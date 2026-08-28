import Foundation
import Testing
@testable import RpplCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func location(at offset: TimeInterval, lat: Double, lon: Double) -> LocationSample {
    LocationSample(
        timestamp: t0.addingTimeInterval(offset),
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: 10,
        speed: 5
    )
}

private func set(index: Int, from start: TimeInterval, to end: TimeInterval) -> SetSegmentStats {
    SetSegmentStats(
        index: index,
        startedAt: t0.addingTimeInterval(start),
        endedAt: t0.addingTimeInterval(end),
        duration: end - start,
        distanceMeters: 10
    )
}

@Suite("SetLocationFilter")
struct SetLocationFilterTests {
    @Test func dropsWalkingBetweenRides() {
        let locations = [
            location(at: 5, lat: 52.0, lon: 5.0),
            location(at: 12, lat: 52.001, lon: 5.0),
            location(at: 18, lat: 52.0015, lon: 5.0),
            location(at: 60, lat: 52.002, lon: 5.0),
            location(at: 110, lat: 52.003, lon: 5.0),
            location(at: 120, lat: 52.004, lon: 5.0),
        ]
        let sets = [
            set(index: 1, from: 10, to: 20),
            set(index: 2, from: 100, to: 130),
        ]
        let tracks = SetLocationFilter.tracks(from: locations, sets: sets)
        #expect(tracks.count == 2)
        #expect(tracks[0].count == 2)
        #expect(tracks[1].count == 2)
        #expect(tracks[0][0].latitude == 52.001)
        #expect(tracks[1][0].latitude == 52.003)
    }

    @Test func omitsSinglePointRide() {
        let locations = [
            location(at: 5, lat: 52.0, lon: 5.0),
            location(at: 15, lat: 52.001, lon: 5.0),
        ]
        let sets = [set(index: 1, from: 10, to: 20)]
        let tracks = SetLocationFilter.tracks(from: locations, sets: sets)
        #expect(tracks.isEmpty)
    }

    @Test func keepsTwoPointRide() {
        let locations = [
            location(at: 10, lat: 52.0, lon: 5.0),
            location(at: 20, lat: 52.001, lon: 5.0),
        ]
        let sets = [set(index: 1, from: 10, to: 20)]
        let tracks = SetLocationFilter.tracks(from: locations, sets: sets)
        #expect(tracks.count == 1)
        #expect(tracks[0].count == 2)
    }
}
