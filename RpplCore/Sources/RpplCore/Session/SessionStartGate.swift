import Foundation

/// Whether a Start request (Action Button, Siri, idle tap) may begin a new session.
///
/// Busy means a session is recording, starting, or still saving the previous one — the request
/// is ignored, never queued. Anything else starts a fresh session, including while the previous
/// session's end summary is on screen: the summary is only a view, and the new session begins
/// with clean buffers.
public enum SessionStartGate {
    public enum Decision: Equatable, Sendable {
        case start
        case ignoreBusy
        /// A required permission is missing: tell the rider instead of starting.
        case blockedByPermission(WatchPermissionKind)
    }

    public static func decide(
        isRunning: Bool,
        isStarting: Bool,
        isStopping: Bool,
        isFinalizing: Bool,
        permissionBlocker: WatchPermissionKind? = nil
    ) -> Decision {
        if isRunning || isStarting || isStopping || isFinalizing { return .ignoreBusy }
        if let permissionBlocker { return .blockedByPermission(permissionBlocker) }
        return .start
    }
}
