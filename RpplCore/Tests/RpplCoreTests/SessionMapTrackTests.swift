import Foundation
import Testing
@testable import RpplCore

@Suite("SessionMapTrackBuilder")
struct SessionMapTrackBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        offset: TimeInterval,
        lat: Double,
        lon: Double,
        speed: Double? = nil
    ) -> LocationSample {
        LocationSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: 5,
            speed: speed
        )
    }

    private func straightTrack(latStart: Double, lon: Double, count: Int) -> [LocationSample] {
        (0..<count).map { index in
            sample(
                offset: TimeInterval(index),
                lat: latStart + Double(index) * 0.0001,
                lon: lon
            )
        }
    }

    @Test func identicalTracksPickSamePath() {
        let track = straightTrack(latStart: 52.0, lon: 5.0, count: 20)
        let picked = CableTrackRepresentative.mostCommonPath(tracks: [track, track])!
        #expect(picked.count == CableTrackRepresentative.defaultSampleCount)
        #expect(abs(picked[0].latitude - track[0].latitude) < 1e-5)
        #expect(abs(picked.last!.latitude - track.last!.latitude) < 1e-4)
    }

    @Test func medoidPicksNearestRealTrack() {
        let low = straightTrack(latStart: 52.0, lon: 5.0, count: 20)
        let high = straightTrack(latStart: 52.0002, lon: 5.0, count: 20)
        let picked = CableTrackRepresentative.mostCommonPath(tracks: [low, high, high])!
        let midLat = picked[32].latitude
        #expect(abs(midLat - high[10].latitude) < abs(midLat - low[10].latitude))
    }

    @Test func commonStartUsesMedian() {
        let tracks = [
            [sample(offset: 0, lat: 52.0, lon: 5.0)],
            [sample(offset: 0, lat: 52.0002, lon: 5.0002)],
            [sample(offset: 0, lat: 52.0004, lon: 5.0004)],
        ]
        let start = CableTrackRepresentative.commonStart(from: tracks)!
        #expect(start.latitude == 52.0002)
        #expect(start.longitude == 5.0002)
    }

    @Test func builderProducesHeatmapAndAveraged() throws {
        let locations = straightTrack(latStart: 52.0, lon: 5.0, count: 30)
        let rides = [
            RideSegmentStats(
                index: 1,
                startedAt: base,
                endedAt: base.addingTimeInterval(29),
                duration: 29,
                distanceMeters: 400,
                lapCount: 1
            ),
        ]
        let data = SessionMapTrackBuilder.build(locations: locations, rides: rides)
        #expect(data != nil)
        #expect(data!.averagedTrack.count == SessionMapTrackBuilder.averagedPointCount)
        #expect(data!.heatmapTracks.count == 1)
        #expect(data!.heatmapTracks[0].count >= 2)
    }

    @Test func speedSegmentsOrderSlowToFast() {
        let track = (0..<10).map { index in
            MapCoordinate(latitude: 52.0 + Double(index) * 0.0001, longitude: 5.0)
        }
        let speeds = (0..<10).map { Double($0 * 3 + 5) }
        let segments = SessionMapSpeedColor.segments(track: track, speedsKmh: speeds)!
        #expect(!segments.isEmpty)
        #expect(segments.first!.color.red >= segments.last!.color.red)
        #expect(segments.last!.color.green >= segments.first!.color.green)
    }
}
