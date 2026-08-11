import Foundation
import WatchConnectivity
import WakeTrackerCore
import Observation

@Observable
@MainActor
final class PhoneConnectivityService: NSObject {
    static let shared = PhoneConnectivityService()

    var status = "WC idle"
    var syncState: SyncConnectionState = .notActivated
    var sessionsRevision = 0

    let store: SessionFileStore
    private var pendingAcks = Set<String>()

    override init() {
        let root = AppConstants.appGroupSessionsRoot ?? AppConstants.documentsSessionsRoot
        store = SessionFileStore(rootURL: root)
        try? store.ensureRootExists()
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = "WC unsupported"
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
        if previous != syncState {
            WakeLog.debug(.sync, "state \(previous) → \(syncState)")
        }
    }

    private func acknowledge(sessionId: String) {
        guard WCSession.default.isReachable else {
            status = "Imported \(sessionId.prefix(8)) — Watch not reachable for ack (will retry when reachable)"
            pendingAcks.insert(sessionId)
            WakeLog.debug(.ack, "defer \(sessionId.prefix(8))… — Watch unreachable pending=\(pendingAcks.count)")
            refreshSyncState()
            return
        }
        WakeLog.debug(.ack, "send \(sessionId.prefix(8))…")
        WCSession.default.sendMessage(
            [AppConstants.wcAckMessageKey: sessionId],
            replyHandler: { _ in
                WakeLog.debug(.ack, "send reply OK \(sessionId.prefix(8))…")
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.pendingAcks.insert(sessionId)
                    self?.status = "Ack send failed: \(error.localizedDescription)"
                    WakeLog.error(.ack, "send failed \(sessionId.prefix(8))…: \(error.localizedDescription)")
                    self?.refreshSyncState()
                }
            }
        )
        pendingAcks.remove(sessionId)
        status = "Acked \(sessionId.prefix(8))"
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

    func importPackage(from url: URL, sessionIdHint: String?) throws {
        WakeLog.debug(.transfer, "import begin hint=\(sessionIdHint.map { String($0.prefix(8)) } ?? "nil")…")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        try store.importTransferPackage(package, intoPhoneStore: store.rootURL)
        sessionsRevision += 1
        let sessionId = sessionIdHint ?? package.manifest.sessionId
        WakeLog.debug(.transfer, "import OK \(sessionId.prefix(8))…")
        acknowledge(sessionId: sessionId)
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
                status = "WC error: \(error.localizedDescription)"
                WakeLog.error(.sync, "WC activate error: \(error.localizedDescription)")
            } else {
                status = "WC activated"
                WakeLog.debug(.sync, "WC activated state=\(activationState.rawValue)")
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
                status = "Imported session"
            } catch {
                status = "Import failed: \(error.localizedDescription)"
                WakeLog.error(.transfer, "import failed: \(error.localizedDescription)")
            }
            refreshSyncState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            if session.isReachable {
                status = "Watch reachable"
                WakeLog.debug(.sync, "Watch reachable")
                flushPendingAcks()
            } else {
                status = "Watch not reachable — transfers still queue"
                WakeLog.debug(.sync, "Watch not reachable")
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSyncState()
            status = "Watch state updated"
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
}
