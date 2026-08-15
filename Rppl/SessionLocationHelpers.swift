import Foundation
import RpplCore

enum SessionLocationHelpers {
    static func sustainedSpeedKmh(from locations: [LocationSample]) -> Double? {
        LocationSpeedStats.sustainedSpeedKmh(from: locations)
    }

    static func sustainedSpeedKmh(
        rides: [RideSegmentStats],
        locations: [LocationSample]
    ) -> Double? {
        if let fromRides = rides.compactMap(\.sustainedSpeedKmh).max() {
            return fromRides
        }
        let windows = rides.map { (start: $0.startedAt, end: $0.endedAt) }
        return LocationSpeedStats.sustainedSpeedKmh(rideWindows: windows, locations: locations)
    }

    /// Prefer ride `averageSpeedKmh` (trimmed); fall back to raw distance/duration.
    static func averageSpeedKmh(for ride: RideSegmentStats) -> Double? {
        if let trimmed = ride.averageSpeedKmh { return trimmed }
        return LocationSpeedStats.averageSpeedKmh(
            distanceMeters: ride.distanceMeters,
            duration: ride.duration
        )
    }

    static func locations(
        for ride: RideSegmentStats,
        in all: [LocationSample]
    ) -> [LocationSample] {
        RideLocationFilter.samples(in: all, from: ride.startedAt, to: ride.endedAt)
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

    /// Centroid of usable GPS points for reverse geocoding.
    static func representativeCoordinate(from locations: [LocationSample]) -> (latitude: Double, longitude: Double)? {
        let usable = locations.filter { sample in
            sample.horizontalAccuracy > 0 && sample.horizontalAccuracy <= 500
        }
        let points = usable.isEmpty ? locations : usable
        guard !points.isEmpty else { return nil }

        let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let longitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return (latitude, longitude)
    }
}
