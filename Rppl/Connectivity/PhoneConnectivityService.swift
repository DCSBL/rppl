import Foundation
import WatchConnectivity
import RpplCore
import Observation

@Observable
@MainActor
final class PhoneConnectivityService: NSObject {
    static let shared = PhoneConnectivityService()

    var status = String(localized: "WC idle")
    var syncState: SyncConnectionState = .notActivated
    var sessionsRevision = 0
    /// Raw WCSession flags for device-pair debugging (shown under Sync).
    var wcDebugSummary = "WC -"
    /// Acks queued because Watch was unreachable (or send failed).
    var pendingAckCount: Int { pendingAcks.count }

    private(set) var store: SessionFileStore
    private var pendingAcks = Set<String>()
    private var rootReplaceLock = false

    override init() {
        let root = AppConstants.localPhoneSessionsRoot
        store = SessionFileStore(rootURL: root)
        super.init()
        try? store.ensureRootExists()
        activate()
    }

    /// Swap live session root (App Group ↔ iCloud Documents). Serializes against imports.
    func replaceStoreRoot(_ rootURL: URL) {
        guard !rootReplaceLock else { return }
        rootReplaceLock = true
        defer { rootReplaceLock = false }
        if store.rootURL.standardizedFileURL == rootURL.standardizedFileURL {
            try? store.ensureRootExists()
            return
        }
        let next = SessionFileStore(rootURL: rootURL)
        try? next.ensureRootExists()
        store = next
        sessionsRevision += 1
        WakeLog.debug(.store, "phone store root → \(rootURL.lastPathComponent)")
    }

    func bumpSessionsRevision() {
        sessionsRevision += 1
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = String(localized: "WC unsupported")
            syncState = .unsupported
            WakeLog.error(.sync, "WC unsupported on iPhone")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        WakeLog.debug(.sync, "WC activate requested")
        refreshSyncState()
    }

    func refreshSyncState() {
        let previous = syncState
        syncState = SyncConnectionProbe.current()
        let session = WCSession.default
        let activation: String
        switch session.activationState {
        case .notActivated: activation = "notActivated"
        case .inactive: activation = "inactive"
        case .activated: activation = "activated"
        @unknown default: activation = "unknown"
        }
        wcDebugSummary =
            "paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) " +
            "reachable=\(session.isReachable) activation=\(activation)"
        if previous != syncState {
            WakeLog.debug(.sync, "state \(previous) → \(syncState)")
        }
        WakeLog.debug(.sync, wcDebugSummary)
    }

    private func acknowledge(sessionId: String) {
        let payload: [String: Any] = [AppConstants.wcAckMessageKey: sessionId]
        // Queued delivery survives Watch not reachable / app restart on phone side of WC.
        WCSession.default.transferUserInfo(payload)
        WakeLog.debug(.ack, "queued userInfo \(sessionId.prefix(8))…")

        guard WCSession.default.isReachable else {
            status = String(localized: "Imported \(sessionId.prefix(8)) - Watch not reachable for ack (will retry when reachable)")
            pendingAcks.insert(sessionId)
            WakeLog.debug(.ack, "defer live \(sessionId.prefix(8))… — Watch unreachable pending=\(pendingAcks.count)")
            refreshSyncState()
            return
        }
        WakeLog.debug(.ack, "send live \(sessionId.prefix(8))…")
        WCSession.default.sendMessage(
            payload,
            replyHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.pendingAcks.remove(sessionId)
                    self?.status = String(localized: "Acked \(sessionId.prefix(8))")
                    WakeLog.debug(.ack, "send reply OK \(sessionId.prefix(8))…")
                    self?.refreshSyncState()
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.pendingAcks.insert(sessionId)
                    self?.status = String(localized: "Ack send failed: \(error.localizedDescription)")
                    WakeLog.error(.ack, "send failed \(sessionId.prefix(8))…: \(error.localizedDescription)")
                    self?.refreshSyncState()
                }
            }
        )
        refreshSyncState()
    }

    func flushPendingAcks() {
        guard WCSession.default.isReachable else { return }
        let ids = Array(pendingAcks)
        guard !ids.isEmpty else { return }
        WakeLog.debug(.ack, "flushPendingAcks count=\(ids.count)")
        for id in ids {
            acknowledge(sessionId: id)
        }
    }

    /// Re-queue acks for sessions already imported on phone (heals Watch stuck in transferring).
    func rebroadcastAcksForImportedSessions() {
        guard WCSession.default.activationState == .activated else { return }
        do {
            let ids = try store.listSessionIDs()
            var count = 0
            for id in ids {
                let manifest = try store.readManifest(sessionId: id)
                guard manifest.transferState == .acknowledged else { continue }
                // File imports never came from Watch — do not rebroadcast ack.
                guard manifest.imported == nil else { continue }
                WCSession.default.transferUserInfo([AppConstants.wcAckMessageKey: id])
                count += 1
            }
            if count > 0 {
                WakeLog.debug(.ack, "rebroadcast userInfo for \(count) imported session(s)")
            }
        } catch {
            WakeLog.error(.ack, "rebroadcast failed: \(error.localizedDescription)")
        }
    }

    func importPackage(from url: URL, sessionIdHint: String?) throws {
        WakeLog.debug(.transfer, "import begin hint=\(sessionIdHint.map { String($0.prefix(8)) } ?? "nil")…")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        try store.importTransferPackage(package, intoPhoneStore: store.rootURL)
        sessionsRevision += 1
        let sessionId = sessionIdHint ?? package.manifest.sessionId
        PhoneICloudDriveController.shared.acceptSession(sessionId)
        WakeLog.debug(.transfer, "import OK \(sessionId.prefix(8))…")
        acknowledge(sessionId: sessionId)
        PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
        // Mark first sync before any permission sheets — sync/ack already finished above.
        UserDefaults.standard.set(true, forKey: AppSettingsKey.didImportSessionFromWatch)
        Task {
            await PhonePermissionsController.shared.requestAfterFirstSyncIfNeeded()
        }
    }

    func hasSession(sessionId: String) -> Bool {
        (try? store.listSessionIDs().contains(sessionId)) ?? false
    }

    /// Import a Share export JSON from Files. No Watch ack, no HealthKit, no post-sync permission trigger.
    /// Throws `SessionExportImportError.alreadyImported` when the session id is already on disk.
    @discardableResult
    func importExportedSession(from url: URL) async throws -> String {
        WakeLog.debug(.transfer, "export-file import begin")
        PhoneICloudDriveController.shared.beginImportOfferSuppression()
        defer { PhoneICloudDriveController.shared.endImportOfferSuppression() }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let store = self.store
        let sessionId: String
        do {
            sessionId = try await StoreIO.runOffMain {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let package = try decoder.decode(SessionTransferPackage.self, from: data)
                let id = package.manifest.sessionId
                if FileManager.default.fileExists(
                    atPath: store.sessionDirectory(for: id).path
                ) {
                    throw SessionExportImportError.alreadyImported(sessionId: id)
                }
                try store.importExportedPackage(package, intoPhoneStore: store.rootURL)
                return id
            }
        } catch let error as SessionExportImportError {
            throw error
        } catch {
            throw SessionExportImportError.unreadable(SessionExportImportError.detail(for: error))
        }
        sessionsRevision += 1
        PhoneICloudDriveController.shared.acceptSession(sessionId)
        PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
        WakeLog.debug(.transfer, "export-file import OK \(sessionId.prefix(8))…")
        return sessionId
    }
}

enum SessionExportImportError: Error {
    case alreadyImported(sessionId: String)
    case unreadable(String)

    /// Diagnostic text for alerts — coding path + Foundation debugDescription, not vague localized strings.
    static func detail(for error: Error) -> String {
        if let decoding = error as? DecodingError {
            return decodingDetail(for: decoding)
        }
        if let importError = error as? SessionExportImportError,
           case .unreadable(let message) = importError {
            return message
        }
        let ns = error as NSError
        if let debug = ns.userInfo[NSDebugDescriptionErrorKey] as? String {
            let trimmed = debug.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty { return localized }
        return String(describing: error)
    }

    private static func decodingDetail(for error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return pathPrefixed(context, extraKey: key)
        case .valueNotFound(_, let context):
            return pathPrefixed(context)
        case .typeMismatch(_, let context):
            return pathPrefixed(context)
        case .dataCorrupted(let context):
            var text = pathPrefixed(context)
            if let underlying = context.underlyingError {
                text += " — \(underlying)"
            }
            return text
        @unknown default:
            return String(describing: error)
        }
    }

    private static func pathPrefixed(_ context: DecodingError.Context, extraKey: CodingKey? = nil) -> String {
        let path = codingPathString(
            extraKey.map { context.codingPath + [$0] } ?? context.codingPath
        )
        let debug = context.debugDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return debug }
        if debug.isEmpty { return path }
        return "\(path): \(debug)"
    }

    private static func codingPathString(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
    }
}

extension PhoneConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshSyncState()
            if let error {
                status = String(localized: "WC error: \(error.localizedDescription)")
                WakeLog.error(.sync, "WC activate error: \(error.localizedDescription)")
            } else {
                status = String(localized: "WC activated")
                WakeLog.debug(.sync, "WC activated state=\(activationState.rawValue)")
                rebroadcastAcksForImportedSessions()
                PhoneWatchViewSync.rebroadcastViewUpdates(store: store)
                flushPendingAcks()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let url = file.fileURL
        let hint = file.metadata?[AppConstants.wcSessionFileMetaSessionID] as? String
        WakeLog.debug(.transfer, "didReceive file hint=\(hint.map { String($0.prefix(8)) } ?? "nil")…")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(hint ?? UUID().uuidString)-in.json")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)

        Task { @MainActor in
            do {
                try importPackage(from: dest, sessionIdHint: hint)
                status = String(localized: "Imported session")
            } catch {
                status = String(localized: "Import failed: \(error.localizedDescription)")
                WakeLog.error(.transfer, "import failed: \(error.localizedDescription)")
            }
            refreshSyncState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            if session.isReachable {
                status = String(localized: "Watch reachable")
                WakeLog.debug(.sync, "Watch reachable")
                flushPendingAcks()
            } else {
                status = String(localized: "Watch not reachable - transfers still queue")
                WakeLog.debug(.sync, "Watch not reachable")
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            status = String(localized: "Watch state updated")
            WakeLog.debug(
                .sync,
                "watchState paired=\(session.isPaired) appInstalled=\(session.isWatchAppInstalled)"
            )
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            WakeLog.debug(.sync, "sessionDidBecomeInactive")
            refreshSyncState()
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WakeLog.debug(.sync, "sessionDidDeactivate — reactivating")
        session.activate()
        Task { @MainActor in
            refreshSyncState()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let known = try? WatchViewSyncCodec.decodeSyncRequest(from: message) {
            Task { @MainActor in
                do {
                    let reply = try PhoneWatchViewSync.handleSyncRequest(
                        store: self.store,
                        knownOnWatch: known
                    )
                    let payload = try WatchViewSyncCodec.encodeSyncReply(reply)
                    replyHandler(payload)
                } catch {
                    WakeLog.error(.sync, "syncRequest failed: \(error.localizedDescription)")
                    replyHandler([:])
                }
            }
            return
        }
        replyHandler([:])
    }
}
