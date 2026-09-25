import Foundation
import Testing
@testable import RpplCore

/// One labeled set from a real recorded park day, tail-trimmed to the last ~45 s (the part
/// `FallDetector` actually scans). See `Fixtures/FallDetection/2026-09-24-park-day.json` and the
/// `FallDetector` doc comment for how each label was derived from the raw GPS trace.
private struct LabeledSetFixture: Decodable {
    var index: Int
    var startedAt: Date
    var endedAt: Date
    var exitDetectorId: String
    var expectedFallDetected: Bool
    var locations: [LocationSample]
}

private struct RealSessionFixture: Decodable {
    var name: String
    var sets: [LabeledSetFixture]
}

@Suite("FallDetector real session replay")
struct FallDetectionRealSessionTests {
    private static func loadFixture() throws -> RealSessionFixture {
        guard let url = Bundle.module.url(
            forResource: "2026-09-24-park-day",
            withExtension: "json",
            subdirectory: "Fixtures/FallDetection"
        ) else {
            throw FixtureError.missing
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RealSessionFixture.self, from: data)
    }

    @Test func matchesExpectedLabelForEverySet() throws {
        let fixture = try Self.loadFixture()
        for set in fixture.sets {
            let got = FallDetector.detectsFall(in: set.locations)
            #expect(
                got == set.expectedFallDetected,
                "set \(set.index) (exit=\(set.exitDetectorId)): expected fallDetected="
                    + "\(set.expectedFallDetected), got \(got)"
            )
        }
    }

    /// Set 1 is the ground-truth "failed start": cable speed for ~7 s, then GPS goes silent for
    /// 4 s and resumes at a near-stop — no two fixes ever show the cliff directly, only the
    /// blackout rule catches it.
    @Test func flagsTheFailedStartViaGpsBlackout() throws {
        let fixture = try Self.loadFixture()
        let set1 = try #require(fixture.sets.first { $0.index == 1 })
        #expect(FallDetector.detectsFall(in: set1.locations))
    }

    /// Whole-session sanity check: 7 of the 10 labeled sets are real falls (one via the blackout
    /// rule, six via plain cliffs), 2 are controlled stops. Catches an accidental threshold
    /// change that flips the overall balance even if individual per-set tests still pass.
    @Test func sevenOfTenSetsAreFlaggedAsFalls() throws {
        let fixture = try Self.loadFixture()
        let flaggedCount = fixture.sets.filter { FallDetector.detectsFall(in: $0.locations) }.count
        #expect(flaggedCount == 7)
        #expect(fixture.sets.count == 10)
    }
}

private enum FixtureError: Error {
    case missing
}
