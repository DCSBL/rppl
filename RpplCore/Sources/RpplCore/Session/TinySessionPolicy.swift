import Foundation

/// HIG tiny-session rule: short sessions with no sets may be discarded on Watch
/// after explicit confirmation (never silent-delete).
public enum TinySessionPolicy: Sendable {
    /// Sessions shorter than this with zero sets offer discard (~30s).
    public static let maxDurationSeconds: TimeInterval = 30

    /// True when Stop should confirm discard instead of only end-and-transfer.
    public static func shouldOfferDiscard(duration: TimeInterval, setCount: Int) -> Bool {
        duration < maxDurationSeconds && setCount == 0
    }

    /// Debug/TestFlight builds add "Stop and discard data" to the end dialog. Past this, a
    /// session is real riding and one mis-tap would lose it, so the option is hidden (10 min).
    public static let debugDiscardMaxDurationSeconds: TimeInterval = 600

    public static func shouldOfferDebugDiscard(duration: TimeInterval) -> Bool {
        duration < debugDiscardMaxDurationSeconds
    }
}
