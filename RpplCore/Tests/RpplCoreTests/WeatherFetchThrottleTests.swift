import Foundation
import Testing

@testable import RpplCore

struct WeatherFetchThrottleTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstFetchAllowed() {
        let throttle = WeatherFetchThrottle()
        #expect(throttle.canFetch(latitude: 52.0, longitude: 5.0, now: t0))
    }

    @Test func blocksWithinHourAllowsAfter() {
        var throttle = WeatherFetchThrottle()
        throttle.recordAttempt(latitude: 52.0, longitude: 5.0, now: t0)
        #expect(!throttle.canFetch(latitude: 52.0, longitude: 5.0, now: t0.addingTimeInterval(59 * 60)))
        #expect(throttle.canFetch(latitude: 52.0, longitude: 5.0, now: t0.addingTimeInterval(60 * 60)))
    }

    @Test func nearbyFixSharesSlot() {
        var throttle = WeatherFetchThrottle()
        throttle.recordAttempt(latitude: 52.001, longitude: 5.001, now: t0)
        #expect(!throttle.canFetch(latitude: 52.004, longitude: 5.003, now: t0.addingTimeInterval(60)))
    }

    @Test func farLocationIndependent() {
        var throttle = WeatherFetchThrottle()
        throttle.recordAttempt(latitude: 52.0, longitude: 5.0, now: t0)
        #expect(throttle.canFetch(latitude: 53.0, longitude: 6.0, now: t0.addingTimeInterval(60)))
    }

    @Test func clockGoingBackwardsAllowsFetch() {
        var throttle = WeatherFetchThrottle()
        throttle.recordAttempt(latitude: 52.0, longitude: 5.0, now: t0)
        #expect(throttle.canFetch(latitude: 52.0, longitude: 5.0, now: t0.addingTimeInterval(-10)))
    }
}
