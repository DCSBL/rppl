import Foundation

/// Peak / average speed helpers using the same GPS quality gates as detection.
public enum LocationSpeedStats {
    /// Max usable sample speed in km/h. Ignores accuracy failures, implausible speeds, and jumps.
    public static func peakSpeedKmh(
        from locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let filter = GpsSignalFilter(thresholds: thresholds)
        var previousUsableMps: Double?
        var peakMps: Double?

        for sample in sorted {
            let tick = DetectionTick(
                timestamp: sample.timestamp,
                speedMps: sample.speed,
                horizontalAccuracy: sample.horizontalAccuracy
            )
            let outcome = filter.evaluate(tick, previousUsableSpeedMps: previousUsableMps)
            guard let usable = outcome.usableSpeedMps, usable > 0 else { continue }
            previousUsableMps = usable
            peakMps = max(peakMps ?? usable, usable)
        }

        guard let peakMps else { return nil }
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: peakMps)
    }

    /// Session top speed = max peak across ride windows (never whole-session GPS).
    public static func peakSpeedKmh(
        rideWindows: [(start: Date, end: Date)],
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        var sessionPeak: Double?
        for window in rideWindows {
            let samples = RideLocationFilter.samples(in: locations, from: window.start, to: window.end)
            guard let ridePeak = peakSpeedKmh(from: samples, thresholds: thresholds) else { continue }
            sessionPeak = max(sessionPeak ?? ridePeak, ridePeak)
        }
        return sessionPeak
    }

    public static func averageSpeedKmh(distanceMeters: Double, duration: TimeInterval) -> Double? {
        guard duration > 0, distanceMeters > 0 else { return nil }
        let mps = distanceMeters / duration
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: mps)
    }
}
