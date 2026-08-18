import Foundation

/// Peak / sustained / average speed helpers using the same GPS quality gates as detection.
public enum LocationSpeedStats {
    /// Min usable samples in a sustained-speed window.
    public static let sustainedMinSamples = 5
    /// Min time span for a sustained-speed window.
    public static let sustainedMinSpan: TimeInterval = 5

    /// Max usable sample speed in km/h. Ignores accuracy failures, implausible speeds, and jumps.
    public static func peakSpeedKmh(
        from locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        let usable = usableSpeeds(from: locations, thresholds: thresholds)
        guard let peakMps = usable.map(\.speedMps).max() else { return nil }
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

    /// Best mean speed (km/h) over consecutive usable samples spanning ≥5 samples and ≥5 s.
    /// Falls back to mean of ≥2 usable samples when no full window exists.
    public static func sustainedSpeedKmh(
        from locations: [LocationSample],
        thresholds: DetectionThresholds = .default,
        minSamples: Int = sustainedMinSamples,
        minSpan: TimeInterval = sustainedMinSpan
    ) -> Double? {
        let usable = usableSpeeds(from: locations, thresholds: thresholds)
        guard !usable.isEmpty else { return nil }

        if usable.count >= minSamples {
            var bestMeanMps: Double?
            for start in 0..<usable.count {
                var end = start + minSamples - 1
                guard end < usable.count else { break }
                while end < usable.count {
                    let span = usable[end].timestamp.timeIntervalSince(usable[start].timestamp)
                    if span >= minSpan {
                        let slice = usable[start...end]
                        let mean = slice.map(\.speedMps).reduce(0, +) / Double(slice.count)
                        bestMeanMps = max(bestMeanMps ?? mean, mean)
                        break
                    }
                    end += 1
                }
            }
            if let bestMeanMps {
                return SpeedUnits.kilometersPerHour(fromMetersPerSecond: bestMeanMps)
            }
        }

        guard usable.count >= 2 else { return nil }
        let mean = usable.map(\.speedMps).reduce(0, +) / Double(usable.count)
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: mean)
    }

    /// Max sustained speed across ride windows.
    public static func sustainedSpeedKmh(
        rideWindows: [(start: Date, end: Date)],
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        var sessionBest: Double?
        for window in rideWindows {
            let samples = RideLocationFilter.samples(in: locations, from: window.start, to: window.end)
            guard let ride = sustainedSpeedKmh(from: samples, thresholds: thresholds) else { continue }
            sessionBest = max(sessionBest ?? ride, ride)
        }
        return sessionBest
    }

    /// Ride meters / riding duration in m/s. HealthKit `HKMetadataKeyAverageSpeed` and speed samples.
    public static func averageSpeedMetersPerSecond(
        distanceMeters: Double,
        duration: TimeInterval
    ) -> Double? {
        guard duration > 0, distanceMeters > 0 else { return nil }
        return distanceMeters / duration
    }

    public static func averageSpeedKmh(distanceMeters: Double, duration: TimeInterval) -> Double? {
        guard let mps = averageSpeedMetersPerSecond(distanceMeters: distanceMeters, duration: duration) else {
            return nil
        }
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: mps)
    }

    /// Full-ride average after trimming start/end tails at/below stopped speed (km/h).
    /// Uses trimmed path distance / trimmed duration.
    public static func trimmedAverageSpeedKmh(
        locations: [LocationSample],
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM,
        stoppedSpeedKmh: Double = DetectionThresholds.default.stoppedSpeedKmh,
        thresholds: DetectionThresholds = .default
    ) -> Double? {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        let usable = usableSpeeds(from: sorted, thresholds: thresholds)
        guard !usable.isEmpty else {
            return averageSpeedKmh(
                distanceMeters: SessionStatsBuilder.distanceMeters(
                    locations: sorted,
                    from: sorted.first!.timestamp,
                    to: sorted.last!.timestamp,
                    maxHorizontalAccuracyM: maxHorizontalAccuracyM
                ),
                duration: sorted.last!.timestamp.timeIntervalSince(sorted.first!.timestamp)
            )
        }

        let stoppedMps = SpeedUnits.metersPerSecond(fromKilometersPerHour: stoppedSpeedKmh)
        var firstMoving = 0
        while firstMoving < usable.count, usable[firstMoving].speedMps <= stoppedMps {
            firstMoving += 1
        }
        var lastMoving = usable.count - 1
        while lastMoving >= firstMoving, usable[lastMoving].speedMps <= stoppedMps {
            lastMoving -= 1
        }
        guard firstMoving <= lastMoving else { return nil }

        let trimStart = usable[firstMoving].timestamp
        let trimEnd = usable[lastMoving].timestamp
        guard trimEnd > trimStart else { return nil }

        let distance = SessionStatsBuilder.distanceMeters(
            locations: sorted,
            from: trimStart,
            to: trimEnd,
            maxHorizontalAccuracyM: maxHorizontalAccuracyM
        )
        return averageSpeedKmh(distanceMeters: distance, duration: trimEnd.timeIntervalSince(trimStart))
    }

    // MARK: - Usable speeds

    struct UsableSpeed: Equatable {
        var timestamp: Date
        var speedMps: Double
    }

    static func usableSpeeds(
        from locations: [LocationSample],
        thresholds: DetectionThresholds
    ) -> [UsableSpeed] {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let filter = GpsSignalFilter(thresholds: thresholds)
        var previousUsableMps: Double?
        var result: [UsableSpeed] = []

        for sample in sorted {
            let tick = DetectionTick(
                timestamp: sample.timestamp,
                speedMps: sample.speed,
                horizontalAccuracy: sample.horizontalAccuracy
            )
            let outcome = filter.evaluate(tick, previousUsableSpeedMps: previousUsableMps)
            guard let usable = outcome.usableSpeedMps, usable > 0 else { continue }
            previousUsableMps = usable
            result.append(UsableSpeed(timestamp: sample.timestamp, speedMps: usable))
        }
        return result
    }
}
