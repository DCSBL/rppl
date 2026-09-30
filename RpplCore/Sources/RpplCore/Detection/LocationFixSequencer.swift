import Foundation

/// Keeps live GPS fixes moving forward in time before they reach detection and the live set
/// tracker.
///
/// CoreLocation can hand the same fix over more than once, and a fix whose processing was held
/// up can surface after newer ones. Hold clocks and backdated set windows assume time only moves
/// forward, so a fix at or before the last accepted one is dropped instead of replayed into the
/// past.
public struct LocationFixSequencer: Sendable, Equatable {
    public private(set) var lastAcceptedAt: Date?
    /// Fixes dropped since the last `reset()` — duplicates and out-of-order arrivals.
    public private(set) var droppedCount = 0

    public init() {}

    public mutating func reset() {
        lastAcceptedAt = nil
        droppedCount = 0
    }

    /// Accept one fix timestamp. `false` means the fix is a duplicate or older than one already
    /// accepted and must not be processed.
    public mutating func accept(_ timestamp: Date) -> Bool {
        if let lastAcceptedAt, timestamp <= lastAcceptedAt {
            droppedCount += 1
            return false
        }
        lastAcceptedAt = timestamp
        return true
    }

    /// The fixes of one delivery that are new, oldest first.
    public mutating func accepted<Fix>(_ fixes: [Fix], timestamp: (Fix) -> Date) -> [Fix] {
        fixes
            .sorted { timestamp($0) < timestamp($1) }
            .filter { accept(timestamp($0)) }
    }
}
