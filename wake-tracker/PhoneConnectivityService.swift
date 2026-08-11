import Foundation
import WatchConnectivity
import WakeTrackerCore
import Observation

@Observable
@MainActor
final class PhoneConnectivityService: NSObject {
    static let shared = PhoneConnectivityService()

    var status = "WC idle"
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
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func acknowledge(sessionId: String) {
        guard WCSession.default.isReachable else {
            status = "Imported \(sessionId.prefix(8)) — Watch not reachable for ack (will retry when reachable)"
            pendingAcks.insert(sessionId)
            return
        }
        WCSession.default.sendMessage(
            [AppConstants.wcAckMessageKey: sessionId],
            replyHandler: { _ in },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.pendingAcks.insert(sessionId)
                    self?.status = "Ack send failed: \(error.localizedDescription)"
                }
            }
        )
        pendingAcks.remove(sessionId)
        status = "Acked \(sessionId.prefix(8))"
    }

    func flushPendingAcks() {
        guard WCSession.default.isReachable else { return }
        for id in Array(pendingAcks) {
            acknowledge(sessionId: id)
        }
    }

    func importPackage(from url: URL, sessionIdHint: String?) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SessionTransferPackage.self, from: data)
        try store.importTransferPackage(package, intoPhoneStore: store.rootURL)
        sessionsRevision += 1
        let sessionId = sessionIdHint ?? package.manifest.sessionId
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
            if let error {
                status = "WC error: \(error.localizedDescription)"
            } else {
                status = "WC activated"
                flushPendingAcks()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let url = file.fileURL
        let hint = file.metadata?[AppConstants.wcSessionFileMetaSessionID] as? String
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
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                flushPendingAcks()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
