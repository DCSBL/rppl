import Foundation

/// Build distilled session map polylines for `derived/view.json`.
public enum SessionMapTrackBuilder {
    public static let averagedPointCount = 64
    public static let heatmapPointsPerSet = 32
    public static let maxHeatmapSets = 24

    public static func build(
        locations: [LocationSample],
        sets: [SetSegmentStats]
    ) -> SessionMapTrackData? {
        let setTracks = SetLocationFilter.tracks(from: locations, sets: sets)
            .filter { $0.count >= 2 }
        guard !setTracks.isEmpty else { return nil }
        guard let averaged = CableTrackRepresentative.average(
            tracks: setTracks,
            sampleCount: averagedPointCount
        ) else {
            return nil
        }
        guard let start = CableTrackRepresentative.commonStart(from: setTracks) else {
            return nil
        }

        let heatmapTracks = setTracks.prefix(maxHeatmapSets).map { track in
            LocationSampleDownsampler.downsample(track, maxCount: heatmapPointsPerSet)
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
