import Foundation

/// Build distilled session map polylines for `derived/view.json`.
public enum SessionMapTrackBuilder {
    public static let averagedPointCount = 64
    public static let heatmapPointsPerRide = 32
    public static let maxHeatmapRides = 24

    public static func build(
        locations: [LocationSample],
        rides: [RideSegmentStats]
    ) -> SessionMapTrackData? {
        let rideTracks = RideLocationFilter.tracks(from: locations, rides: rides)
            .filter { $0.count >= 2 }
        guard !rideTracks.isEmpty else { return nil }
        guard let averaged = CableTrackRepresentative.average(
            tracks: rideTracks,
            sampleCount: averagedPointCount
        ) else {
            return nil
        }
        guard let start = CableTrackRepresentative.commonStart(from: rideTracks) else {
            return nil
        }

        let heatmapTracks = rideTracks.prefix(maxHeatmapRides).map { track in
            LocationSampleDownsampler.downsample(track, maxCount: heatmapPointsPerRide)
                .map(MapCoordinate.init)
        }

        let averagedTrack = averaged.map(MapCoordinate.init)
        let averagedSpeedKmh = speedKmhAlongTrack(averaged)

        return SessionMapTrackData(
            start: start,
            averagedTrack: averagedTrack,
            heatmapTracks: heatmapTracks,
            averagedSpeedKmh: averagedSpeedKmh
        )
    }

    static func speedKmhAlongTrack(_ track: [LocationSample]) -> [Double]? {
        var values: [Double] = []
        values.reserveCapacity(track.count)
        var hasAny = false

        for index in 0..<track.count {
            if index == 0 {
                if let speed = usableSpeedKmh(track[index], previous: nil) {
                    values.append(speed)
                    hasAny = true
                } else {
                    values.append(0)
                }
                continue
            }
            if let speed = usableSpeedKmh(track[index], previous: track[index - 1]) {
                values.append(speed)
                hasAny = true
            } else if let last = values.last {
                values.append(last)
            } else {
                values.append(0)
            }
        }
        return hasAny ? values : nil
    }

    private static func usableSpeedKmh(_ sample: LocationSample, previous: LocationSample?) -> Double? {
        if let speed = sample.speed, speed >= 0 {
            return SpeedUnits.kilometersPerHour(fromMetersPerSecond: speed)
        }
        guard let previous else { return nil }
        let delta = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard delta > 0 else { return nil }
        let distance = GeoDistance.meters(
            fromLat: previous.latitude,
            fromLon: previous.longitude,
            toLat: sample.latitude,
            toLon: sample.longitude
        )
        guard distance > 0 else { return nil }
        return SpeedUnits.kilometersPerHour(fromMetersPerSecond: distance / delta)
    }
}
