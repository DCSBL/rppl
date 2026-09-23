import Foundation

/// One point on the riding-only playback timeline.
public struct TrackPlaybackPoint: Equatable, Sendable {
    public var setIndex: Int
    public var setNumber: Int
    public var coordinate: MapCoordinate
    public var timestamp: Date
    public var speedKmh: Double?
    /// Seconds from the start of the riding-only timeline (dock time removed).
    public var ridingOffset: TimeInterval

    public init(
        setIndex: Int,
        setNumber: Int,
        coordinate: MapCoordinate,
        timestamp: Date,
        speedKmh: Double?,
        ridingOffset: TimeInterval
    ) {
        self.setIndex = setIndex
        self.setNumber = setNumber
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speedKmh = speedKmh
        self.ridingOffset = ridingOffset
    }
}

/// Scrubbable session track: every set concatenated on a riding-only clock.
///
/// Dock time is removed, so a scrubber spends all of its travel on GPS the rider
/// actually produced instead of stalling through a park day of waiting.
public struct TrackPlaybackTimeline: Equatable, Sendable {
    public var points: [TrackPlaybackPoint]
    public var totalRidingDuration: TimeInterval

    public init(points: [TrackPlaybackPoint], totalRidingDuration: TimeInterval) {
        self.points = points
        self.totalRidingDuration = totalRidingDuration
    }

    public static let empty = TrackPlaybackTimeline(points: [], totalRidingDuration: 0)

    public var isEmpty: Bool { points.count < 2 }

    /// Last point index at or before `progress` (0…1).
    public func index(atProgress progress: Double) -> Int {
        guard !points.isEmpty else { return 0 }
        let clamped = min(max(progress, 0), 1)
        let target = clamped * totalRidingDuration
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].ridingOffset <= target {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    public func point(atProgress progress: Double) -> TrackPlaybackPoint? {
        guard !points.isEmpty else { return nil }
        return points[index(atProgress: progress)]
    }

    /// Per-set polylines covering everything ridden up to `progress`.
    public func polylines(upToProgress progress: Double) -> [[MapCoordinate]] {
        guard !points.isEmpty else { return [] }
        let last = index(atProgress: progress)
        var result: [[MapCoordinate]] = []
        var current: [MapCoordinate] = []
        var currentSet = points[0].setIndex

        for cursor in 0...last {
            let point = points[cursor]
            if point.setIndex != currentSet {
                if current.count >= 2 { result.append(current) }
                current = []
                currentSet = point.setIndex
            }
            current.append(point.coordinate)
        }
        if current.count >= 2 { result.append(current) }
        return result
    }

    /// Trailing comet segment: the last `seconds` of riding before `progress`, same set only.
    public func headTrail(upToProgress progress: Double, seconds: TimeInterval) -> [MapCoordinate] {
        guard !points.isEmpty else { return [] }
        let last = index(atProgress: progress)
        let head = points[last]
        var trail: [MapCoordinate] = []
        var cursor = last
        while cursor >= 0 {
            let point = points[cursor]
            guard point.setIndex == head.setIndex,
                  head.ridingOffset - point.ridingOffset <= seconds
            else {
                break
            }
            trail.append(point.coordinate)
            cursor -= 1
        }
        return trail.reversed()
    }
}

public enum TrackPlaybackBuilder {
    public static func build(
        setTracks: [SessionSetTrack],
        thresholds: DetectionThresholds = .default
    ) -> TrackPlaybackTimeline {
        var points: [TrackPlaybackPoint] = []
        var offset: TimeInterval = 0

        for track in setTracks where track.isRenderable {
            let speeds = TrackSpeedSeries.speedsKmh(for: track.samples, thresholds: thresholds)
            let start = track.samples[0].timestamp
            for index in track.samples.indices {
                let sample = track.samples[index]
                points.append(
                    TrackPlaybackPoint(
                        setIndex: track.setIndex,
                        setNumber: track.setNumber,
                        coordinate: MapCoordinate(sample),
                        timestamp: sample.timestamp,
                        speedKmh: speeds[index],
                        ridingOffset: offset + sample.timestamp.timeIntervalSince(start)
                    )
                )
            }
            offset = points.last?.ridingOffset ?? offset
        }

        return TrackPlaybackTimeline(
            points: points,
            totalRidingDuration: points.last?.ridingOffset ?? 0
        )
    }
}
