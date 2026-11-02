import Foundation
import Testing
@testable import RpplCore

@Suite("DockWaitStats")
struct DockWaitStatsTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func set(_ index: Int, from: TimeInterval, to: TimeInterval) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: t0.addingTimeInterval(from),
            endedAt: t0.addingTimeInterval(to),
            duration: to - from,
            distanceMeters: 0
        )
    }

    @Test func gapsRunFromSetEndToNextStart() {
        let sets = [set(1, from: 0, to: 100), set(2, from: 400, to: 500), set(3, from: 600, to: 700)]
        #expect(DockWaitStats.gaps(sets: sets) == [300, 100])
    }

    @Test func summaryNeedsTwoSets() {
        #expect(DockWaitStats.summary(sets: []) == nil)
        #expect(DockWaitStats.summary(sets: [set(1, from: 0, to: 10)]) == nil)
    }

    @Test func summaryInterpolatesQuartiles() throws {
        let sets = [
            set(1, from: 0, to: 10), set(2, from: 110, to: 120), set(3, from: 420, to: 430),
            set(4, from: 930, to: 940), set(5, from: 1_140, to: 1_150),
        ]
        let summary = try #require(DockWaitStats.summary(sets: sets))
        // Gaps 100, 300, 500, 200 → sorted 100, 200, 300, 500.
        #expect(summary.count == 4)
        #expect(summary.median == 250)
        #expect(summary.lowerQuartile == 175)
        #expect(summary.upperQuartile == 350)
    }

    @Test func overlappingSetsClampToZero() {
        let sets = [set(1, from: 0, to: 100), set(2, from: 90, to: 200)]
        #expect(DockWaitStats.gaps(sets: sets) == [0])
    }
}
