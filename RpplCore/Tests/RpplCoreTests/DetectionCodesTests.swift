import Foundation
import Testing
@testable import RpplCore

@Suite("DetectionCodes")
struct DetectionCodesTests {
    @Test func normalizeMapsLegacyPaused() {
        #expect(DetectionCodes.inactive == "inactive")
        #expect(DetectionCodes.normalize("paused") == DetectionCodes.inactive)
        #expect(DetectionCodes.normalize(DetectionCodes.riding) == DetectionCodes.riding)
    }
}
