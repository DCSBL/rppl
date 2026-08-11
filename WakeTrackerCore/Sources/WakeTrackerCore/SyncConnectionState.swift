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
        case .unsupported: return "Unsupported"
        case .notActivated: return "Not activated"
        case .inactive: return "Inactive"
        case .notPaired: return "No Watch paired"
        case .watchAppMissing: return "Watch app missing"
        case .companionMissing: return "iPhone app missing"
        case .readyQueued: return "Ready (queued)"
        case .readyLive: return "Connected"
        }
    }

    public var detail: String {
        switch self {
        case .unsupported:
            return "WatchConnectivity is not available here."
        case .notActivated:
            return "Waiting for WatchConnectivity to activate."
        case .inactive:
            return "Session inactive — reopen the app."
        case .notPaired:
            return "Pair an Apple Watch to sync sessions."
        case .watchAppMissing:
            return "Install Wake Tracker on the Watch."
        case .companionMissing:
            return "Install / open Wake Tracker on iPhone."
        case .readyQueued:
            return "Paired and ready — files sync when the phone is nearby."
        case .readyLive:
            return "iPhone and Watch are connected — ready to sync."
        }
    }
}
