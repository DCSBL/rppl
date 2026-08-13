import Testing
import RpplCore

struct RpplTests {
    @Test func labelCodesAreOpaqueStrings() {
        #expect(LabelCodes.waiting == "waiting")
        #expect(LabelCodes.riding == "riding")
    }
}
