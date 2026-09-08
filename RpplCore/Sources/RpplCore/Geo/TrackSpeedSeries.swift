import Foundation

/// Per-sample display speed (km/h) for map colouring.
///
/// Display only — never a detection input. Uses the same GPS accuracy and plausibility
/// gates as detection so a bad fix cannot paint a fake sprint, then falls back to
/// distance / Δt when Core Location gave no speed, and smooths so colour bands do not
/// flicker every sample.
public enum TrackSpeedSeries {
    /// Samples on each side of a point averaged into its display speed.
    public static let defaultSmoothingRadius = 2

    /// Speeds aligned 1:1 with `locations`. Nil where no usable speed could be resolved.
    public static func speedsKmh(
        for locations: [LocationSample],
        thresholds: DetectionThresholds = .default,
        smoothingRadius: Int = defaultSmoothingRadius
    ) -> [Double?] {
        guard !locations.isEmpty else { return [] }
        let raw = (0..<locations.count).map { index in
            rawSpeedKmh(at: index, in: locations, thresholds: thresholds)
        }
        return smoothed(raw, radius: max(0, smoothingRadius))
    }

    /// Robust low / high speed pair (km/h) for scaling a colour ramp, ignoring outliers.
    /// Returns nil when the track has no usable speed at all.
    public static func percentileRangeKmh(
        _ speeds: [Double?],
        lowPercentile: Double = 0.1,
        highPercentile: Double = 0.9
    ) -> (low: Double, high: Double)? {
        let usable = speeds.compactMap { $0 }.sorted()
        guard let first = usable.first, let last = usable.last else { return nil }
        guard usable.count >= 4 else { return (low: first, high: last) }
        return (
            low: percentile(usable, lowPercentile),
            high: percentile(usable, highPercentile)
        )
    }

    // MARK: - Internals

    private static func rawSpeedKmh(
        at index: Int,
        in locations: [LocationSample],
        thresholds: DetectionThresholds
    ) -> Double? {
        let sample = locations[index]
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= thresholds.maxHorizontalAccuracyM
        else {
            return nil
        }

        if let reported = sample.speed, reported >= 0 {
            let kmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: reported)
            if kmh <= thresholds.maxPlausibleSpeedKmh { return kmh }
        }

        if index > 0, let derived = derivedSpeedKmh(
            from: locations[index - 1],
            to: sample,
            thresholds: thresholds
        ) {
            return derived
        }
        if index + 1 < locations.count, let derived = derivedSpeedKmh(
            from: sample,
            to: locations[index + 1],
            thresholds: thresholds
        ) {
            return derived
        }
        return nil
    }

    private static func derivedSpeedKmh(
        from: LocationSample,
        to: LocationSample,
        thresholds: DetectionThresholds
    ) -> Double? {
        guard GeoDistance.acceptsStep(
            from: from,
            to: to,
            maxHorizontalAccuracyM: thresholds.maxHorizontalAccuracyM,
            maxPlausibleSpeedKmh: thresholds.maxPlausibleSpeedKmh
        ) else {
            return nil
        }
        let delta = to.timestamp.timeIntervalSince(from.timestamp)
        guard delta > 0 else { return nil }
        let meters = GeoDistance.meters(
            fromLat: from.latitude,
            fromLon: from.longitude,
            toLat: to.latitude,
            toLon: to.longitude
        )
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: meters / delta)
    }

    private static func smoothed(_ speeds: [Double?], radius: Int) -> [Double?] {
        guard radius > 0 else { return speeds }
        var result = speeds
        for index in speeds.indices {
            guard speeds[index] != nil else { continue }
            let lower = max(0, index - radius)
            let upper = min(speeds.count - 1, index + radius)
            let window = (lower...upper).compactMap { speeds[$0] }
            guard !window.isEmpty else { continue }
            result[index] = window.reduce(0, +) / Double(window.count)
        }
        return result
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard upper < sorted.count else { return sorted[sorted.count - 1] }
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
