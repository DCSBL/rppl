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
        if stem.hasPrefix("good-ride") {
            #expect(!enters.isEmpty, "good-ride fixture \(fixture.name) must enter at least one ride")
        }
    }
}

private enum FixtureError: Error {
    case missing(String)
}
