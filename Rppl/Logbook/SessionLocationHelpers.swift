import Foundation
import RpplCore

enum SessionLocationHelpers {
    static func averageSpeedKmh(for set: SetSegmentStats) -> Double? {
        if let trimmed = set.averageSpeedKmh { return trimmed }
        return LocationSpeedStats.averageSpeedKmh(
            distanceMeters: set.distanceMeters,
            duration: set.duration
        )
    }

    static func peakSpeedKmh(for set: SetSegmentStats, locations: [LocationSample] = []) -> Double? {
        if let peak = set.peakSpeedKmh { return peak }
        return LocationSpeedStats.peakSpeedKmh(from: locations)
    }

    static func peakSpeedKmh(
        sets: [SetSegmentStats],
        locations: [LocationSample]
    ) -> Double? {
        if let fromRides = sets.compactMap(\.peakSpeedKmh).max() {
            return fromRides
        }
        let windows = sets.map { (start: $0.startedAt, end: $0.endedAt) }
        return LocationSpeedStats.peakSpeedKmh(setWindows: windows, locations: locations)
    }

    static func locations(
        for set: SetSegmentStats,
        in all: [LocationSample]
    ) -> [LocationSample] {
        SetLocationFilter.samples(in: all, from: set.startedAt, to: set.endedAt)
    }

    static func downsample(_ locations: [LocationSample], maxCount: Int) -> [LocationSample] {
        LocationSampleDownsampler.downsample(locations, maxCount: maxCount)
    }

    static func representativeCoordinate(from locations: [LocationSample]) -> (latitude: Double, longitude: Double)? {
        GeoCentroid.representative(from: locations)
    }
}
