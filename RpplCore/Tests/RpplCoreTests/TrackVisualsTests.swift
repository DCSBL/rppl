import Foundation
import Testing
@testable import RpplCore

@Suite("TrackSpeedSeries")
struct TrackSpeedSeriesTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        offset: TimeInterval,
        lat: Double,
        lon: Double = 5.0,
        accuracy: Double = 5,
        speed: Double? = nil
    ) -> LocationSample {
        LocationSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: accuracy,
            speed: speed
        )
    }

    @Test func usesReportedSpeed() {
        let track = [
            sample(offset: 0, lat: 52.0, speed: 5),
            sample(offset: 1, lat: 52.0, speed: 5),
        ]
        let speeds = TrackSpeedSeries.speedsKmh(for: track, smoothingRadius: 0)
        #expect(speeds.count == 2)
        #expect(abs((speeds[0] ?? 0) - 18) < 0.001)
    }

    @Test func derivesSpeedWhenReportedMissing() {
        // ~11.1 m north in 1 s ≈ 40 km/h.
        let track = [
            sample(offset: 0, lat: 52.0),
            sample(offset: 1, lat: 52.0001),
        ]
        let speeds = TrackSpeedSeries.speedsKmh(for: track, smoothingRadius: 0)
        #expect(speeds[0] != nil)
        #expect((speeds[0] ?? 0) > 20)
        #expect((speeds[0] ?? 0) < 60)
    }

    @Test func ignoresImplausibleReportedSpeed() {
        // 200 m/s reported, but the points barely move: fall back to the derived speed.
        let track = [
            sample(offset: 0, lat: 52.0, speed: 200),
            sample(offset: 1, lat: 52.00001, speed: 200),
        ]
        let speeds = TrackSpeedSeries.speedsKmh(for: track, smoothingRadius: 0)
        #expect((speeds[0] ?? 999) < 20)
    }

    @Test func dropsSamplesFailingAccuracyGate() {
        let track = [
            sample(offset: 0, lat: 52.0, accuracy: 400, speed: 8),
            sample(offset: 1, lat: 52.0001, accuracy: 5, speed: 8),
        ]
        let speeds = TrackSpeedSeries.speedsKmh(for: track, smoothingRadius: 0)
        #expect(speeds[0] == nil)
        #expect(speeds[1] != nil)
    }

    @Test func percentileRangeTrimsOutliers() {
        let speeds: [Double?] = [1, 20, 21, 22, 23, 24, 25, 90]
        let range = TrackSpeedSeries.percentileRangeKmh(speeds)
        #expect(range != nil)
        #expect((range?.low ?? 0) > 1)
        #expect((range?.high ?? 100) < 90)
    }

    @Test func percentileRangeNilWithoutUsableSpeed() {
        #expect(TrackSpeedSeries.percentileRangeKmh([nil, nil]) == nil)
    }
}

@Suite("TrackSpeedBands")
struct TrackSpeedBandsTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func track(speedsMps: [Double]) -> [LocationSample] {
        speedsMps.enumerated().map { index, speed in
            LocationSample(
                timestamp: base.addingTimeInterval(TimeInterval(index)),
                latitude: 52.0 + Double(index) * 0.0001,
                longitude: 5.0,
                horizontalAccuracy: 5,
                speed: speed
            )
        }
    }

    @Test func scaleClampsFractionAndBands() {
        let scale = TrackSpeedScale(lowKmh: 10, highKmh: 30, bandCount: 5)
        #expect(scale.fraction(forSpeedKmh: 20) == 0.5)
        #expect(scale.fraction(forSpeedKmh: 0) == 0)
        #expect(scale.fraction(forSpeedKmh: 99) == 1)
        #expect(scale.bandIndex(forSpeedKmh: 0) == 0)
        #expect(scale.bandIndex(forSpeedKmh: 99) == 4)
    }

    @Test func scaleWidensFlatSpread() {
        let scale = TrackSpeedScale(lowKmh: 20, highKmh: 20.5, bandCount: 6)
        #expect(scale.highKmh - scale.lowKmh >= TrackSpeedBands.minimumSpreadKmh)
    }

    @Test func singleBandTrackYieldsOneRun() {
        let scale = TrackSpeedScale(lowKmh: 0, highKmh: 60, bandCount: 6)
        let runs = TrackSpeedBands.runs(from: track(speedsMps: [8, 8, 8, 8, 8]), scale: scale)
        #expect(runs.count == 1)
        #expect(runs[0].coordinates.count == 5)
    }

    @Test func bandChangeSplitsRunsAndKeepsLineJoined() {
        let scale = TrackSpeedScale(lowKmh: 0, highKmh: 60, bandCount: 6)
        let samples = track(speedsMps: [3, 3, 3, 3, 15, 15, 15, 15])
        let runs = TrackSpeedBands.runs(from: samples, scale: scale)
        #expect(runs.count >= 2)
        #expect(runs[0].bandIndex < runs[runs.count - 1].bandIndex)
        for index in 1..<runs.count {
            #expect(runs[index - 1].coordinates.last == runs[index].coordinates.first)
        }
    }

    @Test func scaleNilWithoutUsableSpeed() {
        let unusable = [
            LocationSample(
                timestamp: base,
                latitude: 52,
                longitude: 5,
                horizontalAccuracy: 500,
                speed: nil
            ),
        ]
        #expect(TrackSpeedBands.scale(forTracks: [unusable]) == nil)
    }
}

@Suite("SessionSetTrackBuilder")
struct SessionSetTrackBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(offset: TimeInterval) -> LocationSample {
        LocationSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: 52.0 + offset * 0.00001,
            longitude: 5.0,
            horizontalAccuracy: 5,
            speed: 8
        )
    }

    private func set(index: Int, from: TimeInterval, to: TimeInterval) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: base.addingTimeInterval(from),
            endedAt: base.addingTimeInterval(to),
            duration: to - from,
            distanceMeters: 100
        )
    }

    @Test func skipsSetsWithoutGpsButKeepsSetNumbers() {
        let locations = [sample(offset: 100), sample(offset: 101), sample(offset: 102)]
        let sets = [
            set(index: 1, from: 0, to: 10),
            set(index: 2, from: 90, to: 110),
        ]
        let tracks = SessionSetTrackBuilder.tracks(locations: locations, sets: sets)
        #expect(tracks.count == 1)
        #expect(tracks[0].setIndex == 1)
        #expect(tracks[0].setNumber == 2)
    }

    @Test func downsamplesToBudget() {
        let locations = (0..<400).map { sample(offset: TimeInterval($0)) }
        let sets = [set(index: 1, from: 0, to: 400)]
        let tracks = SessionSetTrackBuilder.tracks(locations: locations, sets: sets, pointBudget: 50)
        #expect(tracks.count == 1)
        #expect(tracks[0].samples.count <= 50)
        #expect(tracks[0].samples.count >= 2)
    }

    @Test func emptyWithoutSets() {
        #expect(SessionSetTrackBuilder.tracks(locations: [sample(offset: 0)], sets: []).isEmpty)
    }
}

@Suite("TrackPlaybackTimeline")
struct TrackPlaybackTimelineTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(offset: TimeInterval, lat: Double) -> LocationSample {
        LocationSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat,
            longitude: 5.0,
            horizontalAccuracy: 5,
            speed: 8
        )
    }

    private var timeline: TrackPlaybackTimeline {
        let first = SessionSetTrack(
            setIndex: 0,
            setNumber: 1,
            samples: [
                sample(offset: 0, lat: 52.0),
                sample(offset: 1, lat: 52.0001),
                sample(offset: 2, lat: 52.0002),
            ]
        )
        let second = SessionSetTrack(
            setIndex: 1,
            setNumber: 2,
            samples: [
                sample(offset: 100, lat: 52.001),
                sample(offset: 101, lat: 52.0011),
                sample(offset: 102, lat: 52.0012),
            ]
        )
        return TrackPlaybackBuilder.build(setTracks: [first, second])
    }

    @Test func ridingClockSkipsDockTime() {
        let built = timeline
        #expect(built.points.count == 6)
        #expect(built.totalRidingDuration == 4)
    }

    @Test func progressMapsToPoints() {
        let built = timeline
        #expect(built.index(atProgress: 0) == 0)
        #expect(built.index(atProgress: 1) == 5)
        #expect(built.point(atProgress: 1)?.setNumber == 2)
        #expect(built.point(atProgress: 0)?.setNumber == 1)
    }

    @Test func polylinesSplitPerSet() {
        let built = timeline
        #expect(built.polylines(upToProgress: 1).count == 2)
        #expect(built.polylines(upToProgress: 0.4).count == 1)
    }

    @Test func headTrailStaysInsideCurrentSet() {
        let built = timeline
        let trail = built.headTrail(upToProgress: 1, seconds: 1)
        #expect(trail.count == 2)
        #expect(trail.last == built.point(atProgress: 1)?.coordinate)
    }

    @Test func emptyTimelineIsSafe() {
        let empty = TrackPlaybackBuilder.build(setTracks: [])
        #expect(empty.isEmpty)
        #expect(empty.point(atProgress: 0.5) == nil)
        #expect(empty.polylines(upToProgress: 1).isEmpty)
        #expect(empty.headTrail(upToProgress: 1, seconds: 5).isEmpty)
    }
}

@Suite("GeoBearing")
struct GeoBearingTests {
    @Test func cardinalBearings() {
        let north = GeoBearing.degrees(fromLat: 0, fromLon: 0, toLat: 1, toLon: 0)
        let east = GeoBearing.degrees(fromLat: 0, fromLon: 0, toLat: 0, toLon: 1)
        let south = GeoBearing.degrees(fromLat: 1, fromLon: 0, toLat: 0, toLon: 0)
        #expect(abs(north - 0) < 0.001)
        #expect(abs(east - 90) < 0.001)
        #expect(abs(south - 180) < 0.001)
    }

    @Test func nilForSamePoint() {
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 0),
            latitude: 52,
            longitude: 5,
            horizontalAccuracy: 5
        )
        #expect(GeoBearing.degrees(from: sample, to: sample) == nil)
    }
}
