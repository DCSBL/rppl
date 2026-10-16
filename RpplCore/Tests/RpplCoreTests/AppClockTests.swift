import Foundation
import Testing
@testable import RpplCore

@Suite(.serialized)
struct AppClockTests {
    @Test func overrideFreezesNowAndParkStatusFollowsIt() {
        defer { AppClock.override = nil }
        let frozen = Date(timeIntervalSince1970: 1_786_789_800)
        AppClock.override = frozen
        #expect(AppClock.now == frozen)
        AppClock.override = nil
        #expect(abs(AppClock.now.timeIntervalSinceNow) < 5)
    }
}
