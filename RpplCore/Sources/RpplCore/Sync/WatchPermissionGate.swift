import Foundation

/// Recording permissions shown on Watch first-run / when access is missing.
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

    /// Needs attention in the permissions list (sort toward top on fresh load).
    public var needsAttention: Bool {
        !isReady
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

/// Stable list ordering for the Watch permissions onboarding screen.
public enum WatchPermissionOrder {
    /// Fresh load / app reopen: attention first, then ready. Stable within each group by
    /// `WatchPermissionKind.allCases` order.
    public static func initialOrder(
        states: [WatchPermissionKind: WatchPermissionState]
    ) -> [WatchPermissionKind] {
        let kinds = WatchPermissionKind.allCases
        let attention = kinds.filter { states[$0]?.needsAttention == true }
        let ready = kinds.filter { states[$0]?.needsAttention != true }
        return attention + ready
    }

    /// Keep `current` order unless a previously ready permission became not ready — then
    /// move those revoked kinds to the front (stable among themselves).
    public static func orderPreserving(
        current: [WatchPermissionKind],
        previous: [WatchPermissionKind: WatchPermissionState],
        next: [WatchPermissionKind: WatchPermissionState]
    ) -> [WatchPermissionKind] {
        let revoked = WatchPermissionKind.allCases.filter { kind in
            let wasReady = previous[kind]?.isReady ?? false
            let isReady = next[kind]?.isReady ?? false
            return wasReady && !isReady
        }
        guard !revoked.isEmpty else { return ensureComplete(current) }

        let remaining = ensureComplete(current).filter { !revoked.contains($0) }
        return revoked + remaining
    }

    /// Permissions checked in this order when explaining why Start is blocked.
    private static let startBlockerOrder: [WatchPermissionKind] = [.health, .location]

    /// First required permission that keeps Start blocked, or nil when recording may start.
    public static func startBlocker(
        states: [WatchPermissionKind: WatchPermissionState]
    ) -> WatchPermissionKind? {
        startBlockerOrder.first { $0.blocksRecording(when: states[$0] ?? .notDetermined) }
    }

    /// First run: a required permission can still show its system sheet, so onboarding prompts.
    /// Once every required permission is decided, the Watch is browsable and Start explains the block.
    public static func needsFirstRunPrompt(
        states: [WatchPermissionKind: WatchPermissionState]
    ) -> Bool {
        startBlockerOrder.contains { (states[$0] ?? .notDetermined) == .notDetermined }
    }

    public static func areAllReady(_ states: [WatchPermissionKind: WatchPermissionState]) -> Bool {
        WatchPermissionKind.allCases.allSatisfy { kind in
            !kind.blocksRecording(when: states[kind] ?? .notDetermined)
        }
    }

    private static func ensureComplete(_ current: [WatchPermissionKind]) -> [WatchPermissionKind] {
        var seen = Set<WatchPermissionKind>()
        var result: [WatchPermissionKind] = []
        for kind in current where seen.insert(kind).inserted {
            result.append(kind)
        }
        for kind in WatchPermissionKind.allCases where seen.insert(kind).inserted {
            result.append(kind)
        }
        return result
    }
}
