import Foundation

/// Walking between sets, distilled from the sparse `inactive` GPS (the Watch delivers a fix about
/// every 8 m while not riding, so the walk back to the dock is in the location stream already).
public struct WalkTrackData: Equatable, Sendable {
    /// Meters walked over the whole session (steps at walking pace outside set windows).
    public var walkedMeters: Double
    /// Estimated meters swum: the slow, blurry fixes in the minutes after a set end (the swim back).
    public var swumMeters: Double
    /// Downsampled walking polylines.
    public var tracks: [[MapCoordinate]]

    public init(walkedMeters: Double, swumMeters: Double = 0, tracks: [[MapCoordinate]]) {
        self.walkedMeters = walkedMeters
        self.swumMeters = swumMeters
        self.tracks = tracks
    }
}

/// Picks walking steps out of the GPS between sets: a step counts when its implied speed sits in
/// the walking band and both fixes are sharp. Swimming after a fall is slower and, from the water,
/// a few meters less accurate, so the accuracy gate drops most of it even when the pace overlaps.
public enum WalkTrackBuilder {
    public static let minSpeedKmh = 2.5
    public static let maxSpeedKmh = 7.0
    public static let maxHorizontalAccuracyM = 10.0
    /// Fixes further apart than this are two different walks (standing still delivers no fixes).
    public static let maxStepSeconds: TimeInterval = 60
    /// A swim-out or dock shuffle shorter than this is not a walk.
    public static let minTrackMeters = 20.0
    /// Fixes right after a set end are the fall and the swim, not the walk.
    public static let setEndPadding: TimeInterval = 15
    public static let setStartPadding: TimeInterval = 5
    /// Swimming shows up as slow steps, or blurry ones, shortly after a set end.
    public static let swimMinSpeedKmh = 0.5
    public static let swimMaxSpeedKmh = 4.0
    public static let swimMaxHorizontalAccuracyM = 30.0
    public static let swimWindow: TimeInterval = 240
    public static let pointsPerTrack = 32
    public static let maxTracks = 40

    public static func build(locations: [LocationSample], sets: [SetSegmentStats]) -> WalkTrackData {
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        let windows = sets.map { ($0.startedAt.addingTimeInterval(-setStartPadding), $0.endedAt.addingTimeInterval(setEndPadding)) }
        var walked = 0.0
        var tracks: [[LocationSample]] = []
        var current: [LocationSample] = []
        var previous: LocationSample?

        func close() {
            if pathMeters(current) >= minTrackMeters {
                tracks.append(current)
            }
            current = []
        }

        for sample in sorted {
            guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxHorizontalAccuracyM else {
                continue
            }
            if windows.contains(where: { sample.timestamp >= $0.0 && sample.timestamp <= $0.1 }) {
                close()
                previous = nil
                continue
            }
            defer { previous = sample }
            guard let from = previous else { continue }
            let delta = sample.timestamp.timeIntervalSince(from.timestamp)
            guard delta > 0, delta <= maxStepSeconds else {
                close()
                continue
            }
            let meters = GeoDistance.meters(
                fromLat: from.latitude, fromLon: from.longitude,
                toLat: sample.latitude, toLon: sample.longitude
            )
            let kmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: meters / delta)
            guard kmh >= minSpeedKmh, kmh <= maxSpeedKmh else {
                close()
                continue
            }
            if current.isEmpty { current.append(from) }
            current.append(sample)
            walked += meters
        }
        close()

        let distilled = tracks.prefix(maxTracks).map { track in
            LocationSampleDownsampler.downsample(track, maxCount: pointsPerTrack).map(MapCoordinate.init)
        }
        return WalkTrackData(
            walkedMeters: walked,
            swumMeters: swumMeters(sorted: sorted, sets: sets),
            tracks: Array(distilled)
        )
    }

    /// Meters between consecutive fixes in the `swimWindow` after a set end that are not a walking
    /// step: slower than a walk, or measured from the water with a blurrier fix. An estimate, not
    /// a swim tracker; the Watch gets a fix about every 8 m, so jitter at standstill adds nothing.
    static func swumMeters(sorted: [LocationSample], sets: [SetSegmentStats]) -> Double {
        let ends = sets.map(\.endedAt).sorted()
        let windows = sets.map { ($0.startedAt.addingTimeInterval(-setStartPadding), $0.endedAt.addingTimeInterval(setEndPadding)) }
        func inSwimWindow(_ time: Date) -> Bool {
            guard let end = ends.last(where: { $0 <= time }) else { return false }
            return time.timeIntervalSince(end) <= swimWindow
        }
        var swum = 0.0
        var previous: LocationSample?
        for sample in sorted {
            guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= swimMaxHorizontalAccuracyM,
                  !windows.contains(where: { sample.timestamp >= $0.0 && sample.timestamp <= $0.1 }),
                  inSwimWindow(sample.timestamp)
            else {
                previous = nil
                continue
            }
            defer { previous = sample }
            guard let from = previous else { continue }
            let delta = sample.timestamp.timeIntervalSince(from.timestamp)
            guard delta > 0, delta <= maxStepSeconds else { continue }
            let meters = GeoDistance.meters(
                fromLat: from.latitude, fromLon: from.longitude,
                toLat: sample.latitude, toLon: sample.longitude
            )
            let kmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: meters / delta)
            guard kmh >= swimMinSpeedKmh, kmh < swimMaxSpeedKmh else { continue }
            let sharp = from.horizontalAccuracy <= maxHorizontalAccuracyM && sample.horizontalAccuracy <= maxHorizontalAccuracyM
            if sharp, kmh >= minSpeedKmh { continue }
            swum += meters
        }
        return swum
    }

    static func pathMeters(_ samples: [LocationSample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        var total = 0.0
        for (from, to) in zip(samples, samples.dropFirst()) {
            total += GeoDistance.meters(
                fromLat: from.latitude, fromLon: from.longitude,
                toLat: to.latitude, toLon: to.longitude
            )
        }
        return total
    }
}
