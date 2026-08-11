import Foundation
import WatchConnectivity
import WakeTrackerCore

enum SyncConnectionProbe {
    static func current(session: WCSession = .default) -> SyncConnectionState {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif

        let activation: SyncConnectionResolver.Activation
        switch session.activationState {
        case .notActivated:
            activation = .notActivated
        case .inactive:
            activation = .inactive
        case .activated:
            activation = .activated
        @unknown default:
            activation = .notActivated
        }

        return SyncConnectionResolver.resolve(
            supported: WCSession.isSupported(),
            activation: activation,
            isPaired: true,
            isWatchAppInstalled: true,
            isCompanionAppInstalled: session.isCompanionAppInstalled,
            isReachable: session.isReachable,
            isSimulator: simulator,
            platform: .watch
        )
    }
}
