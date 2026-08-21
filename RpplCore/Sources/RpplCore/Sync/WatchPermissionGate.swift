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
    /// Gate may proceed past this permission.
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

    public static func allReady(_ states: [WatchPermissionKind: WatchPermissionState]) -> Bool {
        WatchPermissionKind.allCases.allSatisfy { states[$0]?.isReady == true }
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
