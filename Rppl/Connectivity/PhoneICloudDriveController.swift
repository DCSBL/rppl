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

    /// User preference (KVS). Default on.
    private(set) var isSyncEnabled: Bool
    /// Ubiquity container resolved (nil until identity / entitlement ready).
    private(set) var isICloudAvailable = false
    private(set) var statusMessage: String?
    /// Remote packages found via metadata query that need an import choice.
    private(set) var pendingImportSummaries: [RemoteSessionSummary] = []
    /// Present import picker when remote-only set appears.
    private(set) var shouldOfferImport = false
    /// Logbook shows only these session ids while Drive sync is on (Ask-before-import).
    private(set) var acceptedSessionIDs: Set<String> = []

    private var ubiquityContainerURL: URL?
    private var metadataQuery: NSMetadataQuery?
    /// Session ids the user dismissed this run (avoid re-prompt spam until set changes).
    private var dismissedRemoteIDs = Set<String>()
    private var rootSwitchTask: Task<Void, Never>?
    private var isSwitchingRoot = false
    private var metadataHasGathered = false

    private let kvs = NSUbiquitousKeyValueStore.default
    private let fileManager = FileManager.default

    override init() {
        if kvs.object(forKey: AppConstants.iCloudDriveSyncEnabledKVSKey) == nil {
            kvs.set(true, forKey: AppConstants.iCloudDriveSyncEnabledKVSKey)
            kvs.synchronize()
        }
        isSyncEnabled = kvs.bool(forKey: AppConstants.iCloudDriveSyncEnabledKVSKey)
        UserDefaults.standard.set(isSyncEnabled, forKey: AppSettingsKey.iCloudDriveSyncEnabled)
        super.init()
        acceptedSessionIDs = loadAcceptedIDs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquityIdentityChanged),
            name: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvsDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
        kvs.synchronize()
        refreshAvailability()
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
        refreshAvailability()
        applyPreferredRootIfNeeded(reason: "start")
        restartMetadataQueryIfNeeded()
    }

    /// Toggle from Settings. When turning off, caller asks whether to delete Drive copies.
    func setSyncEnabled(_ enabled: Bool, deleteICloudCopies: Bool) async {
        isSyncEnabled = enabled
        kvs.set(enabled, forKey: AppConstants.iCloudDriveSyncEnabledKVSKey)
        kvs.synchronize()
        UserDefaults.standard.set(enabled, forKey: AppSettingsKey.iCloudDriveSyncEnabled)

        refreshAvailability()
        if !enabled {
            stopMetadataQuery()
            pendingImportSummaries = []
            shouldOfferImport = false
            let cloudRoot = iCloudSessionsRoot
            // Always copy down before leaving Drive so the App Group logbook stays complete.
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
            applyPreferredRootIfNeeded(reason: "enable")
            restartMetadataQueryIfNeeded()
        }
    }

    func refreshAvailability() {
        let token = fileManager.ubiquityIdentityToken
        let container = fileManager.url(
            forUbiquityContainerIdentifier: AppConstants.iCloudContainerIdentifier
        )
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
        }
    }

    /// User confirmed import of selected remote session ids.
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
    }

    func dismissImportOffer() {
        dismissedRemoteIDs.formUnion(pendingImportSummaries.map(\.sessionId))
        shouldOfferImport = false
        pendingImportSummaries = []
    }

    /// Watch import / local create — always part of this phone’s logbook.
    func acceptSession(_ sessionId: String) {
        acceptSessions([sessionId])
    }

    func unacceptSession(_ sessionId: String) {
        var next = acceptedSessionIDs
        next.remove(sessionId)
        acceptedSessionIDs = next
        persistAcceptedIDs()
    }

    /// Ids the logbook should show. `nil` = show every package on disk (sync off).
    var logbookFilterIDs: Set<String>? {
        isSyncEnabled && isICloudAvailable ? acceptedSessionIDs : nil
    }

    // MARK: - Private

    private func loadAcceptedIDs() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: AppSettingsKey.iCloudAcceptedSessionIDs) ?? []
        return Set(raw)
    }

    private func persistAcceptedIDs() {
        UserDefaults.standard.set(
            Array(acceptedSessionIDs).sorted(),
            forKey: AppSettingsKey.iCloudAcceptedSessionIDs
        )
    }

    private func acceptSessions(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        acceptedSessionIDs = acceptedSessionIDs.union(ids)
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
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            if copyMissing, let source, fileManager.fileExists(atPath: source.path) {
                let copied = try await coordinatedCopyMissing(from: source, to: destination)
                if !copied.isEmpty {
                    WakeLog.debug(.store, "iCloud migrate \(reason) copied=\(copied.count)")
                }
            }
            PhoneConnectivityService.shared.replaceStoreRoot(destination)
            if isSyncEnabled,
               let cloud = iCloudSessionsRoot,
               destination.standardizedFileURL == cloud.standardizedFileURL {
                let ids = Set((try? SessionRootMigrator.sessionIDs(in: destination)) ?? [])
                acceptSessions(ids)
            }
            statusMessage = nil
            PhoneConnectivityService.shared.bumpSessionsRevision()
        } catch {
            statusMessage = error.localizedDescription
            WakeLog.error(.store, "iCloud migrate \(reason) failed: \(error.localizedDescription)")
        }
    }

    @objc private func ubiquityIdentityChanged() {
        refreshAvailability()
        if isSyncEnabled {
            applyPreferredRootIfNeeded(reason: "identity")
            restartMetadataQueryIfNeeded()
        }
    }

    @objc private func kvsDidChange(_ note: Notification) {
        let enabled = kvs.bool(forKey: AppConstants.iCloudDriveSyncEnabledKVSKey)
        guard enabled != isSyncEnabled else { return }
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppSettingsKey.iCloudDriveSyncEnabled)
        if enabled {
            applyPreferredRootIfNeeded(reason: "kvs")
            restartMetadataQueryIfNeeded()
        } else {
            stopMetadataQuery()
            applyPreferredRootIfNeeded(reason: "kvs-off")
        }
    }

    private func restartMetadataQueryIfNeeded() {
        stopMetadataQuery()
        metadataHasGathered = false
        guard isSyncEnabled, isICloudAvailable, let root = iCloudSessionsRoot else { return }
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

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

    private func stopMetadataQuery() {
        if let query = metadataQuery {
            query.stop()
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
        }
        metadataQuery = nil
        metadataHasGathered = false
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
        guard isSyncEnabled, let root = iCloudSessionsRoot, let query = metadataQuery else {
            pendingImportSummaries = []
            shouldOfferImport = false
            return
        }

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

            guard !acceptedSessionIDs.contains(sessionId),
                  !dismissedRemoteIDs.contains(sessionId)
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

        // Peer delete: accepted package gone from Drive → drop local + unaccept.
        if metadataHasGathered, !remoteIDs.isEmpty {
            let missingFromRemote = acceptedSessionIDs.subtracting(remoteIDs)
            for sessionId in missingFromRemote {
                try? store.deleteSession(sessionId: sessionId)
                unacceptSession(sessionId)
                WakeLog.debug(.store, "peer-delete drop \(sessionId.prefix(8))…")
            }
            if !missingFromRemote.isEmpty {
                PhoneConnectivityService.shared.bumpSessionsRevision()
            }
        }

        pendingImportSummaries = Dictionary(grouping: candidates, by: \.sessionId)
            .compactMap(\.value.first)
            .sorted { $0.startedAt > $1.startedAt }

        shouldOfferImport = !pendingImportSummaries.isEmpty
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
}
