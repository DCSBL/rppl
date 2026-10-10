import Foundation
import Testing
@testable import RpplCore

@Suite("PendingStop")
struct PendingStopTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let tap = Date(timeIntervalSince1970: 5_000)
    private let now = Date(timeIntervalSince1970: 5_200)

    @Test func withoutPendingStopTheSessionEndsNow() {
        #expect(PendingStop.endDate(requestedAt: nil, sessionStart: start, now: now) == now)
    }

    @Test func confirmedStopEndsAtTheFirstTap() {
        #expect(PendingStop.endDate(requestedAt: tap, sessionStart: start, now: now) == tap)
    }

    @Test func neverEndsBeforeTheSessionStarted() {
        let early = Date(timeIntervalSince1970: 10)
        #expect(PendingStop.endDate(requestedAt: early, sessionStart: start, now: now) == start)
    }

    @Test func neverEndsInTheFuture() {
        let future = now.addingTimeInterval(60)
        #expect(PendingStop.endDate(requestedAt: future, sessionStart: start, now: now) == now)
    }

    @Test func firstReminderComesOneIntervalAfterTheTap() {
        #expect(!PendingStop.reminderDue(requestedAt: tap, lastReminderAt: nil, now: tap.addingTimeInterval(59)))
        #expect(PendingStop.reminderDue(requestedAt: tap, lastReminderAt: nil, now: tap.addingTimeInterval(60)))
    }

    @Test func laterRemindersCountFromThePreviousOne() {
        let last = tap.addingTimeInterval(60)
        #expect(!PendingStop.reminderDue(requestedAt: tap, lastReminderAt: last, now: last.addingTimeInterval(30)))
        #expect(PendingStop.reminderDue(requestedAt: tap, lastReminderAt: last, now: last.addingTimeInterval(60)))
    }
}
