import Foundation
import RpplCore

enum SessionLocationHelpers {
    static func averageSpeedKmh(for ride: RideSegmentStats) -> Double? {
        if let trimmed = ride.averageSpeedKmh { return trimmed }
        return LocationSpeedStats.averageSpeedKmh(
            distanceMeters: ride.distanceMeters,
            duration: ride.duration
        )
    }

    static func peakSpeedKmh(for ride: RideSegmentStats, locations: [LocationSample] = []) -> Double? {
        if let peak = ride.peakSpeedKmh { return peak }
        return LocationSpeedStats.peakSpeedKmh(from: locations)
    }

    static func peakSpeedKmh(
        rides: [RideSegmentStats],
        locations: [LocationSample]
    ) -> Double? {
        if let fromRides = rides.compactMap(\.peakSpeedKmh).max() {
            return fromRides
        }
        let windows = rides.map { (start: $0.startedAt, end: $0.endedAt) }
        return LocationSpeedStats.peakSpeedKmh(rideWindows: windows, locations: locations)
    }

    static func locations(
        for ride: RideSegmentStats,
        in all: [LocationSample]
    ) -> [LocationSample] {
        RideLocationFilter.samples(in: all, from: ride.startedAt, to: ride.endedAt)
    }

    static func downsample(_ locations: [LocationSample], maxCount: Int) -> [LocationSample] {
        LocationSampleDownsampler.downsample(locations, maxCount: maxCount)
    }

    static func representativeCoordinate(from locations: [LocationSample]) -> (latitude: Double, longitude: Double)? {
        GeoCentroid.representative(from: locations)
    }
}
