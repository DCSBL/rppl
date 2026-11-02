import Foundation
import Testing
@testable import RpplCore

@Suite("WalkTrackBuilder")
struct WalkTrackBuilderTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    /// Degrees of latitude per meter.
    private let latPerMeter = 1.0 / 110_574

    private func set(_ index: Int, from: TimeInterval, to: TimeInterval) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: t0.addingTimeInterval(from),
            endedAt: t0.addingTimeInterval(to),
            duration: to - from,
            distanceMeters: 1_000
        )
    }

    /// Fixes every `stepMeters` along a north-bound line at `kmh`, starting at `offset` seconds.
    private func line(
        from offset: TimeInterval, meters: Double, kmh: Double, stepMeters: Double = 8, accuracy: Double = 4
    ) -> [LocationSample] {
        let stepSeconds = stepMeters / (kmh / 3.6)
        return stride(from: 0.0, through: meters, by: stepMeters).enumerated().map { index, metersNorth in
            LocationSample(
                timestamp: t0.addingTimeInterval(offset + Double(index) * stepSeconds),
                latitude: 52.0 + metersNorth * latPerMeter,
                longitude: 5.0,
                horizontalAccuracy: accuracy,
                speed: kmh / 3.6
            )
        }
    }

    @Test func walkBetweenSetsIsCountedAndDrawn() {
        let sets = [set(1, from: 0, to: 100), set(2, from: 400, to: 500)]
        // 160 m walk at 4.5 km/h, starting well after the fall-and-swim padding.
        let walk = line(from: 150, meters: 160, kmh: 4.5)
        let data = WalkTrackBuilder.build(locations: walk, sets: sets)

        #expect(abs(data.walkedMeters - 160) < 2)
        #expect(data.tracks.count == 1)
        #expect(data.tracks[0].count >= 2)
        #expect(data.tracks[0].count <= WalkTrackBuilder.pointsPerTrack)
    }

    @Test func ridingSwimmingAndBlurryFixesAreNotWalking() {
        let sets = [set(1, from: 0, to: 100)]
        let riding = line(from: 10, meters: 300, kmh: 30)
        let swim = line(from: 200, meters: 100, kmh: 1.5)
        let blurry = line(from: 600, meters: 100, kmh: 4.5, accuracy: 18)
        let data = WalkTrackBuilder.build(locations: riding + swim + blurry, sets: sets)

        #expect(data.walkedMeters == 0)
        #expect(data.tracks.isEmpty)
    }

    @Test func shortShuffleAddsMetersButNoTrack() {
        let data = WalkTrackBuilder.build(locations: line(from: 0, meters: 12, kmh: 4), sets: [])
        #expect(data.walkedMeters > 0)
        #expect(data.tracks.isEmpty)
    }

    @Test func longStandstillSplitsTracks() {
        let first = line(from: 0, meters: 60, kmh: 4)
        let second = line(from: 400, meters: 60, kmh: 4)
        let data = WalkTrackBuilder.build(locations: first + second, sets: [])
        #expect(data.tracks.count == 2)
        #expect(abs(data.walkedMeters - 112) < 2)
    }

    @Test func statsAndMapTracksCarryTheWalk() throws {
        let sets = [set(1, from: 0, to: 100)]
        let walk = line(from: 150, meters: 100, kmh: 4.5)
        let map = SessionMapTrackBuilder.build(locations: line(from: 0, meters: 300, kmh: 30) + walk, sets: sets)
        #expect(map?.walkTracks?.count == 1)

        let encoded = try JSONEncoder().encode(try #require(map))
        let decoded = try JSONDecoder().decode(SessionMapTrackData.self, from: encoded)
        #expect(decoded.walkTracks?.count == 1)

        let legacy = Data(#"{"start":{"latitude":52,"longitude":5},"heatmapTracks":[]}"#.utf8)
        #expect(try JSONDecoder().decode(SessionMapTrackData.self, from: legacy).walkTracks == nil)
    }
}
