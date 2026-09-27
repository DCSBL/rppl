import Foundation

/// Estimates cable (line) speed as the most common riding speed across a session.
///
/// Cable speed rarely changes within a session, so the mode of usable riding speeds is a robust
/// proxy for it. Speeds are binned, smoothed over neighbouring bins, and the dominant peak wins.
/// `estimates` returns every distinct peak so a session on several cables can be supported later;
/// `cableSpeedKmh` is the dominant one.
public enum CableSpeedEstimator {
    public struct Estimate: Equatable, Sendable {
        public var speedKmh: Double
        /// Fraction (0...1) of counted samples that belong to this peak.
        public var share: Double
    }

    public static let binWidthKmh = 1.0
    /// Min usable samples before an estimate is trusted.
    public static let minSamples = 20
    /// A set only overrides the session-wide speed by this much (km/h) or more.
    public static let setOverrideThresholdKmh = 2.0
    /// Min span of usable samples before a set's own speed is trusted over the session value.
    public static let minSetSampleSpan: TimeInterval = 60

    /// Nearest 0.5 km/h — cable speeds are set in coarse steps, not fractions.
    public static func roundedToHalfKmh(_ speedKmh: Double) -> Double {
        (speedKmh * 2).rounded() / 2
    }

    /// Dominant cable speed (km/h) across set windows; nil when too little data.
    public static func cableSpeedKmh(
        setWindows: [(start: Date, end: Date)],
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        let speeds = usableSpeedsKmh(setWindows: setWindows, locations: locations, thresholds: thresholds)
        guard let speedKmh = estimates(speedsKmh: speeds, thresholds: thresholds).first?.speedKmh else { return nil }
        return roundedToHalfKmh(speedKmh)
    }

    /// Per-set cable speed: the session-wide value, unless this set's own usable samples span at
    /// least `minSetSampleSpan` and its own estimate differs by `setOverrideThresholdKmh` or more —
    /// a short set is too easily thrown off by a single sprint or fall to trust on its own.
    public static func cableSpeedKmh(
        setWindow: (start: Date, end: Date),
        sessionSpeedKmh: Double?,
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        guard let sessionSpeedKmh else { return nil }
        let roundedSession = roundedToHalfKmh(sessionSpeedKmh)

        let samples = SetLocationFilter.samples(in: locations, from: setWindow.start, to: setWindow.end)
        let usable = LocationSpeedStats.usableSpeeds(from: samples, thresholds: thresholds)
        guard let first = usable.first?.timestamp, let last = usable.last?.timestamp,
              last.timeIntervalSince(first) >= minSetSampleSpan else {
            return roundedSession
        }

        let speedsKmh = usable.map { SpeedUnits.kilometersPerHour(fromMetersPerSecond: $0.speedMps) }
        guard let setSpeedKmh = estimates(speedsKmh: speedsKmh, thresholds: thresholds).first?.speedKmh else {
            return roundedSession
        }

        let roundedSet = roundedToHalfKmh(setSpeedKmh)
        guard abs(roundedSet - roundedSession) >= setOverrideThresholdKmh else { return roundedSession }
        return roundedSet
    }

    private static func usableSpeedsKmh(
        setWindows: [(start: Date, end: Date)],
        locations: [LocationSample],
        thresholds: DetectionThresholds
    ) -> [Double] {
        setWindows.flatMap { window -> [Double] in
            let samples = SetLocationFilter.samples(in: locations, from: window.start, to: window.end)
            return LocationSpeedStats.usableSpeeds(from: samples, thresholds: thresholds)
                .map { SpeedUnits.kilometersPerHour(fromMetersPerSecond: $0.speedMps) }
        }
    }

    /// Distinct speed peaks, dominant first. Speeds at/below the stopped threshold are ignored
    /// (dock starts, falls, standing still).
    public static func estimates(
        speedsKmh: [Double],
        thresholds: DetectionThresholds = .default
    ) -> [Estimate] {
        let moving = speedsKmh.filter { $0 > thresholds.stoppedSpeedKmh }
        guard moving.count >= minSamples else { return [] }

        // Track each bin's actual sample sum alongside its count, so a peak's reported speed is
        // the true mean of its samples — not the bin's midpoint, which biases constant-speed sets
        // (e.g. exactly 32.0 km/h floors into bin 32, whose midpoint is 32.5).
        var bins: [Int: (count: Int, sum: Double)] = [:]
        for speed in moving {
            let bin = Int((speed / binWidthKmh).rounded(.down))
            let existing = bins[bin] ?? (count: 0, sum: 0)
            bins[bin] = (count: existing.count + 1, sum: existing.sum + speed)
        }

        // Each bin's score includes its neighbours so GPS jitter across a bin edge does not split a peak.
        func score(_ bin: Int) -> Int {
            (bins[bin - 1]?.count ?? 0) + (bins[bin]?.count ?? 0) + (bins[bin + 1]?.count ?? 0)
        }

        var remaining = bins
        var result: [Estimate] = []
        while let peak = remaining.keys.max(by: { score($0) < score($1) || (score($0) == score($1) && $0 > $1) }),
              score(peak) > 0, result.count < 3 {
            let members = (peak - 1...peak + 1).filter { remaining[$0] != nil }
            let count = members.reduce(0) { $0 + (remaining[$1]?.count ?? 0) }
            guard Double(count) / Double(moving.count) >= 0.1 else { break }
            let sum = members.reduce(0.0) { $0 + (remaining[$1]?.sum ?? 0) }
            result.append(Estimate(speedKmh: sum / Double(count), share: Double(count) / Double(moving.count)))
            // Drop this peak and its shoulders so the next iteration finds a separate one.
            for bin in (peak - 2...peak + 2) { remaining[bin] = nil }
            // score() reads `bins`, so mask consumed bins there too.
            for bin in (peak - 2...peak + 2) { bins[bin] = nil }
        }
        return result
    }
}
