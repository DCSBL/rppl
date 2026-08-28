import Foundation

/// GPS samples that fall inside detected set windows.
public enum SetLocationFilter {
    public static func samples(
        in locations: [LocationSample],
        from start: Date,
        to end: Date
    ) -> [LocationSample] {
        locations.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// One track per set. Inactive/walking samples between sets are omitted,
    /// so a map can stroke sets without connecting the gaps.
    public static func tracks(
        from locations: [LocationSample],
        sets: [SetSegmentStats]
    ) -> [[LocationSample]] {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        return sets
            .map { samples(in: sorted, from: $0.startedAt, to: $0.endedAt) }
            .filter { $0.count >= 2 }
    }
}
