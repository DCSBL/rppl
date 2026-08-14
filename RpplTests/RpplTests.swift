import Testing
import RpplCore

struct RpplTests {
    @Test func detectionCodesExposeRidePauseUnsure() {
        #expect(DetectionCodes.riding == "riding")
        #expect(DetectionCodes.paused == "paused")
        #expect(DetectionCodes.unsure == "unsure")
        #expect(DetectionCodes.isConfident(DetectionCodes.riding))
        #expect(!DetectionCodes.isConfident(DetectionCodes.unsure))
    }
}
