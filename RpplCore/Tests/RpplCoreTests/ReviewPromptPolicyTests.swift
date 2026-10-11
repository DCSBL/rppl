import Foundation
import Testing
@testable import RpplCore

@Suite("ReviewPromptPolicy")
struct ReviewPromptPolicyTests {
    private func set(_ index: Int, laps: Int) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            duration: 60,
            distanceMeters: 500,
            lapCount: laps
        )
    }

    private func stats(duration: TimeInterval, laps: [Int]) -> SessionStats {
        SessionStats(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: duration),
            totalDuration: duration,
            totalDistanceMeters: 1000,
            activeEnergyKilocalories: nil,
            setCount: laps.count,
            ridingDuration: 600,
            inactiveDuration: 0,
            ridingInactiveRatio: 1,
            sets: laps.enumerated().map { set($0.offset, laps: $0.element) }
        )
    }

    private func manifest(manual: Bool = false) -> SessionManifest {
        var manifest = SessionManifest(testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "w", systemVersion: "26")
        if manual { manifest.manual = ManualEntry() }
        return manifest
    }

    @Test func goodSessionNeedsHalfHourAndThreeSetsWithLap() {
        let m = manifest()
        #expect(ReviewPromptState.isGoodSession(manifest: m, stats: stats(duration: 1800, laps: [1, 2, 1])))
        #expect(!ReviewPromptState.isGoodSession(manifest: m, stats: stats(duration: 1799, laps: [1, 1, 1])))
        #expect(!ReviewPromptState.isGoodSession(manifest: m, stats: stats(duration: 3600, laps: [1, 1])))
        #expect(!ReviewPromptState.isGoodSession(manifest: m, stats: stats(duration: 3600, laps: [1, 0, 1])))
        #expect(ReviewPromptState.isGoodSession(manifest: m, stats: stats(duration: 3600, laps: [1, 0, 1, 3])))
    }

    @Test func manualSessionIsNeverGood() {
        #expect(!ReviewPromptState.isGoodSession(
            manifest: manifest(manual: true),
            stats: stats(duration: 3600, laps: [1, 1, 1])
        ))
    }

    @Test func scheduleIsThreeTenThenEveryTen() {
        let expected = [0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 20, 20, 20]
        #expect((0..<expected.count).map { ReviewPromptState.milestone(for: $0) } == expected)
        #expect(ReviewPromptState.milestone(for: 25) == 20)
        #expect(ReviewPromptState.milestone(for: 30) == 30)
    }

    @Test func armsAtThreeTenAndTwentyOnly() {
        var state = ReviewPromptState()
        var armedAt: [Int] = []
        for n in 1...31 where state.record(goodSessionIDs: ["s\(n)"]) {
            armedAt.append(n)
            let armed1 = state.consumePending()
            #expect(armed1)
        }
        #expect(armedAt == [3, 10, 20, 30])
    }

    @Test func duplicateIDsDoNotCount() {
        var state = ReviewPromptState()
        let armed1 = state.record(goodSessionIDs: ["a", "b", "a", "b"])
        #expect(!armed1)
        let armed2 = state.record(goodSessionIDs: ["a", "b"])
        #expect(!armed2)
        let armed3 = state.record(goodSessionIDs: ["c"])
        #expect(armed3)
    }

    @Test func historicJumpArmsOnce() {
        var state = ReviewPromptState()
        let armed1 = state.record(goodSessionIDs: (1...12).map { "s\($0)" })
        #expect(armed1)
        #expect(state.promptedMilestone == 10)
        let armed2 = state.consumePending()
        #expect(armed2)
        let armed3 = state.consumePending()
        #expect(!armed3)
        let armed4 = state.record(goodSessionIDs: ["s13"])
        #expect(!armed4)
    }

    @Test func pendingSurvivesUntilConsumed() {
        var state = ReviewPromptState()
        state.record(goodSessionIDs: ["a", "b", "c"])
        let armed1 = state.record(goodSessionIDs: ["d"])
        #expect(!armed1)
        #expect(state.pending)
        let armed2 = state.consumePending()
        #expect(armed2)
    }

    @Test func codableRoundTrip() throws {
        var state = ReviewPromptState()
        state.record(goodSessionIDs: ["a", "b", "c"])
        let decoded = try JSONDecoder().decode(ReviewPromptState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
