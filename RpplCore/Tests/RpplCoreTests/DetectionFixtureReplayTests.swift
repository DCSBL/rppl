import Foundation
import Testing
@testable import RpplCore

private struct DetectionFixture: Decodable {
    var name: String
    var manifest: SessionManifest
    var locations: [LocationSample]
    var expectedRideEnters: Int
}

@Suite("DetectionFixtureReplay")
struct DetectionFixtureReplayTests {
    private static let fixtureNames = [
        "walk-spike-orig",
        "walk-spike-fp1",
        "walk-spike-fp2",
        "walk-spike-fp3",
        "walk-spike-fp4",
        "good-ride-1",
        "good-ride-2",
    ]

    private static func loadFixture(named stem: String) throws -> DetectionFixture {
        guard let url = Bundle.module.url(
            forResource: stem,
            withExtension: "json",
            subdirectory: "Fixtures/Detection"
        ) else {
            throw FixtureError.missing(stem)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DetectionFixture.self, from: data)
    }

    @Test(arguments: fixtureNames)
    func replayMatchesExpectedRideEnterCount(stem: String) throws {
        let fixture = try Self.loadFixture(named: stem)
        let events = DetectionEngine.replay(locations: fixture.locations)
        let enters = events.filter { $0.detectorId == "ride_enter" }
        #expect(
            enters.count == fixture.expectedRideEnters,
            "fixture \(fixture.name): expected \(fixture.expectedRideEnters) ride_enter, got \(enters.count)"
        )
    }

    @Test func walkGpsSpikePatternStaysInactive() {
        // Mimics dock walk spike: ~5 km/h then brief 22→18 km/h for 2 s (below 3 s hold @ 20 km/h).
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 318, speedKmh: 5))
        _ = engine.process(tick(at: 322, speedKmh: 5))
        _ = engine.process(tick(at: 323, speedKmh: 22.6))
        _ = engine.process(tick(at: 324, speedKmh: 18.4))
        _ = engine.process(tick(at: 325, speedKmh: 18.4))
        _ = engine.process(tick(at: 326, speedKmh: 14))
        #expect(engine.currentCode == DetectionCodes.inactive)
    }

    @Test func walkBumpFixtureSliceStaysInactive() {
        // Same shape as walk-spike-fp4 (14:10 bump): walk then 21.5 for 2 s.
        var engine = DetectionEngine()
        _ = engine.makeSessionStartEvent(at: t0)
        _ = engine.process(tick(at: 0, speedKmh: 6.7))
        _ = engine.process(tick(at: 1, speedKmh: 21.5))
        _ = engine.process(tick(at: 2, speedKmh: 21.5))
        _ = engine.process(tick(at: 3, speedKmh: 19.9))
        #expect(engine.currentCode == DetectionCodes.inactive)
    }
}

private enum FixtureError: Error {
    case missing(String)
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func tick(
    at offset: TimeInterval,
    speedKmh: Double?,
    accuracy: Double? = 10,
    water: String? = nil,
    activity: String? = nil
) -> DetectionTick {
    DetectionTick(
        timestamp: t0.addingTimeInterval(offset),
        speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
        horizontalAccuracy: accuracy,
        waterSubmersionState: water,
        motionActivity: activity
    )
}
