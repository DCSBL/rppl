import Foundation
import WatchConnectivity
import RpplCore

/// iPhone → Watch distilled logbook sync (view-only mirror).
enum PhoneWatchViewSync {
    static func makeUpdate(store: SessionFileStore, sessionId: String) throws -> WatchViewUpdate? {
        let manifest = try store.readManifest(sessionId: sessionId)
        guard manifest.transferState == .acknowledged, manifest.mirrorsToWatch else { return nil }
        let derived = try store.ensureDerivedView(sessionId: sessionId)
        return WatchViewUpdate(manifest: manifest, derived: derived)
    }

    static func allPhoneUpdates(store: SessionFileStore) throws -> [WatchViewUpdate] {
        try store.listSessionIDs().compactMap { sessionId in
            try makeUpdate(store: store, sessionId: sessionId)
        }
    }

    static func pushViewUpdate(_ update: WatchViewUpdate) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let payload = try? WatchViewSyncCodec.encodeViewUpdate(update) else { return }
        WCSession.default.transferUserInfo(payload)
        WakeLog.debug(.sync, "queued viewUpdate \(update.manifest.sessionId.prefix(8))…")
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            payload,
            replyHandler: nil,
            errorHandler: { error in
                WakeLog.error(.sync, "viewUpdate send failed: \(error.localizedDescription)")
            }
        )
    }

    static func pushViewUpdate(store: SessionFileStore, sessionId: String) {
        guard let update = try? makeUpdate(store: store, sessionId: sessionId) else { return }
        pushViewUpdate(update)
    }

    static func pushViewDelete(sessionId: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = WatchViewSyncCodec.encodeViewDelete(sessionId: sessionId)
        WCSession.default.transferUserInfo(payload)
        WakeLog.debug(.sync, "queued viewDelete \(sessionId.prefix(8))…")
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            payload,
            replyHandler: nil,
            errorHandler: { error in
                WakeLog.error(.sync, "viewDelete send failed: \(error.localizedDescription)")
            }
        )
    }

    static func rebroadcastViewUpdates(store: SessionFileStore) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        do {
            let updates = try allPhoneUpdates(store: store)
            for update in updates {
                pushViewUpdate(update)
            }
            if !updates.isEmpty {
                WakeLog.debug(.sync, "rebroadcast viewUpdate count=\(updates.count)")
            }
        } catch {
            WakeLog.error(.sync, "rebroadcast viewUpdate failed: \(error.localizedDescription)")
        }
    }

    static func handleSyncRequest(
        store: SessionFileStore,
        knownOnWatch: [WatchKnownSession]
    ) throws -> WatchViewSyncReply {
        let phoneUpdates = try allPhoneUpdates(store: store)
        return WatchViewSyncDiff.reply(knownOnWatch: knownOnWatch, phoneUpdates: phoneUpdates)
    }
}
