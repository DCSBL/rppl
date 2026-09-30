import Foundation
import WatchConnectivity
import RpplCore
import Observation

@Observable
@MainActor
final class WatchTransferService: NSObject {
    static let shared = WatchTransferService()

    var lastMessage = String(localized: "WC idle")
    var syncState: SyncConnectionState = .notActivated
    var pendingTransferCount = 0
    /// Bumps on ack / pending refresh so summary sync line re-renders.
    private(set) var syncStatusRevision = 0

    private var store: SessionFileStore?
    private let tempDir: URL
    /// Sessions whose package is being built off-main — not yet in WC's outstanding list.
    private var packagingSessionIds: Set<String> = []

    override init() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wc-out", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastMessage = String(localized: "WC unsupported")
            syncState = .unsupported
            WakeLog.error(.sync, "WC unsupported on Watch")
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
        refreshPendingCount()
        if previous != syncState {
            WakeLog.debug(.sync, "state \(previous) → \(syncState)")
        }
    }

    func refreshPendingCount() {
        let fileStore = store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        pendingTransferCount = (try? fileStore.sessionsNeedingTransfer().count) ?? 0
        syncStatusRevision &+= 1
    }

    /// Locked summary copy: Syncing… until phone ack, then Synced.
    func isSessionSynced(sessionId: String) -> Bool {
        let fileStore = store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        guard let manifest = try? fileStore.readManifest(sessionId: sessionId) else {
            return false
        }
        return manifest.transferState == .acknowledged
    }

    func enqueueTransfer(sessionId: String, store: SessionFileStore) {
        WakeLog.debug(.transfer, "enqueue \(sessionId.prefix(8))…")
        self.store = store
        Task {
            await WatchSyncNotifier.requestAuthorizationIfNeeded()
        }
        transferPending()
    }

    func transferPending() {
        if store == nil {
            store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        }
        guard let store else { return }
        refreshSyncState()

        do {
            let pending = try store.sessionsNeedingTransfer()
            pendingTransferCount = pending.count
            lastMessage = String(localized: "Pending transfers: \(pending.count)")
            WakeLog.debug(.transfer, "transferPending count=\(pending.count)")
            for manifest in pending {
                transfer(sessionId: manifest.sessionId, store: store)
            }
            refreshPendingCount()
        } catch {
            lastMessage = String(localized: "Transfer list error: \(error.localizedDescription)")
            WakeLog.error(.transfer, "list error: \(error.localizedDescription)")
        }
    }

    /// Checks run on the main actor; building and encoding the package (every stream of a
    /// multi-hour session) runs off it so the stop summary and idle UI stay responsive.
    private func transfer(sessionId: String, store: SessionFileStore) {
        guard WCSession.default.activationState == .activated else {
            lastMessage = String(localized: "WC not activated - will retry")
            WakeLog.debug(.transfer, "skip \(sessionId.prefix(8))… — WC not activated")
            refreshSyncState()
            return
        }

        let alreadyQueued = WCSession.default.outstandingFileTransfers.contains { fileTransfer in
            (fileTransfer.file.metadata?[AppConstants.wcSessionFileMetaSessionID] as? String) == sessionId
        }
        if alreadyQueued {
            WakeLog.debug(.transfer, "skip \(sessionId.prefix(8))… — already in WC queue")
            return
        }
        guard !packagingSessionIds.contains(sessionId) else {
            WakeLog.debug(.transfer, "skip \(sessionId.prefix(8))… — package being built")
            return
        }
        packagingSessionIds.insert(sessionId)

        let directory = tempDir
        Task {
            defer { packagingSessionIds.remove(sessionId) }
            do {
                let packageURL = try await StoreIO.runOffMain {
                    try store.markTransferring(sessionId: sessionId)
                    return try store.zipSessionForTransfer(sessionId: sessionId, to: directory)
                }
                WCSession.default.transferFile(packageURL, metadata: [
                    AppConstants.wcSessionFileMetaSessionID: sessionId
                ])
                lastMessage = String(localized: "Queued \(sessionId.prefix(8))…")
                WakeLog.debug(.transfer, "queued file \(sessionId.prefix(8))…")
            } catch {
                lastMessage = String(localized: "Transfer error: \(error.localizedDescription)")
                WakeLog.error(.transfer, "transfer \(sessionId.prefix(8))…: \(error.localizedDescription)")
                try? store.markReadyToTransfer(sessionId: sessionId)
            }
            refreshPendingCount()
        }
    }
}

extension WatchTransferService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshSyncState()
            if let error {
                lastMessage = String(localized: "WC activate error: \(error.localizedDescription)")
                WakeLog.error(.sync, "WC activate error: \(error.localizedDescription)")
            } else {
                lastMessage = String(localized: "WC activated")
                WakeLog.debug(.sync, "WC activated state=\(activationState.rawValue)")
                transferPending()
                WatchViewSyncService.shared.requestViewSyncIfReachable()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            if session.isReachable {
                lastMessage = String(localized: "iPhone reachable")
                WakeLog.debug(.sync, "iPhone reachable")
                transferPending()
                WatchViewSyncService.shared.requestViewSyncIfReachable()
            } else {
                lastMessage = String(localized: "iPhone not reachable - transfers will queue")
                WakeLog.debug(.sync, "iPhone not reachable — queue transfers")
            }
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in
            WakeLog.debug(.sync, "companionAppInstalled=\(session.isCompanionAppInstalled)")
            refreshSyncState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if message[AppConstants.wcAckMessageKey] != nil {
                applyAckMessage(message)
                return
            }
            WatchViewSyncService.shared.handleIncomingMessage(message)
        }
    }

    /// Phone `sendMessage` uses a replyHandler — WC delivers here, not `didReceiveMessage`.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[AppConstants.wcAckMessageKey] != nil {
            replyHandler([AppConstants.wcAckMessageKey: "ok"])
            Task { @MainActor in
                applyAckMessage(message)
            }
            return
        }
        if WatchViewSyncCodec.messageType(in: message) != nil {
            replyHandler([:])
            Task { @MainActor in
                WatchViewSyncService.shared.handleIncomingMessage(message)
            }
            return
        }
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if userInfo[AppConstants.wcAckMessageKey] != nil {
                applyAckMessage(userInfo)
                return
            }
            WatchViewSyncService.shared.handleIncomingMessage(userInfo)
        }
    }

    @MainActor
    private func applyAckMessage(_ message: [String: Any]) {
        guard let ack = message[AppConstants.wcAckMessageKey] as? String else {
            WakeLog.debug(.ack, "ignored non-ack message keys=\(Array(message.keys))")
            return
        }
        WakeLog.debug(.ack, "received ack \(ack.prefix(8))…")
        let store = self.store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        do {
            let newlyAcknowledged = try store.markAcknowledged(sessionId: ack)
            lastMessage = String(localized: "Acked \(ack.prefix(8))")
            WakeLog.debug(
                .ack,
                "markAcknowledged OK \(ack.prefix(8))… newly=\(newlyAcknowledged)"
            )
            refreshPendingCount()
            // Phone rebroadcasts / dual-channel acks must not spam banners.
            if newlyAcknowledged {
                WatchSyncNotifier.notifySyncCompleted(sessionId: ack)
                WatchViewSyncService.shared.pruneAfterAck(sessionId: ack)
            }
        } catch {
            lastMessage = String(localized: "Ack failed: \(error.localizedDescription)")
            WakeLog.error(.ack, "markAcknowledged: \(error.localizedDescription)")
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            let sessionId = fileTransfer.file.metadata?[AppConstants.wcSessionFileMetaSessionID] as? String
            if let error {
                lastMessage = String(localized: "Transfer failed (kept on Watch): \(error.localizedDescription)")
                WakeLog.error(
                    .transfer,
                    "failed (kept) \(sessionId.map { String($0.prefix(8)) } ?? "?"): \(error.localizedDescription)"
                )
                if let sessionId {
                    let store = self.store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
                    try? store.markReadyToTransfer(sessionId: sessionId)
                    WakeLog.debug(.store, "re-queued readyToTransfer \(sessionId.prefix(8))…")
                }
            } else {
                lastMessage = String(localized: "File delivered - awaiting phone ack")
                WakeLog.debug(
                    .transfer,
                    "delivered \(sessionId.map { String($0.prefix(8)) } ?? "?")… — awaiting ack"
                )
            }
            refreshSyncState()
        }
    }
}
