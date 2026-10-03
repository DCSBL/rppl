import Foundation
import WatchConnectivity
import RpplCore
import Observation

@Observable
@MainActor
final class WatchViewSyncService {
    static let shared = WatchViewSyncService()

    private(set) var catalogRevision = 0

    private var store: SessionFileStore {
        SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)
    }

    func bumpCatalogRevision() {
        catalogRevision &+= 1
    }

    func applyViewUpdate(_ update: WatchViewUpdate) {
        do {
            try store.applyDistilledView(update)
            bumpCatalogRevision()
            WakeLog.debug(.sync, "applied viewUpdate \(update.manifest.sessionId.prefix(8))…")
        } catch {
            WakeLog.error(.sync, "apply viewUpdate: \(error.localizedDescription)")
        }
    }

    func applyViewDelete(sessionId: String) {
        do {
            guard let manifest = try? store.readManifest(sessionId: sessionId) else {
                WakeLog.debug(.sync, "viewDelete missing \(sessionId.prefix(8))…")
                return
            }
            guard WatchViewDeletePolicy.mayDelete(manifest) else {
                WakeLog.error(.sync, "viewDelete refused \(sessionId.prefix(8))… state=\(manifest.transferState)")
                return
            }
            try store.deleteSession(sessionId: sessionId)
            bumpCatalogRevision()
            WakeLog.debug(.sync, "applied viewDelete \(sessionId.prefix(8))…")
        } catch SessionStoreError.sessionNotFound {
            WakeLog.debug(.sync, "viewDelete missing \(sessionId.prefix(8))…")
        } catch {
            WakeLog.error(.sync, "apply viewDelete: \(error.localizedDescription)")
        }
    }

    func applySyncReply(_ reply: WatchViewSyncReply) {
        for sessionId in reply.deletes {
            applyViewDelete(sessionId: sessionId)
        }
        for update in reply.updates {
            applyViewUpdate(update)
        }
    }

    func handleIncomingMessage(_ message: [String: Any]) {
        if let update = try? WatchViewSyncCodec.decodeViewUpdate(from: message) {
            applyViewUpdate(update)
            return
        }
        if let sessionId = try? WatchViewSyncCodec.decodeViewDelete(from: message) {
            applyViewDelete(sessionId: sessionId)
            return
        }
        if let reply = try? WatchViewSyncCodec.decodeSyncReply(from: message) {
            applySyncReply(reply)
        }
    }

    func pruneAfterAck(sessionId: String) {
        do {
            if try store.readDerivedView(sessionId: sessionId) != nil {
                try store.pruneRawStreams(sessionId: sessionId)
                WakeLog.debug(.store, "pruned raw after ack \(sessionId.prefix(8))…")
            }
        } catch {
            WakeLog.error(.store, "prune after ack: \(error.localizedDescription)")
        }
    }

    func knownSessionsOnWatch() -> [WatchKnownSession] {
        guard let ids = try? store.listSessionIDs() else { return [] }
        return ids.compactMap { sessionId in
            guard
                let manifest = try? store.readManifest(sessionId: sessionId),
                WatchViewDeletePolicy.mayDelete(manifest),
                let derived = try? store.readDerivedView(sessionId: sessionId)
            else {
                return nil
            }
            return WatchKnownSession(sessionId: sessionId, analyzerVersion: derived.analyzerVersion)
        }
    }

    /// On-demand diff sync when iPhone is reachable (no polling).
    func requestViewSyncIfReachable() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else { return }

        let known = knownSessionsOnWatch()
        guard let payload = try? WatchViewSyncCodec.encodeSyncRequest(known: known) else { return }

        WakeLog.debug(.sync, "syncRequest known=\(known.count)")
        WCSession.default.sendMessage(
            payload,
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if let syncReply = try? WatchViewSyncCodec.decodeSyncReply(from: reply) {
                        self?.applySyncReply(syncReply)
                    }
                }
            },
            errorHandler: { error in
                WakeLog.error(.sync, "syncRequest failed: \(error.localizedDescription)")
            }
        )
    }
}
