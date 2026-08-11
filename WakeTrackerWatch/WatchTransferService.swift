import Foundation
import WatchConnectivity
import WakeTrackerCore
import Observation

@Observable
@MainActor
final class WatchTransferService: NSObject {
    static let shared = WatchTransferService()

    var lastMessage = "WC idle"

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
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func enqueueTransfer(sessionId: String, store: SessionFileStore) {
        self.store = store
        transferPending()
    }

    func transferPending() {
        if store == nil {
            store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
        }
        guard let store else { return }

        do {
            let pending = try store.sessionsNeedingTransfer()
            lastMessage = "Pending transfers: \(pending.count)"
            for manifest in pending {
                try transfer(sessionId: manifest.sessionId, store: store)
            }
        } catch {
            lastMessage = "Transfer list error: \(error.localizedDescription)"
        }
    }

    private func transfer(sessionId: String, store: SessionFileStore) throws {
        guard WCSession.default.activationState == .activated else {
            lastMessage = "WC not activated — will retry"
            return
        }

        try store.markTransferring(sessionId: sessionId)
        let packageURL = try store.zipSessionForTransfer(sessionId: sessionId, to: tempDir)
        WCSession.default.transferFile(packageURL, metadata: [
            AppConstants.wcSessionFileMetaSessionID: sessionId
        ])
        lastMessage = "Queued \(sessionId.prefix(8))…"
    }
}

extension WatchTransferService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastMessage = "WC activate error: \(error.localizedDescription)"
            } else {
                lastMessage = "WC activated"
                transferPending()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let ack = message[AppConstants.wcAckMessageKey] as? String else { return }
            let store = self.store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
            do {
                try store.markAcknowledged(sessionId: ack)
                lastMessage = "Acked \(ack.prefix(8))"
            } catch {
                lastMessage = "Ack failed: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastMessage = "Transfer failed (kept on Watch): \(error.localizedDescription)"
                if let sessionId = fileTransfer.file.metadata?[AppConstants.wcSessionFileMetaSessionID] as? String {
                    let store = self.store ?? SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
                    try? store.markReadyToTransfer(sessionId: sessionId)
                }
            } else {
                lastMessage = "File delivered — awaiting phone ack"
            }
        }
    }
}
