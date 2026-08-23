import Foundation

/// HIG tiny-session rule: short sessions with no rides may be discarded on Watch
/// after explicit confirmation (never silent-delete).
public enum TinySessionPolicy: Sendable {
    /// Sessions shorter than this with zero rides offer discard (~30s).
    public static let maxDurationSeconds: TimeInterval = 30

    /// True when Stop should confirm discard instead of only end-and-transfer.
    public static func shouldOfferDiscard(duration: TimeInterval, rideCount: Int) -> Bool {
        duration < maxDurationSeconds && rideCount == 0
    }
}
