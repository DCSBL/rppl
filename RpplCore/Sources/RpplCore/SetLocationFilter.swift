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

    /// Samples in a set window that are fit to draw as a line: position accuracy within the
    /// detection gate, and no teleport faster than the plausible-speed gate from the previous
    /// kept point. One 216 m network fix mid-set otherwise draws a spike tens of meters off the
    /// cable on the map (field session 2026-09-30, set 4).
    public static func trackSamples(
        in locations: [LocationSample],
        from start: Date,
        to end: Date,
        thresholds: DetectionThresholds = .default
    ) -> [LocationSample] {
        var kept: [LocationSample] = []
        for sample in samples(in: locations, from: start, to: end) {
            guard sample.horizontalAccuracy >= 0,
                  sample.horizontalAccuracy <= thresholds.maxHorizontalAccuracyM
            else { continue }
            if let previous = kept.last, !isPlausibleStep(from: previous, to: sample, thresholds: thresholds) {
                continue
            }
            kept.append(sample)
        }
        return kept
    }

    /// One track per set. Inactive/walking samples between sets are omitted,
    /// so a map can stroke sets without connecting the gaps.
    public static func tracks(
        from locations: [LocationSample],
        sets: [SetSegmentStats]
    ) -> [[LocationSample]] {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        return sets
            .map { trackSamples(in: sorted, from: $0.startedAt, to: $0.endedAt) }
            .filter { $0.count >= 2 }
    }

    private static func isPlausibleStep(
        from: LocationSample,
        to: LocationSample,
        thresholds: DetectionThresholds
    ) -> Bool {
        let delta = to.timestamp.timeIntervalSince(from.timestamp)
        guard delta > 0 else { return false }
        let meters = GeoDistance.meters(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
        let impliedKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: meters / delta)
        return impliedKmh <= thresholds.maxPlausibleSpeedKmh
    }
}
