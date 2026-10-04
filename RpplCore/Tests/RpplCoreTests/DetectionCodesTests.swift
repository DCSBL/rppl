import Foundation
import Testing
@testable import RpplCore

@Suite("DetectionCodes")
struct DetectionCodesTests {
    @Test func onlyRidingAndInactiveAreConfident() {
        #expect(DetectionCodes.isConfident(DetectionCodes.riding))
        #expect(DetectionCodes.isConfident(DetectionCodes.inactive))
        #expect(!DetectionCodes.isConfident(DetectionCodes.unsure))
    }

    @Test func unknownCodesAreNotConfidentAndNotRewritten() {
        // Codes are opaque strings: nothing maps an unknown code (even an old name) to a known one.
        #expect(!DetectionCodes.isConfident("paused"))
        #expect(!DetectionCodes.isConfident("swimming"))
    }
}
