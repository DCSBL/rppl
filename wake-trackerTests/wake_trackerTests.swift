import Testing
import WakeTrackerCore

struct wake_trackerTests {
    @Test func labelCycleMatchesCore() {
        #expect(LabelCodes.next(after: LabelCodes.waiting) == LabelCodes.riding)
    }
}
