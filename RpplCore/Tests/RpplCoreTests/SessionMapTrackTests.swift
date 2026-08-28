import Foundation
import Testing
@testable import RpplCore

@Suite("SessionMapTrackBuilder")
struct SessionMapTrackBuilderTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        offset: TimeInterval,
        lat: Double,
        lon: Double
    ) -> LocationSample {
        LocationSample(
            timestamp: base.addingTimeInterval(offset),
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: 5,
            speed: nil
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

    @Test func commonStartUsesMedian() {
        let tracks = [
            [sample(offset: 0, lat: 52.0, lon: 5.0)],
            [sample(offset: 0, lat: 52.0002, lon: 5.0002)],
            [sample(offset: 0, lat: 52.0004, lon: 5.0004)],
        ]
        let start = SessionMapTrackBuilder.commonStart(from: tracks)!
        #expect(start.latitude == 52.0002)
        #expect(start.longitude == 5.0002)
    }

    @Test func builderProducesHeatmapTracks() throws {
        let locations = straightTrack(latStart: 52.0, lon: 5.0, count: 30)
        let sets = [
            SetSegmentStats(
                index: 1,
                startedAt: base,
                endedAt: base.addingTimeInterval(29),
                duration: 29,
                distanceMeters: 400,
                lapCount: 1
            ),
        ]
        let data = SessionMapTrackBuilder.build(locations: locations, sets: sets)
        #expect(data != nil)
        #expect(data!.heatmapTracks.count == 1)
        #expect(data!.heatmapTracks[0].count >= 2)
    }

    @Test func decodesLegacyMapTracksWithoutHeatmapKey() throws {
        let json = """
        {"start":{"latitude":52.0,"longitude":5.0},"averagedTrack":[],"heatmapTracks":[]}
        """
        let data = try JSONDecoder().decode(SessionMapTrackData.self, from: Data(json.utf8))
        #expect(data.start.latitude == 52.0)
        #expect(data.heatmapTracks.isEmpty)
    }
}
