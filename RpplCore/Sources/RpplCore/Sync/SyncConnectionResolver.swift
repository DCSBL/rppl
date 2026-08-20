import Foundation

public enum SyncConnectionResolver {
    public enum Activation: String, Sendable, Equatable {
        case notActivated
        case inactive
        case activated
    }

    public enum PlatformKind: String, Sendable, Equatable {
        case phone
        case watch
    }

    /// Pure decision for WatchConnectivity readiness. No WCSession dependency.
    public static func resolve(
        supported: Bool,
        activation: Activation,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isCompanionAppInstalled: Bool,
        isReachable: Bool,
        isSimulator: Bool,
        platform: PlatformKind
    ) -> SyncConnectionState {
        guard supported else { return .unsupported }

        switch activation {
        case .notActivated:
            return .notActivated
        case .inactive:
            return .inactive
        case .activated:
            break
        }

        switch platform {
        case .phone:
            guard isPaired else { return .notPaired }
            if isWatchAppInstalled || isReachable {
                return isReachable ? .readyLive : .readyQueued
            }
            // Simulator often reports isWatchAppInstalled == false while Watch app runs.
            if isSimulator {
                return .readyQueued
            }
            return .watchAppMissing

        case .watch:
            if !isCompanionAppInstalled {
                return .companionMissing
            }
            return isReachable ? .readyLive : .readyQueued
        }
    }
}
