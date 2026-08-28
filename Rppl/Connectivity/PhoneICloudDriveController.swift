import Foundation
import RpplCore
import Observation

/// Native iCloud Documents wiring for the phone logbook.
///
/// When enabled and ubiquity is available, the live `SessionFileStore` root is
/// the app’s iCloud Drive `Documents/Sessions` folder — Apple syncs creates,
/// edits, and deletes. Discovery of not-yet-local packages uses `NSMetadataQuery`.
@Observable
@MainActor
final class PhoneICloudDriveController: NSObject {
    static let shared = PhoneICloudDriveController()

    /// User preference (UserDefaults). Default on.
    private(set) var isSyncEnabled: Bool
    /// Ubiquity container resolved (nil until identity / entitlement ready).
    private(set) var isICloudAvailable = false
    private(set) var statusMessage: String?
    /// Remote packages found via metadata query that need an import choice.
    private(set) var pendingImportSummaries: [RemoteSessionSummary] = []
    /// Present import picker when remote-only set appears (background discovery).
    private(set) var shouldOfferImport = false
    /// True while enable/disable migration runs (Settings spinner).
    private(set) var isApplyingSyncChange = false
    /// Blocks auto-presenting import sheet during manual JSON import / root churn.
    private(set) var suppressImportOffer = false
    /// Logbook shows only these session ids while Drive sync is on (Ask-before-import).
    private(set) var acceptedSessionIDs: Set<String> = []
    /// Hidden on this phone while the package may remain in iCloud Drive.
    private(set) var hiddenSessionIDs: Set<String> = []

    private var ubiquityContainerURL: URL?
    private var metadataQuery: NSMetadataQuery?
    /// Session ids the user dismissed this run (avoid re-prompt spam until set changes).
    private var dismissedRemoteIDs = Set<String>()
    private var rootSwitchTask: Task<Void, Never>?
    private var isSwitchingRoot = false
    private var metadataHasGathered = false
    private var suppressMetadataRebuild = false

    private let fileManager = FileManager.default
    private var defaults: UserDefaults { .standard }

    override init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppSettingsKey.iCloudDriveSyncEnabled) == nil {
            defaults.set(true, forKey: AppSettingsKey.iCloudDriveSyncEnabled)
        }
        isSyncEnabled = defaults.bool(forKey: AppSettingsKey.iCloudDriveSyncEnabled)
        super.init()
        acceptedSessionIDs = loadAcceptedIDs()
        hiddenSessionIDs = loadHiddenIDs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquityIdentityChanged),
            name: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil
        )
        Task { @MainActor in
            await refreshAvailability()
        }
    }

    var iCloudSessionsRoot: URL? {
        ubiquityContainerURL.map { AppConstants.iCloudDocumentsSessionsRoot(containerURL: $0) }
    }

    /// Preferred live store root for the current preference + availability.
    func preferredSessionsRoot() -> URL {
        if isSyncEnabled, let iCloudSessionsRoot {
            return iCloudSessionsRoot
        }
        return AppConstants.localPhoneSessionsRoot
    }

    func start() {
        Task { @MainActor in
            await refreshAvailability()
            applyPreferredRootIfNeeded(reason: "start")
            await uploadLocalOnlyPackagesIfNeeded(reason: "start")
            await restartMetadataQueryIfNeeded()
        }
    }

    /// Call synchronously from Settings before `Task { await setSyncEnabled }` so the spinner replaces the toggle immediately.
    func markApplyingSyncChangeForUI() {
        isApplyingSyncChange = true
    }

    /// Toggle from Settings. When turning off, caller asks whether to delete Drive copies.
    func setSyncEnabled(_ enabled: Bool, deleteICloudCopies: Bool) async {
        if !isApplyingSyncChange {
            isApplyingSyncChange = true
        }
        defer { isApplyingSyncChange = false }

        // Paint spinner before ubiquity / file I/O (first enable can block for seconds).
        try? await Task.sleep(for: .milliseconds(50))

        if !enabled {
            let cloudRoot = iCloudSessionsRoot
            isSyncEnabled = false
            defaults.set(false, forKey: AppSettingsKey.iCloudDriveSyncEnabled)

            suppressMetadataRebuild = true
            defer { suppressMetadataRebuild = false }

            pendingImportSummaries = []
            shouldOfferImport = false
            await stopMetadataQuery()
            await migrateLiveRoot(
                to: AppConstants.localPhoneSessionsRoot,
                from: cloudRoot,
                copyMissing: true,
                reason: "disable"
            )
            if deleteICloudCopies, let cloudRoot {
                await coordinatedRemoveAll(at: cloudRoot)
            }
        } else {
            isSyncEnabled = true
            defaults.set(true, forKey: AppSettingsKey.iCloudDriveSyncEnabled)

            await refreshAvailability()
            let preferred = preferredSessionsRoot()
            let current = PhoneConnectivityService.shared.store.rootURL
            if preferred.standardizedFileURL != current.standardizedFileURL {
                await migrateLiveRoot(
                    to: preferred,
                    from: current,
                    copyMissing: true,
                    reason: "enable"
                )
            } else {
                try? await Self.ensureDirectoryExists(preferred)
                try? PhoneConnectivityService.shared.store.ensureRootExists()
            }
            await uploadLocalOnlyPackagesIfNeeded(reason: "enable")
            await restartMetadataQueryIfNeeded()
        }
    }

    func beginImportOfferSuppression() {
        suppressImportOffer = true
    }

    func endImportOfferSuppression() {
        suppressImportOffer = false
    }

    func refreshAvailability() async {
        let token = fileManager.ubiquityIdentityToken
        // First call can block for seconds — keep off MainActor.
        let container = await Self.resolveUbiquityContainerURL()
        ubiquityContainerURL = container
        isICloudAvailable = token != nil && container != nil
        if !isICloudAvailable {
            statusMessage = String(localized: "iCloud Drive unavailable")
        } else {
            statusMessage = nil
        }
        WakeLog.debug(
            .store,
            "iCloud available=\(isICloudAvailable) enabled=\(isSyncEnabled) container=\(container != nil)"
        )
    }

    private static func resolveUbiquityContainerURL() async -> URL? {
        await Task.detached(priority: .userInitiated) {
            FileManager.default.url(
                forUbiquityContainerIdentifier: AppConstants.iCloudContainerIdentifier
            )
        }.value
    }

    private static func ensureDirectoryExists(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }.value
    }

    func applyPreferredRootIfNeeded(reason: String) {
        guard !isSwitchingRoot else { return }
        let preferred = preferredSessionsRoot()
        let current = PhoneConnectivityService.shared.store.rootURL
        guard preferred.standardizedFileURL != current.standardizedFileURL else {
            try? PhoneConnectivityService.shared.store.ensureRootExists()
            return
        }
        rootSwitchTask?.cancel()
        rootSwitchTask = Task { @MainActor in
            await migrateLiveRoot(
                to: preferred,
                from: current,
                copyMissing: true,
                reason: reason
            )
            await uploadLocalOnlyPackagesIfNeeded(reason: reason)
        }
    }

    private func uploadLocalOnlyPackagesIfNeeded(reason: String) async {
        guard isSyncEnabled, let cloudRoot = iCloudSessionsRoot else { return }
        let localRoot = AppConstants.localPhoneSessionsRoot
        let localExists = await Task.detached(priority: .userInitiated) {
            FileManager.default.fileExists(atPath: localRoot.path)
        }.value
        guard localRoot.standardizedFileURL != cloudRoot.standardizedFileURL,
              localExists
        else {
            if PhoneConnectivityService.shared.store.rootURL.standardizedFileURL
                == cloudRoot.standardizedFileURL {
                await reconcileAcceptedWithDisk()
            }
            return
        }
        do {
            try await Self.ensureDirectoryExists(cloudRoot)
            let copied = try await coordinatedCopyMissing(from: localRoot, to: cloudRoot)
            if !copied.isEmpty {
                WakeLog.debug(.store, "iCloud upload-all \(reason) copied=\(copied.count)")
                PhoneConnectivityService.shared.bumpSessionsRevision()
            }
            await reconcileAcceptedWithDisk(in: cloudRoot)
        } catch {
            statusMessage = error.localizedDescription
            WakeLog.error(
                .store,
                "iCloud upload-all \(reason) failed: \(error.localizedDescription)"
            )
        }
    }

    func importSelectedRemoteSessions(_ sessionIds: Set<String>) async {
        guard let root = iCloudSessionsRoot else { return }
        for sessionId in sessionIds {
            let dir = root.appendingPathComponent(sessionId, isDirectory: true)
            await downloadUbiquitousItem(at: dir)
        }
        acceptSessions(sessionIds)
        dismissedRemoteIDs.subtract(sessionIds)
        rebuildPendingImportsFromQuery()
        PhoneConnectivityService.shared.bumpSessionsRevision()
        for sessionId in sessionIds {
            PhoneWatchViewSync.pushViewUpdate(
                store: PhoneConnectivityService.shared.store,
                sessionId: sessionId
            )
        }
    }

    func dismissImportOffer() {
        dismissedRemoteIDs.formUnion(pendingImportSummaries.map(\.sessionId))
        shouldOfferImport = false
        pendingImportSummaries = []
    }

    /// Settings → Import session: iCloud picker even when auto-offer was dismissed.
    func summariesForManualImport() -> [RemoteSessionSummary] {
        collectRemoteImportSummaries(ignoreDismissed: true)
    }

    func acceptSession(_ sessionId: String) {
        acceptSessions([sessionId])
    }

    func unacceptSession(_ sessionId: String) {
        var next = acceptedSessionIDs
        next.remove(sessionId)
        acceptedSessionIDs = next
        persistAcceptedIDs()
    }

    /// Removes a session from this phone’s logbook while leaving the iCloud Drive copy.
    func hideSessionFromLogbook(_ sessionId: String) {
        unacceptSession(sessionId)
        hiddenSessionIDs.insert(sessionId)
        persistHiddenIDs()
        PhoneConnectivityService.shared.bumpSessionsRevision()
        WakeLog.debug(.store, "hide session from logbook \(sessionId.prefix(8))…")
    }

    /// Permanently deletes a session package, using file coordination when on iCloud Drive.
    func deleteSessionPermanently(_ sessionId: String) async throws {
        let store = PhoneConnectivityService.shared.store
        let dir = store.sessionDirectory(for: sessionId)
        guard fileManager.fileExists(atPath: dir.path) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        try await coordinatedDeleteSession(at: dir)
        hiddenSessionIDs.remove(sessionId)
        persistHiddenIDs()
        unacceptSession(sessionId)
        PhoneConnectivityService.shared.bumpSessionsRevision()
        WakeLog.debug(.store, "permanent delete session \(sessionId.prefix(8))…")
    }

    func clearHiddenSession(_ sessionId: String) {
        guard hiddenSessionIDs.contains(sessionId) else { return }
        hiddenSessionIDs.remove(sessionId)
        persistHiddenIDs()
    }

    var logbookFilterIDs: Set<String>? {
        isSyncEnabled && isICloudAvailable ? acceptedSessionIDs : nil
    }

    // MARK: - Private

    private func loadAcceptedIDs() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: AppSettingsKey.iCloudAcceptedSessionIDs) ?? []
        return Set(raw)
    }

    private func loadHiddenIDs() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: AppSettingsKey.iCloudHiddenSessionIDs) ?? []
        return Set(raw)
    }

    private func persistAcceptedIDs() {
        UserDefaults.standard.set(
            Array(acceptedSessionIDs).sorted(),
            forKey: AppSettingsKey.iCloudAcceptedSessionIDs
        )
    }

    private func persistHiddenIDs() {
        UserDefaults.standard.set(
            Array(hiddenSessionIDs).sorted(),
            forKey: AppSettingsKey.iCloudHiddenSessionIDs
        )
    }

    private func acceptSessions(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        hiddenSessionIDs.subtract(ids)
        persistHiddenIDs()
        acceptedSessionIDs = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: acceptedSessionIDs,
            localIDs: ids,
            hiddenFromLogbook: hiddenSessionIDs
        )
        persistAcceptedIDs()
    }

    private func reconcileAcceptedWithDisk(in root: URL? = nil) async {
        let scanRoot = root ?? PhoneConnectivityService.shared.store.rootURL
        let disk = await Task.detached(priority: .userInitiated) {
            Set((try? SessionRootMigrator.sessionIDs(in: scanRoot)) ?? [])
        }.value
        guard !disk.isEmpty else { return }
        acceptedSessionIDs = ICloudLogbookPolicy.reconcileAccepted(
            previousAccepted: acceptedSessionIDs,
            localIDs: disk,
            hiddenFromLogbook: hiddenSessionIDs
        )
        persistAcceptedIDs()
    }

    private func migrateLiveRoot(
        to destination: URL,
        from source: URL?,
        copyMissing: Bool,
        reason: String
    ) async {
        isSwitchingRoot = true
        defer { isSwitchingRoot = false }
        do {
            try await Self.ensureDirectoryExists(destination)
            if copyMissing, let source {
                let sourceExists = await Task.detached(priority: .userInitiated) {
                    FileManager.default.fileExists(atPath: source.path)
                }.value
                if sourceExists {
                    let copied = try await coordinatedCopyMissing(from: source, to: destination)
                    if !copied.isEmpty {
                        WakeLog.debug(.store, "iCloud migrate \(reason) copied=\(copied.count)")
                    }
                }
            }
            PhoneConnectivityService.shared.replaceStoreRoot(destination)
            if isSyncEnabled,
               let cloud = iCloudSessionsRoot,
               destination.standardizedFileURL == cloud.standardizedFileURL {
                await reconcileAcceptedWithDisk(in: destination)
            }
            statusMessage = nil
            PhoneConnectivityService.shared.bumpSessionsRevision()
        } catch {
            statusMessage = error.localizedDescription
            WakeLog.error(.store, "iCloud migrate \(reason) failed: \(error.localizedDescription)")
        }
    }

    @objc private func ubiquityIdentityChanged() {
        Task { @MainActor in
            await refreshAvailability()
            if isSyncEnabled {
                applyPreferredRootIfNeeded(reason: "identity")
                await restartMetadataQueryIfNeeded()
            }
        }
    }

    private func restartMetadataQueryIfNeeded() async {
        await stopMetadataQuery()
        metadataHasGathered = false
        guard isSyncEnabled, isICloudAvailable, let root = iCloudSessionsRoot else { return }
        try? await Self.ensureDirectoryExists(root)

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K ENDSWITH %@",
            NSMetadataItemFSNameKey,
            "manifest.json"
        )
        metadataQuery = query

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        query.start()
        WakeLog.debug(.store, "NSMetadataQuery started for Sessions manifests")
    }

    private func stopMetadataQuery() async {
        guard let query = metadataQuery else {
            metadataHasGathered = false
            return
        }
        metadataQuery = nil
        metadataHasGathered = false
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        await Task.detached(priority: .userInitiated) {
            query.stop()
        }.value
    }

    @objc private func metadataQueryDidFinishGathering(_ note: Notification) {
        metadataHasGathered = true
        metadataQueryDidUpdate(note)
    }

    @objc private func metadataQueryDidUpdate(_ note: Notification) {
        guard let query = note.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        rebuildPendingImportsFromQuery()
    }

    private func rebuildPendingImportsFromQuery() {
        guard !suppressMetadataRebuild else { return }
        guard isSyncEnabled, iCloudSessionsRoot != nil, metadataQuery != nil else {
            pendingImportSummaries = []
            shouldOfferImport = false
            return
        }

        pendingImportSummaries = collectRemoteImportSummaries(ignoreDismissed: false)
        shouldOfferImport = !suppressImportOffer && !pendingImportSummaries.isEmpty
    }

    private func collectRemoteImportSummaries(ignoreDismissed: Bool) -> [RemoteSessionSummary] {
        guard isSyncEnabled, let root = iCloudSessionsRoot, let query = metadataQuery else {
            return []
        }

        let dismissed = ignoreDismissed ? Set<String>() : dismissedRemoteIDs
        var remoteIDs = Set<String>()
        var candidates: [RemoteSessionSummary] = []
        let store = PhoneConnectivityService.shared.store

        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }
            let sessionDir = url.deletingLastPathComponent()
            guard sessionDir.deletingLastPathComponent().standardizedFileURL
                == root.standardizedFileURL
            else {
                continue
            }
            let sessionId = sessionDir.lastPathComponent
            remoteIDs.insert(sessionId)

            guard ICloudLogbookPolicy.remoteImportCandidates(
                remoteMetadata: [sessionId],
                accepted: acceptedSessionIDs,
                dismissed: dismissed
            ).contains(sessionId)
            else {
                continue
            }

            if let summary = readSummaryCoordinated(at: sessionDir) {
                candidates.append(summary)
            } else {
                Task { @MainActor in
                    await downloadUbiquitousItem(at: sessionDir)
                }
                candidates.append(
                    RemoteSessionSummary(sessionId: sessionId, startedAt: Date.distantPast)
                )
            }
        }

        if !ignoreDismissed {
            let localOnDisk = Set((try? store.listSessionIDs()) ?? [])
            // Anything already on the live root belongs in this phone’s logbook unless hidden.
            let autoAccept = localOnDisk.subtracting(hiddenSessionIDs)
            if !autoAccept.isEmpty {
                acceptSessions(autoAccept)
            }
            let peerDeletes = ICloudLogbookPolicy.peerDeleteCandidates(
                accepted: acceptedSessionIDs,
                remoteMetadata: remoteIDs,
                localOnDisk: localOnDisk,
                metadataGatherComplete: metadataHasGathered && !isSwitchingRoot
            )
            for sessionId in peerDeletes {
                try? store.deleteSession(sessionId: sessionId)
                unacceptSession(sessionId)
                clearHiddenSession(sessionId)
                WakeLog.debug(.store, "peer-delete drop \(sessionId.prefix(8))…")
            }
            if !peerDeletes.isEmpty {
                PhoneConnectivityService.shared.bumpSessionsRevision()
            }
        }

        return Dictionary(grouping: candidates, by: \.sessionId)
            .compactMap(\.value.first)
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func readSummaryCoordinated(at sessionDir: URL) -> RemoteSessionSummary? {
        var summary: RemoteSessionSummary?
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: sessionDir, options: [], error: &error) { url in
            summary = try? RemoteSessionSummaryReader.read(sessionDirectory: url)
        }
        return summary
    }

    private func downloadUbiquitousItem(at url: URL) async {
        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            WakeLog.error(.store, "download ubiquitous failed: \(error.localizedDescription)")
        }
    }

    private func coordinatedCopyMissing(from source: URL, to destination: URL) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var result: Result<[String], Error> = .success([])
                coordinator.coordinate(
                    readingItemAt: source,
                    options: [],
                    writingItemAt: destination,
                    options: [.forMerging],
                    error: &coordinatorError
                ) { readURL, writeURL in
                    do {
                        let copied = try SessionRootMigrator.copyMissingPackages(
                            from: readURL,
                            to: writeURL
                        )
                        result = .success(copied)
                    } catch {
                        result = .failure(error)
                    }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else {
                    continuation.resume(with: result)
                }
            }
        }
    }

    private func coordinatedRemoveAll(at root: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var error: NSError?
                coordinator.coordinate(
                    writingItemAt: root,
                    options: [.forDeleting],
                    error: &error
                ) { url in
                    try? SessionRootMigrator.removeAllPackages(at: url)
                }
                if let error {
                    WakeLog.error(.store, "remove iCloud Sessions: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private func coordinatedDeleteSession(at sessionDir: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordinatorError: NSError?
                var result: Result<Void, Error> = .success(())
                coordinator.coordinate(
                    writingItemAt: sessionDir,
                    options: [.forDeleting],
                    error: &coordinatorError
                ) { url in
                    do {
                        try FileManager.default.removeItem(at: url)
                        result = .success(())
                    } catch {
                        result = .failure(error)
                    }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else {
                    continuation.resume(with: result)
                }
            }
        }
    }
}
