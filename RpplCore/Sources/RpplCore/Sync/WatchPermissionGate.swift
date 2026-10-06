import Foundation

/// Recording permissions the Watch asks for when a session starts / explains when access is missing.
public enum WatchPermissionKind: String, CaseIterable, Sendable, Codable, Hashable {
    case location
    case health
    case motion
}

/// Coarse gate state for a single Watch permission.
public enum WatchPermissionState: String, Sendable, Codable, Hashable {
    /// System sheet can still be presented.
    case notDetermined
    /// Ready for recording (or hardware skipped).
    case authorized
    /// User denied / restricted — Settings path required.
    case denied
    /// Hardware missing — does not block the gate (treated as ready).
    case unavailable
}

extension WatchPermissionState {
    /// Gate may proceed past this permission when the kind is required.
    public var isReady: Bool {
        switch self {
        case .authorized, .unavailable:
            return true
        case .notDetermined, .denied:
            return false
        }
    }

    /// Location only. With Precise Location off, CoreLocation grants access but delivers fixes with
    /// kilometers of error and no usable speed: detection rejects every fix and the whole session
    /// records without sets or a track, while everything looks fine. A granted permission with
    /// reduced accuracy therefore counts as not ready (fixed in Settings > Precise Location).
    public func accountingForReducedAccuracy(_ isReduced: Bool) -> WatchPermissionState {
        self == .authorized && isReduced ? .denied : self
    }
}

extension WatchPermissionKind {
    /// Whether this permission can keep the Watch recording onboarding gate closed.
    ///
    /// - Location: required (GPS).
    /// - Health: required, and must be `.authorized` (not merely "unavailable"). The HK workout
    ///   session keeps the app running with the wrist down; without it sensors and detection
    ///   stop. The Watch stays browsable (logbook, sessions); only Start is blocked.
    /// - Motion: never blocks (helps dock/ride hints; device motion still records).
    public func blocksRecording(when state: WatchPermissionState) -> Bool {
        switch self {
        case .location:
            return !state.isReady
        case .health:
            return state != .authorized
        case .motion:
            return false
        }
    }
}

/// Start-gate decisions over the Watch recording permissions.
public enum WatchPermissionOrder {
    /// Permissions checked in this order when explaining why Start is blocked.
    private static let startBlockerOrder: [WatchPermissionKind] = [.health, .location]

    /// First required permission that keeps Start blocked, or nil when recording may start.
    public static func startBlocker(
        states: [WatchPermissionKind: WatchPermissionState]
    ) -> WatchPermissionKind? {
        startBlockerOrder.first { $0.blocksRecording(when: states[$0] ?? .notDetermined) }
    }

    public static func areAllReady(_ states: [WatchPermissionKind: WatchPermissionState]) -> Bool {
        WatchPermissionKind.allCases.allSatisfy { kind in
            !kind.blocksRecording(when: states[kind] ?? .notDetermined)
        }
    }

    /// True when Start should show the permission checklist first: a required permission blocks
    /// recording, or any permission can still show its system sheet. A denied optional permission
    /// (Motion) alone does not: it cannot be asked again, and recording works without it.
    public static func needsSetup(_ states: [WatchPermissionKind: WatchPermissionState]) -> Bool {
        startBlocker(states: states) != nil
            || WatchPermissionKind.allCases.contains { (states[$0] ?? .notDetermined) == .notDetermined }
    }
}
