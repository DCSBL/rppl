import Foundation

/// Per-set time series for the debug charts: speed, altitude and g-force, as seconds since set start.
public struct SetTelemetry: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var offset: TimeInterval
        public var value: Double

        public init(offset: TimeInterval, value: Double) {
            self.offset = offset
            self.value = value
        }
    }

    /// GPS speed in km/h (negative / missing readings skipped).
    public var speedKmh: [Point]
    /// Altitude in meters relative to the first altitude reading in the set.
    public var altitudeMeters: [Point]
    /// Magnitude of gravity-free user acceleration in g; peak per time bucket so spikes survive downsampling.
    public var gForce: [Point]

    public var isEmpty: Bool { speedKmh.isEmpty && altitudeMeters.isEmpty && gForce.isEmpty }

    public init(speedKmh: [Point] = [], altitudeMeters: [Point] = [], gForce: [Point] = []) {
        self.speedKmh = speedKmh
        self.altitudeMeters = altitudeMeters
        self.gForce = gForce
    }
}

public enum SetTelemetryBuilder {
    public static func build(
        locations: [LocationSample],
        motion: [MotionSample],
        from start: Date,
        to end: Date,
        maxPoints: Int = 240
    ) -> SetTelemetry {
        guard end > start, maxPoints > 1 else { return SetTelemetry() }

        let inWindow = locations
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }

        let speed = inWindow.compactMap { sample -> SetTelemetry.Point? in
            guard let speed = sample.speed, speed >= 0 else { return nil }
            return .init(offset: sample.timestamp.timeIntervalSince(start), value: speed * 3.6)
        }

        let altitudes = inWindow.compactMap { sample -> (Date, Double)? in
            guard let altitude = sample.altitude else { return nil }
            return (sample.timestamp, altitude)
        }
        let baseline = altitudes.first?.1 ?? 0
        let altitude = altitudes.map {
            SetTelemetry.Point(offset: $0.0.timeIntervalSince(start), value: $0.1 - baseline)
        }

        return SetTelemetry(
            speedKmh: thin(speed, maxCount: maxPoints),
            altitudeMeters: thin(altitude, maxCount: maxPoints),
            gForce: peakBuckets(motion: motion, from: start, to: end, buckets: maxPoints)
        )
    }

    private static func thin(_ points: [SetTelemetry.Point], maxCount: Int) -> [SetTelemetry.Point] {
        guard points.count > maxCount else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[Int((Double($0) * step).rounded())] }
    }

    private static func peakBuckets(
        motion: [MotionSample],
        from start: Date,
        to end: Date,
        buckets: Int
    ) -> [SetTelemetry.Point] {
        let duration = end.timeIntervalSince(start)
        var peaks = [Double?](repeating: nil, count: buckets)
        for sample in motion where sample.timestamp >= start && sample.timestamp <= end {
            let g = (sample.userAccelX * sample.userAccelX
                + sample.userAccelY * sample.userAccelY
                + sample.userAccelZ * sample.userAccelZ).squareRoot()
            let index = min(buckets - 1, Int(sample.timestamp.timeIntervalSince(start) / duration * Double(buckets)))
            peaks[index] = max(peaks[index] ?? 0, g)
        }
        let width = duration / Double(buckets)
        return peaks.enumerated().compactMap { index, peak in
            peak.map { .init(offset: (Double(index) + 0.5) * width, value: $0) }
        }
    }
}
