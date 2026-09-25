import Foundation
import Testing
@testable import RpplCore

private struct DetectionFixture: Decodable {
    var name: String
    var manifest: SessionManifest
    var locations: [LocationSample]
}

/// Real recorded sets from `Fixtures/Detection` — every one here ends with GPS speed collapsing
/// to a near-stop within ~2 s (a fall or hard letting-go), which is what calibrated
/// `FallDetectionThresholds.default`. See `FallDetector` doc comment for the numbers.
@Suite("FallDetector fixture replay")
struct FallDetectionFixtureTests {
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

    private static func statsFor(_ stem: String) throws -> SessionStats {
        let fixture = try loadFixture(named: stem)
        let detections = DetectionEngine.replay(locations: fixture.locations)
        return SessionStatsBuilder.build(
            manifest: fixture.manifest,
            detections: detections,
            locations: fixture.locations,
            health: []
        )
    }

    @Test(
        arguments: [
            "good-ride-1",
            "good-ride-2",
            "walk-spike-orig",
            "walk-spike-fp1",
        ]
    )
    func flagsTheSetThatEndsInACliff(stem: String) throws {
        let stats = try Self.statsFor(stem)
        #expect(!stats.sets.isEmpty, "fixture \(stem) produced no sets")
        #expect(stats.sets.contains { $0.fallDetected }, "fixture \(stem) should flag a fall")
    }

    /// This set ends through a GPS gap rather than a visible speed cliff — no cliff to flag.
    @Test func doesNotFlagAGpsGapEnding() throws {
        let stats = try Self.statsFor("walk-spike-fp2")
        #expect(stats.sets.allSatisfy { !$0.fallDetected })
    }
}

private enum FixtureError: Error {
    case missing(String)
}
