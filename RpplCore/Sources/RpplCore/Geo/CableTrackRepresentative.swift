import Foundation

/// Average multiple ride tracks into one representative cable loop.
public enum CableTrackRepresentative {
    public static let defaultSampleCount = 64

    /// One path per ride resampled to equal arc length, then lat/lon (and speed) averaged per index.
    public static func average(
        tracks: [[LocationSample]],
        sampleCount: Int = defaultSampleCount
    ) -> [LocationSample]? {
        let valid = tracks.filter { $0.count >= 2 }
        guard !valid.isEmpty else { return nil }
        guard sampleCount >= 2 else { return nil }

        if valid.count == 1 {
            return LocationSampleDownsampler.downsample(valid[0], maxCount: sampleCount)
        }

        let resampled = valid.map { resampleByArcLength($0, count: sampleCount) }
        let baseTime = valid.first?.first?.timestamp ?? Date(timeIntervalSince1970: 0)
        var averaged: [LocationSample] = []
        averaged.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let points = resampled.map { $0[index] }
            let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
            let longitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
            let speeds = points.compactMap(\.speed).filter { $0 >= 0 }
            let speed = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
            let accuracy = points.map(\.horizontalAccuracy).reduce(0, +) / Double(points.count)
            averaged.append(
                LocationSample(
                    timestamp: baseTime.addingTimeInterval(TimeInterval(index)),
                    latitude: latitude,
                    longitude: longitude,
                    horizontalAccuracy: accuracy,
                    speed: speed
                )
            )
        }
        return averaged
    }

    /// Median of each ride's first GPS point (common dock / cut-in).
    public static func commonStart(from tracks: [[LocationSample]]) -> MapCoordinate? {
        let starts = tracks.compactMap(\.first).map(MapCoordinate.init)
        guard !starts.isEmpty else { return nil }
        let latitudes = starts.map(\.latitude).sorted()
        let longitudes = starts.map(\.longitude).sorted()
        let mid = starts.count / 2
        return MapCoordinate(latitude: latitudes[mid], longitude: longitudes[mid])
    }

    // MARK: - Arc-length resample

    static func trackDistanceMeters(_ track: [LocationSample]) -> Double {
        guard track.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<track.count {
            let prev = track[index - 1]
            let cur = track[index]
            total += GeoDistance.meters(
                fromLat: prev.latitude,
                fromLon: prev.longitude,
                toLat: cur.latitude,
                toLon: cur.longitude
            )
        }
        return total
    }

    static func resampleByArcLength(_ track: [LocationSample], count: Int) -> [LocationSample] {
        guard count >= 2, track.count >= 2 else { return track }
        if track.count == count { return track }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(track.count)
        for index in 1..<track.count {
            let prev = track[index - 1]
            let cur = track[index]
            let step = GeoDistance.meters(
                fromLat: prev.latitude,
                fromLon: prev.longitude,
                toLat: cur.latitude,
                toLon: cur.longitude
            )
            cumulative.append(cumulative[index - 1] + step)
        }

        let total = cumulative.last ?? 0
        guard total > 0 else { return LocationSampleDownsampler.downsample(track, maxCount: count) }

        var result: [LocationSample] = []
        result.reserveCapacity(count)
        var segmentIndex = 0

        for sampleIndex in 0..<count {
            let target = total * Double(sampleIndex) / Double(count - 1)
            while segmentIndex + 1 < cumulative.count, cumulative[segmentIndex + 1] < target {
                segmentIndex += 1
            }
            if segmentIndex >= track.count - 1 {
                result.append(track[track.count - 1])
                continue
            }

            let startDistance = cumulative[segmentIndex]
            let endDistance = cumulative[segmentIndex + 1]
            let span = max(endDistance - startDistance, 1e-9)
            let fraction = (target - startDistance) / span
            let from = track[segmentIndex]
            let to = track[segmentIndex + 1]
            let latitude = from.latitude + (to.latitude - from.latitude) * fraction
            let longitude = from.longitude + (to.longitude - from.longitude) * fraction
            let speed: Double?
            if let fromSpeed = from.speed, let toSpeed = to.speed, fromSpeed >= 0, toSpeed >= 0 {
                speed = fromSpeed + (toSpeed - fromSpeed) * fraction
            } else {
                speed = from.speed ?? to.speed
            }
            result.append(
                LocationSample(
                    timestamp: from.timestamp.addingTimeInterval(
                        to.timestamp.timeIntervalSince(from.timestamp) * fraction
                    ),
                    latitude: latitude,
                    longitude: longitude,
                    horizontalAccuracy: max(from.horizontalAccuracy, to.horizontalAccuracy),
                    speed: speed
                )
            )
        }
        return result
    }
}
