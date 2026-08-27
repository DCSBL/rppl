import Foundation

/// RGB stop for speed-colored map segments (0 = slow/red, 1 = fast/green).
public struct SessionMapSpeedColorStop: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Fitness-style red → yellow → green.
    public static func color(normalized: Double) -> SessionMapSpeedColorStop {
        let value = min(1, max(0, normalized))
        if value < 0.5 {
            let blend = value * 2
            return SessionMapSpeedColorStop(red: 1, green: blend, blue: 0)
        }
        let blend = (value - 0.5) * 2
        return SessionMapSpeedColorStop(red: 1 - blend, green: 1, blue: 0)
    }
}

public struct SessionMapSpeedSegment: Sendable, Equatable {
    public var coordinates: [MapCoordinate]
    public var color: SessionMapSpeedColorStop

    public init(coordinates: [MapCoordinate], color: SessionMapSpeedColorStop) {
        self.coordinates = coordinates
        self.color = color
    }
}

public enum SessionMapSpeedColor {
    public static let defaultMaxSegments = 50

    /// Bucket averaged track into colored segments for MapKit polylines.
    public static func segments(
        track: [MapCoordinate],
        speedsKmh: [Double],
        maxSegments: Int = defaultMaxSegments
    ) -> [SessionMapSpeedSegment]? {
        guard track.count >= 2, speedsKmh.count == track.count else { return nil }
        guard speedsKmh.contains(where: { $0 > 0 }) else { return nil }

        let sorted = speedsKmh.filter { $0 > 0 }.sorted()
        guard let rawMin = sorted.first, let rawMax = sorted.last else { return nil }
        let minSpeed = sorted.count >= 4
            ? sorted[sorted.count / 10]
            : rawMin
        let maxSpeed = sorted.count >= 4
            ? sorted[(sorted.count * 9) / 10]
            : rawMax
        let span = max(maxSpeed - minSpeed, 1)

        let bucketCount = min(maxSegments, max(1, track.count - 1))
        let pointsPerBucket = max(1, (track.count - 1) / bucketCount)

        var segments: [SessionMapSpeedSegment] = []
        var startIndex = 0
        while startIndex < track.count - 1 {
            let endIndex = min(track.count - 1, startIndex + pointsPerBucket)
            let slice = Array(track[startIndex...endIndex])
            let sliceSpeeds = speedsKmh[startIndex...endIndex]
            let mean = sliceSpeeds.reduce(0, +) / Double(sliceSpeeds.count)
            let normalized = (mean - minSpeed) / span
            segments.append(
                SessionMapSpeedSegment(
                    coordinates: slice,
                    color: SessionMapSpeedColorStop.color(normalized: normalized)
                )
            )
            if endIndex >= track.count - 1 { break }
            startIndex = endIndex
        }
        return segments.isEmpty ? nil : segments
    }
}
