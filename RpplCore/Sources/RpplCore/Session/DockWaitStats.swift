import Foundation

/// How long the rider waited between sets: the gap from one set's end to the next set's start.
/// A crowded dock shows as long gaps, so the median over a session is a busyness indicator.
public struct DockWaitSummary: Equatable, Sendable {
    public var median: TimeInterval
    public var lowerQuartile: TimeInterval
    public var upperQuartile: TimeInterval
    public var count: Int

    public init(median: TimeInterval, lowerQuartile: TimeInterval, upperQuartile: TimeInterval, count: Int) {
        self.median = median
        self.lowerQuartile = lowerQuartile
        self.upperQuartile = upperQuartile
        self.count = count
    }
}

public enum DockWaitStats {
    /// Seconds between consecutive sets, in session order. Empty with fewer than two sets.
    public static func gaps(sets: [SetSegmentStats]) -> [TimeInterval] {
        let ordered = sets.sorted { $0.startedAt < $1.startedAt }
        return zip(ordered, ordered.dropFirst()).map { max(0, $1.startedAt.timeIntervalSince($0.endedAt)) }
    }

    public static func summary(sets: [SetSegmentStats]) -> DockWaitSummary? {
        let values = gaps(sets: sets).sorted()
        guard !values.isEmpty else { return nil }
        return DockWaitSummary(
            median: quantile(values, 0.5),
            lowerQuartile: quantile(values, 0.25),
            upperQuartile: quantile(values, 0.75),
            count: values.count
        )
    }

    /// Linear interpolation between order statistics (`sorted` ascending, non-empty).
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
