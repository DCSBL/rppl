import Foundation

/// Pick the most common set path across laps (medoid), not a mean that collapses loops.
public enum CableTrackRepresentative {
    public static let defaultSampleCount = 64

    /// Medoid lap: resample, circularly align, then pick the track closest to all others.
    public static func mostCommonPath(
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
        let aligned = alignTracksCircularly(resampled)

        var bestIndex = 0
        var bestCost = Double.infinity
        for index in aligned.indices {
            var cost = 0.0
            for other in aligned.indices where other != index {
                cost += meanPointDistanceMeters(aligned[index], aligned[other])
            }
            if cost < bestCost {
                bestCost = cost
                bestIndex = index
            }
        }
        return aligned[bestIndex]
    }

    /// Backward-compatible entry point; uses medoid path selection.
    public static func average(
        tracks: [[LocationSample]],
        sampleCount: Int = defaultSampleCount
    ) -> [LocationSample]? {
        mostCommonPath(tracks: tracks, sampleCount: sampleCount)
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

    // MARK: - Alignment

    static func alignTracksCircularly(_ tracks: [[LocationSample]]) -> [[LocationSample]] {
        guard let reference = tracks.first else { return tracks }
        return tracks.enumerated().map { index, track in
            guard index > 0 else { return track }
            return bestCircularMatch(reference: reference, candidate: track)
        }
    }

    static func bestCircularMatch(
        reference: [LocationSample],
        candidate: [LocationSample]
    ) -> [LocationSample] {
        guard reference.count == candidate.count, reference.count >= 2 else { return candidate }

        var bestTrack = candidate
        var bestDistance = meanPointDistanceMeters(reference, candidate)

        for offset in 0..<candidate.count {
            let rotated = rotate(candidate, by: offset)
            let forward = meanPointDistanceMeters(reference, rotated)
            if forward < bestDistance {
                bestDistance = forward
                bestTrack = rotated
            }

            let reversed = Array(rotated.reversed())
            let backward = meanPointDistanceMeters(reference, reversed)
            if backward < bestDistance {
                bestDistance = backward
                bestTrack = reversed
            }
        }
        return bestTrack
    }

    static func rotate(_ track: [LocationSample], by offset: Int) -> [LocationSample] {
        guard !track.isEmpty else { return track }
        let normalized = ((offset % track.count) + track.count) % track.count
        guard normalized > 0 else { return track }
        return Array(track[normalized...]) + Array(track[..<normalized])
    }

    static func meanPointDistanceMeters(_ left: [LocationSample], _ right: [LocationSample]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return .infinity }
        var total = 0.0
        for index in left.indices {
            total += GeoDistance.meters(
                fromLat: left[index].latitude,
                fromLon: left[index].longitude,
                toLat: right[index].latitude,
                toLon: right[index].longitude
            )
        }
        return total / Double(left.count)
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
