import Foundation
import WatchConnectivity
import WakeTrackerCore

enum SyncConnectionProbe {
    #if os(iOS)
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
        guard session.isWatchAppInstalled else { return .watchAppMissing }
        return session.isReachable ? .readyLive : .readyQueued
    }
    #elseif os(watchOS)
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
        if session.activationState == .activated {
            // isCompanionAppInstalled is available on watchOS 6+
            if !session.isCompanionAppInstalled {
                return .companionMissing
            }
        }
        return session.isReachable ? .readyLive : .readyQueued
    }
    #endif
}
