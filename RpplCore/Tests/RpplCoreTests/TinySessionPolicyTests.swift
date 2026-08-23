import Foundation
import Testing
@testable import RpplCore

@Suite("TinySessionPolicy")
struct TinySessionPolicyTests {
    @Test func offersDiscardWhenShortAndNoRides() {
        #expect(TinySessionPolicy.shouldOfferDiscard(duration: 0, rideCount: 0))
        #expect(TinySessionPolicy.shouldOfferDiscard(duration: 29.9, rideCount: 0))
    }

    @Test func keepsWhenAtOrOverThreshold() {
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 30, rideCount: 0))
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 90, rideCount: 0))
    }

    @Test func keepsWhenAnyRide() {
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 10, rideCount: 1))
        #expect(!TinySessionPolicy.shouldOfferDiscard(duration: 5, rideCount: 2))
    }

    @Test func thresholdIsThirtySeconds() {
        #expect(TinySessionPolicy.maxDurationSeconds == 30)
    }
}
