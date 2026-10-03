import Testing
@testable import RpplCore

@Suite("WorkoutSessionLossPolicy")
struct WorkoutSessionLossPolicyTests {
    typealias Policy = WorkoutSessionLossPolicy

    @Test func endedOrStoppedWhileRecordingIsLoss() {
        #expect(Policy.isUnexpectedLoss(isRunning: true, isStopping: false, toStateRaw: Policy.StateRaw.ended))
        #expect(Policy.isUnexpectedLoss(isRunning: true, isStopping: false, toStateRaw: Policy.StateRaw.stopped))
    }

    @Test func ourOwnStopIsNotLoss() {
        #expect(!Policy.isUnexpectedLoss(isRunning: true, isStopping: true, toStateRaw: Policy.StateRaw.stopped))
        #expect(!Policy.isUnexpectedLoss(isRunning: false, isStopping: false, toStateRaw: Policy.StateRaw.ended))
    }

    @Test func otherSessionsAndStatesAreIgnored() {
        #expect(!Policy.isUnexpectedLoss(
            isRunning: true, isStopping: false, isCurrentSession: false, toStateRaw: Policy.StateRaw.ended
        ))
        // running (2) and paused (4) are not losses
        #expect(!Policy.isUnexpectedLoss(isRunning: true, isStopping: false, toStateRaw: 2))
        #expect(!Policy.isUnexpectedLoss(isRunning: true, isStopping: false, toStateRaw: 4))
    }

    @Test func failureRespectsSameGuards() {
        #expect(Policy.isUnexpectedFailure(isRunning: true, isStopping: false))
        #expect(!Policy.isUnexpectedFailure(isRunning: true, isStopping: true))
        #expect(!Policy.isUnexpectedFailure(isRunning: true, isStopping: false, isCurrentSession: false))
    }
}
