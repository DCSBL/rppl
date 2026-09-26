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

    /// Dominant cable speed (km/h) across set windows; nil when too little data.
    public static func cableSpeedKmh(
        setWindows: [(start: Date, end: Date)],
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        let speeds = setWindows.flatMap { window -> [Double] in
            let samples = SetLocationFilter.samples(in: locations, from: window.start, to: window.end)
            return LocationSpeedStats.usableSpeeds(from: samples, thresholds: thresholds)
                .map { SpeedUnits.kilometersPerHour(fromMetersPerSecond: $0.speedMps) }
        }
        return estimates(speedsKmh: speeds, thresholds: thresholds).first?.speedKmh
    }

    /// Distinct speed peaks, dominant first. Speeds at/below the stopped threshold are ignored
    /// (dock starts, falls, standing still).
    public static func estimates(
        speedsKmh: [Double],
        thresholds: DetectionThresholds = .default
    ) -> [Estimate] {
        let moving = speedsKmh.filter { $0 > thresholds.stoppedSpeedKmh }
        guard moving.count >= minSamples else { return [] }

        var bins: [Int: Int] = [:]
        for speed in moving { bins[Int((speed / binWidthKmh).rounded(.down)), default: 0] += 1 }

        // Each bin's score includes its neighbours so GPS jitter across a bin edge does not split a peak.
        func score(_ bin: Int) -> Int { (bins[bin - 1] ?? 0) + (bins[bin] ?? 0) + (bins[bin + 1] ?? 0) }

        var remaining = bins
        var result: [Estimate] = []
        while let peak = remaining.keys.max(by: { score($0) < score($1) || (score($0) == score($1) && $0 > $1) }),
              score(peak) > 0, result.count < 3 {
            let members = (peak - 1...peak + 1).filter { remaining[$0] != nil }
            let count = members.reduce(0) { $0 + (remaining[$1] ?? 0) }
            guard Double(count) / Double(moving.count) >= 0.1 else { break }
            let weighted = members.reduce(0.0) {
                $0 + (Double($1) + 0.5) * binWidthKmh * Double(remaining[$1] ?? 0)
            }
            result.append(Estimate(speedKmh: weighted / Double(count), share: Double(count) / Double(moving.count)))
            // Drop this peak and its shoulders so the next iteration finds a separate one.
            for bin in (peak - 2...peak + 2) { remaining[bin] = nil }
            // score() reads `bins`, so mask consumed bins there too.
            for bin in (peak - 2...peak + 2) { bins[bin] = nil }
        }
        return result
    }
}
