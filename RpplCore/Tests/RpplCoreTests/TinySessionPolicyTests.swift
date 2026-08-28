import Foundation
import Testing
@testable import RpplCore

@Suite("TinySessionPolicy")
struct TinySessionPolicyTests {
    @Test func offersDiscardWhenShortAndNoRides() {
        #expect(TinySessionPolicy.shouldOfferDiscard(duration: 0, setCount: 0))
        #expect(TinySessionPolicy.shouldOfferDiscard(duration: 29.9, setCount: 0))
    }

    @Test func keepsWhenAtOrOverThreshold() {
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 30, setCount: 0))
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 90, setCount: 0))
    }

    @Test func keepsWhenAnyRide() {
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 10, setCount: 1))
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 5, setCount: 2))
    }

    @Test func thresholdIsThirtySeconds() {
        #expect(TinySessionPolicy.maxDurationSeconds == 30)
    }
}
