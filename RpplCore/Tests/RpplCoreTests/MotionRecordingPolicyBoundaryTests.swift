import Foundation
import Testing
@testable import RpplCore

/// `decide` is what deletes recorded motion when the Watch runs out of space, so the exact
/// thresholds and the order in which the reasons win matter.
@Suite("MotionRecordingPolicy boundaries")
struct MotionRecordingPolicyBoundaryTests {
    private let plenty: Int64 = 4 * 1024 * 1024 * 1024
    private typealias Policy = MotionRecordingPolicy

    @Test func freeSpaceExactlyAtTheStopThresholdStillRecords() {
        #expect(Policy.decide(elapsed: 60, motionBytes: 0, freeBytes: Policy.stopBelowFreeBytes) == .record)
    }

    @Test func freeSpaceExactlyAtTheDropThresholdStopsButKeepsWhatIsRecorded() {
        let decision = Policy.decide(elapsed: 60, motionBytes: 0, freeBytes: Policy.dropBelowFreeBytes)
        #expect(decision == .stop(reason: Policy.Reason.lowStorage))
    }

    @Test func justUnderTheBudgetsStillRecords() {
        let decision = Policy.decide(
            elapsed: Policy.maxSessionDuration - 1,
            motionBytes: Policy.maxCompressedBytes - 1,
            freeBytes: plenty
        )
        #expect(decision == .record)
    }

    @Test func criticalStorageBeatsEveryOtherReason() {
        let decision = Policy.decide(
            elapsed: Policy.maxSessionDuration * 2,
            motionBytes: Policy.maxCompressedBytes * 2,
            freeBytes: Policy.dropBelowFreeBytes - 1
        )
        #expect(decision == .dropRecorded(reason: Policy.Reason.storageCritical))
    }

    @Test func lowStorageBeatsTheFileBudgetAndTheDurationCap() {
        let decision = Policy.decide(
            elapsed: Policy.maxSessionDuration * 2,
            motionBytes: Policy.maxCompressedBytes * 2,
            freeBytes: Policy.stopBelowFreeBytes - 1
        )
        #expect(decision == .stop(reason: Policy.Reason.lowStorage))
    }

    @Test func fileBudgetBeatsTheDurationCap() {
        let decision = Policy.decide(
            elapsed: Policy.maxSessionDuration * 2,
            motionBytes: Policy.maxCompressedBytes,
            freeBytes: plenty
        )
        #expect(decision == .stop(reason: Policy.Reason.fileBudget))
    }

    @Test func unknownFreeSpaceNeverStopsMotionByItselfButTheBudgetsStillApply() {
        #expect(Policy.decide(elapsed: 60, motionBytes: 0, freeBytes: nil) == .record)
        #expect(
            Policy.decide(elapsed: Policy.maxSessionDuration, motionBytes: 0, freeBytes: nil)
                == .stop(reason: Policy.Reason.longSession)
        )
    }

    @Test func onlyDroppingDeletesRecordedMotion() {
        #expect(Policy.Decision.record.reason == nil)
        #expect(Policy.Decision.stop(reason: "a").reason == "a")
        #expect(Policy.Decision.dropRecorded(reason: "b").reason == "b")
        #expect(Policy.Decision.stop(reason: "a") != Policy.Decision.dropRecorded(reason: "a"))
    }
}
