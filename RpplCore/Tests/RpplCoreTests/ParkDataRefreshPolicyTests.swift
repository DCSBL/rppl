import Foundation
import Testing
@testable import RpplCore

struct ParkDataRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(success: Bool, secondsAgo: TimeInterval?) -> ParkDataUpdateState {
        var state = ParkDataUpdateState()
        state.lastRealAttemptSucceeded = success
        state.lastSuccess = secondsAgo.map { now.addingTimeInterval(-$0) }
        return state
    }

    @Test func fakesOnlyWithinAMinuteOfARealSuccess() {
        #expect(ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: true, secondsAgo: 10), now: now))
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: true, secondsAgo: 60), now: now))
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: true, secondsAgo: 3600), now: now))
    }

    @Test func neverFakesAfterAFailureOrWithoutHistory() {
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: false, secondsAgo: 5), now: now))
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: true, secondsAgo: nil), now: now))
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: ParkDataUpdateState(), now: now))
    }

    @Test func clockMovingBackwardsDoesNotFake() {
        #expect(!ParkDataRefreshPolicy.shouldFakeManualRefresh(state: state(success: true, secondsAgo: -30), now: now))
    }

    @Test func dailyCheckDueAfter24HoursOrWithoutSuccess() {
        #expect(ParkDataRefreshPolicy.isDailyCheckDue(state: ParkDataUpdateState(), now: now))
        #expect(!ParkDataRefreshPolicy.isDailyCheckDue(state: state(success: true, secondsAgo: 23 * 3600), now: now))
        #expect(ParkDataRefreshPolicy.isDailyCheckDue(state: state(success: true, secondsAgo: 24 * 3600), now: now))
        #expect(ParkDataRefreshPolicy.isDailyCheckDue(state: state(success: true, secondsAgo: -100), now: now))
    }

    @Test func backgroundCheckUsesAShorterMinimumAge() {
        let age = ParkDataRefreshPolicy.backgroundMinimumAge
        #expect(!ParkDataRefreshPolicy.isDailyCheckDue(state: state(success: true, secondsAgo: 19 * 3600), now: now, minimumAge: age))
        #expect(ParkDataRefreshPolicy.isDailyCheckDue(state: state(success: true, secondsAgo: 21 * 3600), now: now, minimumAge: age))
    }

    @Test func nextDailyCheckLandsOnTheInstallationOffset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let next = ParkDataRefreshPolicy.nextDailyCheck(after: start, offsetFraction: 0.75, calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour], from: next)
        #expect(parts.day == 22 && parts.hour == 18)

        let tomorrow = ParkDataRefreshPolicy.nextDailyCheck(after: start, offsetFraction: 0.25, calendar: calendar)
        let tParts = calendar.dateComponents([.day, .hour], from: tomorrow)
        #expect(tParts.day == 23 && tParts.hour == 6)
    }

    @Test func nextDailyCheckKeepsAMinimumGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 17, minute: 30))!
        // 18:00 is only 30 minutes away, under the one-hour gap: move to tomorrow.
        let next = ParkDataRefreshPolicy.nextDailyCheck(after: start, offsetFraction: 0.75, calendar: calendar)
        #expect(calendar.component(.day, from: next) == 23)
    }

    @Test func ageBuckets() {
        func age(_ seconds: TimeInterval) -> ParkDataAge { ParkDataAge(from: now.addingTimeInterval(-seconds), to: now) }
        #expect(age(0) == .lessThanMinute)
        #expect(age(59) == .lessThanMinute)
        #expect(age(60) == .minutes(1))
        #expect(age(59 * 60) == .minutes(59))
        #expect(age(3600) == .hours(1))
        #expect(age(21 * 3600) == .hours(21))
        #expect(age(48 * 3600) == .days(2))
        #expect(ParkDataAge(from: now.addingTimeInterval(100), to: now) == .lessThanMinute)
    }
}
