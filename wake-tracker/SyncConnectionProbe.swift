import Foundation
import WatchConnectivity
import WakeTrackerCore

enum SyncConnectionProbe {
    static func current(session: WCSession = .default) -> SyncConnectionState {
        guard WCSession.isSupported() else { return .unsupported }
        switch session.activationState {
        case .notActivated:
            return .notActivated
        case .inactive:
            return .inactive
        case .activated:
            break
        @unknown default:
            return .notActivated
        }
        guard session.isPaired else { return .notPaired }

        // Simulator often reports isWatchAppInstalled == false even when the Watch app is running.
        // Treat reachable OR installed as enough; on Simulator, paired alone is enough for queued sync.
        if session.isWatchAppInstalled || session.isReachable {
            return session.isReachable ? .readyLive : .readyQueued
        }

        #if targetEnvironment(simulator)
        return .readyQueued
        #else
        return .watchAppMissing
        #endif
    }
}
