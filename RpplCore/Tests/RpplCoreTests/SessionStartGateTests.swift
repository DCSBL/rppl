import Foundation
import Testing
@testable import RpplCore

@Suite("SessionStartGate")
struct SessionStartGateTests {
    @Test func idleStarts() {
        #expect(
            SessionStartGate.decide(isRunning: false, isStarting: false, isStopping: false, isFinalizing: false)
                == .start
        )
    }

    @Test func anyBusyStateIgnores() {
        #expect(SessionStartGate.decide(isRunning: true, isStarting: false, isStopping: false, isFinalizing: false) == .ignoreBusy)
        #expect(SessionStartGate.decide(isRunning: false, isStarting: true, isStopping: false, isFinalizing: false) == .ignoreBusy)
        #expect(SessionStartGate.decide(isRunning: false, isStarting: false, isStopping: true, isFinalizing: false) == .ignoreBusy)
        // Summary on screen while the previous session still saves.
        #expect(SessionStartGate.decide(isRunning: true, isStarting: false, isStopping: true, isFinalizing: true) == .ignoreBusy)
        #expect(SessionStartGate.decide(isRunning: false, isStarting: false, isStopping: false, isFinalizing: true) == .ignoreBusy)
    }
}
