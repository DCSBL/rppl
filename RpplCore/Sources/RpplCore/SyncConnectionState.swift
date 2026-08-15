import Foundation

/// Cross-device WatchConnectivity readiness for session file sync.
public enum SyncConnectionState: String, Codable, Sendable, Equatable {
    case unsupported
    case notActivated
    case inactive
    /// iPhone: no paired Watch.
    case notPaired
    /// iPhone: Watch paired but this app not installed on Watch.
    case watchAppMissing
    /// Watch: companion iPhone app missing / not installed.
    case companionMissing
    /// Activated + paired/installed, but not currently reachable. File transfers still queue.
    case readyQueued
    /// Activated and currently reachable for interactive messaging / immediate sync.
    case readyLive

    public var isReadyToSync: Bool {
        switch self {
        case .readyLive, .readyQueued:
            return true
        default:
            return false
        }
    }

    public var title: String {
        switch self {
        case .unsupported: return String(localized: "Unsupported", bundle: .module)
        case .notActivated: return String(localized: "Not activated", bundle: .module)
        case .inactive: return String(localized: "Inactive", bundle: .module)
        case .notPaired: return String(localized: "No Watch paired", bundle: .module)
        case .watchAppMissing: return String(localized: "Watch app missing", bundle: .module)
        case .companionMissing: return String(localized: "iPhone app missing", bundle: .module)
        case .readyQueued: return String(localized: "Ready (queued)", bundle: .module)
        case .readyLive: return String(localized: "Connected", bundle: .module)
        }
    }

    public var detail: String {
        switch self {
        case .unsupported:
            return String(localized: "WatchConnectivity is not available here.", bundle: .module)
        case .notActivated:
            return String(localized: "Waiting for WatchConnectivity to activate.", bundle: .module)
        case .inactive:
            return String(localized: "Session inactive — reopen the app.", bundle: .module)
        case .notPaired:
            return String(localized: "Pair an Apple Watch to sync sessions.", bundle: .module)
        case .watchAppMissing:
            return String(localized: "Install Rppl on the Watch.", bundle: .module)
        case .companionMissing:
            return String(localized: "Install / open Rppl on iPhone.", bundle: .module)
        case .readyQueued:
            return String(
                localized: "Paired and ready — files sync when the phone is nearby.",
                bundle: .module
            )
        case .readyLive:
            return String(
                localized: "iPhone and Watch are connected — ready to sync.",
                bundle: .module
            )
        }
    }
}
