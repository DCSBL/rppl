import Foundation
import RpplCore

enum SessionLocationHelpers {
    static func peakSpeedKmh(from locations: [LocationSample]) -> Double? {
        let peakMps = locations.compactMap(\.speed).filter { $0 > 0 }.max()
        guard let peakMps else { return nil }
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: peakMps)
    }

    static func locations(
        for ride: RideSegmentStats,
        in all: [LocationSample]
    ) -> [LocationSample] {
        all.filter { $0.timestamp >= ride.startedAt && $0.timestamp <= ride.endedAt }
    }

    /// Evenly pick up to `maxCount` samples so MapKit stays responsive.
    static func downsample(_ locations: [LocationSample], maxCount: Int) -> [LocationSample] {
        guard maxCount > 1, locations.count > maxCount else { return locations }
        let lastIndex = locations.count - 1
        let step = Double(lastIndex) / Double(maxCount - 1)
        var result: [LocationSample] = []
        result.reserveCapacity(maxCount)
        for index in 0..<maxCount {
            let sampleIndex = min(lastIndex, Int((Double(index) * step).rounded()))
            result.append(locations[sampleIndex])
        }
        return result
    }

    static func averageSpeedKmh(distanceMeters: Double, duration: TimeInterval) -> Double? {
        guard duration > 0, distanceMeters > 0 else { return nil }
        let mps = distanceMeters / duration
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: mps)
    }
}
