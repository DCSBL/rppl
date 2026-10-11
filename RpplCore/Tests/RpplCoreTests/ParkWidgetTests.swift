import Foundation
import Testing
@testable import RpplCore

struct ParkWidgetTests {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    private func date(_ iso: String, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute)
        )!
    }

    /// Open Monday-Friday 14:00-20:00 in October, closed at the weekend.
    private var weekdaysOnly: ParkOpening {
        ParkOpening(rules: [
            ParkOpeningRule(months: [10], days: ["weekdays"], open: "14:00", close: "20:00"),
        ])
    }

    @Test func openNowShowsUntil() {
        // 2026-10-12 is a Monday.
        let state = ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-12", hour: 15), timeZone: amsterdam)
        guard case .openUntil(let window) = state else {
            Issue.record("got \(state)")
            return
        }
        #expect(window.endMinute == 20 * 60)
    }

    @Test func opensLaterTodayShowsFromTo() {
        let state = ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-12", hour: 9), timeZone: amsterdam)
        guard case .opensToday(let window) = state else {
            Issue.record("got \(state)")
            return
        }
        #expect(window.startMinute == 14 * 60)
        #expect(window.endMinute == 20 * 60)
    }

    @Test func afterClosingTomorrowOpenOrClosed() {
        // Monday evening: Tuesday is open. Friday evening: the weekend is closed.
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-12", hour: 21), timeZone: amsterdam) == .opensTomorrow)
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-16", hour: 21), timeZone: amsterdam) == .closed)
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-17", hour: 12), timeZone: amsterdam) == .closed)
    }

    @Test func noOpeningTimesIsUnknown() {
        #expect(ParkWidgetState.make(for: nil, at: date("2026-10-12", hour: 12), timeZone: amsterdam) == .unknown)
    }

    @Test func changeDatesCoverWindowEdgesAndMidnights() {
        let now = date("2026-10-12", hour: 15)
        let dates = ParkWidgetTimeline.changeDates(for: weekdaysOnly, after: now, timeZone: amsterdam)
        #expect(dates == [
            date("2026-10-12", hour: 20),
            date("2026-10-13", hour: 0),
            date("2026-10-13", hour: 14),
            date("2026-10-13", hour: 20),
            date("2026-10-14", hour: 0),
        ])
    }

    @Test func changeDatesForUnknownParkAreMidnightsOnly() {
        let now = date("2026-10-12", hour: 15)
        let dates = ParkWidgetTimeline.changeDates(for: nil, after: now, timeZone: amsterdam)
        #expect(dates == [date("2026-10-13", hour: 0), date("2026-10-14", hour: 0)])
    }
}
