import Testing
import RpplCore

struct RpplTests {
    @Test func detectionCodesExposeRideInactiveUnsure() {
        #expect(DetectionCodes.riding == "riding")
        #expect(DetectionCodes.inactive == "inactive")
        #expect(DetectionCodes.unsure == "unsure")
        #expect(DetectionCodes.normalize("paused") == DetectionCodes.inactive)
        #expect(DetectionCodes.isConfident(DetectionCodes.riding))
        #expect(DetectionCodes.isConfident("paused"))
        #expect(!DetectionCodes.isConfident(DetectionCodes.unsure))
    }
}
