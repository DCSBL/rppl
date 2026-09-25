import Foundation
import Testing
@testable import RpplCore

/// One labeled set from a real recorded park day, tail-trimmed to the last ~45 s. GPS locations
/// are kept for historical/documentary value (they are what first motivated the GPS-cliff design
/// this file replaced), but `FallDetector` itself only uses `startedAt`/`endedAt`.
///
/// Ground truth from the rider, correcting an earlier GPS-cliff-based design that flagged most
/// normal set endings as falls:
///  - Set 1: a failed start — grabbed the handle, held cable speed briefly, then came off. Must flag.
///  - Set 8: a failed attempt to jump a kicker; the ride ended almost immediately. Must flag.
///  - Set 9: a failed kicker attempt after a lap and a landed jump. Must flag — and its GPS trace
///    is a steady, unremarkable cruise start to finish, so no GPS-shape rule could ever have
///    caught it; only its short duration does.
///  - Set 3: a failed surface 360, ending in what reads as a soft/gradual stop. Optional — fine to
///    flag or not.
///  - Sets 2, 4, 5, 6, 7, 10: normal sets that ran a full lap (some landing real tricks, e.g. two
///    kickers in set 10) and simply ended. Must NOT flag, even though several of them show the
///    exact same sharp GPS speed cliff as the real fails — that cliff is just what letting go of
///    the cable looks like, clean or not, which is why duration replaced it as the signal.
private struct LabeledSetFixture: Decodable {
    var index: Int
    var startedAt: Date
    var endedAt: Date
    var exitDetectorId: String
    var expectedFallDetected: Bool
    var locations: [LocationSample]

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
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
            let got = FallDetector.detectsFall(duration: set.duration)
            #expect(
                got == set.expectedFallDetected,
                "set \(set.index) (exit=\(set.exitDetectorId), duration=\(set.duration)s): expected"
                    + " fallDetected=\(set.expectedFallDetected), got \(got)"
            )
        }
    }

    @Test func flagsTheFailedStart() throws {
        let fixture = try Self.loadFixture()
        let set1 = try #require(fixture.sets.first { $0.index == 1 })
        #expect(FallDetector.detectsFall(duration: set1.duration))
    }

    /// The one case no GPS-shape rule could catch: a steady cruise the whole way, cut short.
    @Test func flagsTheFailedKickerWithNoGpsCliff() throws {
        let fixture = try Self.loadFixture()
        let set9 = try #require(fixture.sets.first { $0.index == 9 })
        #expect(FallDetector.detectsFall(duration: set9.duration))
    }

    /// Regression guard for the bug this file exists to fix: a normal, full-length set must not
    /// be flagged just because it ends in a sharp GPS speed cliff.
    @Test func doesNotFlagNormalFullLengthSets() throws {
        let fixture = try Self.loadFixture()
        for index in [2, 4, 5, 6, 7, 10] {
            let set = try #require(fixture.sets.first { $0.index == index })
            #expect(!FallDetector.detectsFall(duration: set.duration), "set \(index) must not flag")
        }
    }

    /// Whole-session sanity check: exactly 4 of the 10 labeled sets are cut-short (1, 3, 8, 9 —
    /// with 3 being the optional/lenient case), 6 ran a normal full length. Catches a threshold
    /// change that flips the overall balance even if individual per-set tests still pass.
    @Test func fourOfTenSetsAreFlaggedAsCutShort() throws {
        let fixture = try Self.loadFixture()
        let flaggedCount = fixture.sets.filter { FallDetector.detectsFall(duration: $0.duration) }.count
        #expect(flaggedCount == 4)
        #expect(fixture.sets.count == 10)
    }
}

private enum FixtureError: Error {
    case missing
}
