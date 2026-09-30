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
        let busy: [(Bool, Bool, Bool, Bool)] = [
            (true, false, false, false),
            (false, true, false, false),
            (false, false, true, false),
            (false, false, false, true),
            (true, false, true, true),
        ]
        for (running, starting, stopping, finalizing) in busy {
            #expect(
                SessionStartGate.decide(
                    isRunning: running,
                    isStarting: starting,
                    isStopping: stopping,
                    isFinalizing: finalizing
                ) == .ignoreBusy
            )
        }
    }
}
