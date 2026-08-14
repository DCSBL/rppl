import Foundation
import WatchConnectivity
import RpplCore
import Observation

@Observable
@MainActor
final class WatchTransferService: NSObject {
    static let shared = WatchTransferService()

    var lastMessage = "WC idle"
    var syncState: SyncConnectionState = .notActivated
    var pendingTransferCount = 0

    private var store: SessionFileStore?
    private let tempDir: URL

    override init() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wc-out", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastMessage = "WC unsupported"
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
    }

    func enqueueTransfer(sessionId: String, store: SessionFileStore) {
        WakeLog.debug(.transfer, "enqueue \(sessionId.prefix(8))…")
        self.store = store
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
            lastMessage = "Pending transfers: \(pending.count)"
            WakeLog.debug(.transfer, "transferPending count=\(pending.count)")
            for manifest in pending {
                do {
                    try transfer(sessionId: manifest.sessionId, store: store)
                } catch {
                    lastMessage = "Transfer error: \(error.localizedDescription)"
                    WakeLog.error(
                        .transfer,
                        "transfer \(manifest.sessionId.prefix(8))…: \(error.localizedDescription)"
                    )
                    try? store.markReadyToTransfer(sessionId: manifest.sessionId)
                }
            }
            refreshPendingCount()
        } catch {
            lastMessage = "Transfer list error: \(error.localizedDescription)"
            WakeLog.error(.transfer, "list error: \(error.localizedDescription)")
        }
    }

    private func transfer(sessionId: String, store: SessionFileStore) throws {
        guard WCSession.default.activationState == .activated else {
            lastMessage = "WC not activated — will retry"
            WakeLog.debug(.transfer, "skip \(sessionId.prefix(8))… — WC not activated")
            refreshSyncState()
            return
        }

        try store.markTransferring(sessionId: sessionId)
        let packageURL = try store.zipSessionForTransfer(sessionId: sessionId, to: tempDir)
        WCSession.default.transferFile(packageURL, metadata: [
            AppConstants.wcSessionFileMetaSessionID: sessionId
        ])
        lastMessage = "Queued \(sessionId.prefix(8))…"
        WakeLog.debug(.transfer, "queued file \(sessionId.prefix(8))…")
        refreshPendingCount()
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
                lastMessage = "WC activate error: \(error.localizedDescription)"
                WakeLog.error(.sync, "WC activate error: \(error.localizedDescription)")
            } else {
                lastMessage = "WC activated"
                WakeLog.debug(.sync, "WC activated state=\(activationState.rawValue)")
                transferPending()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            if session.isReachable {
                lastMessage = "iPhone reachable"
                WakeLog.debug(.sync, "iPhone reachable")
                transferPending()
            } else {
                lastMessage = "iPhone not reachable — transfers will queue"
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
            applyAckMessage(message)
        }
    }

    /// Phone `sendMessage` uses a replyHandler — WC delivers here, not `didReceiveMessage`.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler([AppConstants.wcAckMessageKey: "ok"])
        Task { @MainActor in
            applyAckMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            applyAckMessage(userInfo)
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
            try store.markAcknowledged(sessionId: ack)
            lastMessage = "Acked \(ack.prefix(8))"
            WakeLog.debug(.ack, "markAcknowledged OK \(ack.prefix(8))…")
            refreshPendingCount()
        } catch {
            lastMessage = "Ack failed: \(error.localizedDescription)"
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
                lastMessage = "Transfer failed (kept on Watch): \(error.localizedDescription)"
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
                lastMessage = "File delivered — awaiting phone ack"
                WakeLog.debug(
                    .transfer,
                    "delivered \(sessionId.map { String($0.prefix(8)) } ?? "?")… — awaiting ack"
                )
            }
            refreshSyncState()
        }
    }
}
