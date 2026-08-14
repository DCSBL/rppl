import Foundation

/// GPS samples that fall inside detected ride windows.
public enum RideLocationFilter {
    public static func samples(
        in locations: [LocationSample],
        from start: Date,
        to end: Date
    ) -> [LocationSample] {
        locations.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// One track per ride. Paused/walking samples between rides are omitted,
    /// so a map can stroke rides without connecting the gaps.
    public static func tracks(
        from locations: [LocationSample],
        rides: [RideSegmentStats]
    ) -> [[LocationSample]] {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        return rides
            .map { samples(in: sorted, from: $0.startedAt, to: $0.endedAt) }
            .filter { $0.count >= 2 }
    }
}
