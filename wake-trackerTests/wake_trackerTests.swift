import Testing
import WakeTrackerCore

struct wake_trackerTests {
    @Test func detectionCodesExposeRidePauseUnsure() {
        #expect(DetectionCodes.riding == "riding")
        #expect(DetectionCodes.paused == "paused")
        #expect(DetectionCodes.unsure == "unsure")
        #expect(DetectionCodes.isConfident(DetectionCodes.riding))
        #expect(!DetectionCodes.isConfident(DetectionCodes.unsure))
    }
}
