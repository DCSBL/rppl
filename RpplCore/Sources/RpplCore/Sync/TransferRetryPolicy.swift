import Foundation

/// When the Watch may queue a session package again.
///
/// A session the phone cannot import (too large, corrupt) used to be rebuilt and re-sent every
/// time the Watch app became active — tens of MB of work per wrist raise, during recordings too.
/// Attempts now back off; an explicit "sync now" still retries at once.
public enum TransferRetryPolicy {
    /// Wait after the n-th queued attempt (1-based); the last value repeats.
    public static let delays: [TimeInterval] = [60, 5 * 60, 30 * 60, 2 * 3600, 6 * 3600, 24 * 3600]

    public static func delay(afterAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return delays[min(attempt, delays.count) - 1]
    }

    public static func isDue(_ manifest: SessionManifest, now: Date) -> Bool {
        guard let next = manifest.nextTransferAttemptAt else { return true }
        return next <= now
    }

    /// Sessions needing a phone ack whose backoff has passed.
    public static func due(_ manifests: [SessionManifest], now: Date) -> [SessionManifest] {
        TransferPendingFilter.needingTransfer(manifests).filter { isDue($0, now: now) }
    }
}
