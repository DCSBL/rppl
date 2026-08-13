import Testing
import RpplCore

struct RpplTests {
    @Test func labelCycleMatchesCore() {
        #expect(LabelCodes.next(after: LabelCodes.waiting) == LabelCodes.riding)
    }
}
