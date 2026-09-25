import Foundation
import Testing
@testable import RpplCore

@Suite("FallDetector")
struct FallDetectorTests {
    @Test func defaultThresholdMatchesCalibratedValue() {
        #expect(FallDetectionThresholds.default.maxCutShortDuration == 150)
    }

    @Test func veryShortDurationFlags() {
        #expect(FallDetector.detectsFall(duration: 9))
    }

    @Test func justBelowThresholdFlags() {
        #expect(FallDetector.detectsFall(duration: 149.9))
    }

    @Test func exactlyAtThresholdDoesNotFlag() {
        #expect(!FallDetector.detectsFall(duration: 150))
    }

    @Test func justAboveThresholdDoesNotFlag() {
        #expect(!FallDetector.detectsFall(duration: 150.1))
    }

    @Test func veryLongDurationDoesNotFlag() {
        #expect(!FallDetector.detectsFall(duration: 303))
    }

    @Test func zeroDurationFlags() {
        #expect(FallDetector.detectsFall(duration: 0))
    }

    @Test func customThresholdCanTightenTheCutoff() {
        // A set that qualifies under the default 150 s cutoff should not once the cutoff is
        // lowered past it.
        #expect(FallDetector.detectsFall(duration: 90))
        let strict = FallDetectionThresholds(maxCutShortDuration: 60)
        #expect(!FallDetector.detectsFall(duration: 90, thresholds: strict))
    }

    @Test func customThresholdCanLoosenTheCutoff() {
        // A set that does not qualify under the default 150 s cutoff should once the cutoff is
        // raised past it.
        #expect(!FallDetector.detectsFall(duration: 200))
        let loose = FallDetectionThresholds(maxCutShortDuration: 250)
        #expect(FallDetector.detectsFall(duration: 200, thresholds: loose))
    }
}
