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
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-12", hour: 21), timeZone: amsterdam) == .opensTomorrow(startMinute: 14 * 60))
    }

    @Test func closedWithKnownNextOpeningCountsDays() {
        // Friday evening: Saturday and Sunday closed, Monday open = in 3 days. Saturday noon = in 2 days.
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-16", hour: 21), timeZone: amsterdam) == .opensInDays(3))
        #expect(ParkWidgetState.make(for: weekdaysOnly, at: date("2026-10-17", hour: 12), timeZone: amsterdam) == .opensInDays(2))
    }

    @Test func farNextOpeningReadsClosed() {
        // Only September is scheduled: beyond 3 days the widget just says closed.
        let septemberOnly = ParkOpening(rules: [ParkOpeningRule(months: [9], days: ["daily"], open: "10:00", close: "18:00")])
        #expect(ParkWidgetState.make(for: septemberOnly, at: date("2026-10-12", hour: 12), timeZone: amsterdam) == .closed)
    }

    @Test func traceKeepsAspectAndLoopsFullSizeCables() throws {
        let park = Park(
            id: "t", name: "T", location: ParkCoordinate(lat: 52, lon: 5),
            cables: [ParkCable(direction: .clockwise, points: [
                ParkCablePoint(lat: 52.0, lon: 5.0),
                ParkCablePoint(lat: 52.0, lon: 5.001),
                ParkCablePoint(lat: 52.001, lon: 5.001),
            ])]
        )
        let trace = try #require(ParkTrace.make(for: park))
        let line = try #require(trace.lines.first)
        #expect(line.isLoop)
        #expect(line.points.count == 3)
        // North is up: the northern point has the smaller y.
        #expect(line.points[2].y < line.points[0].y)
        for point in line.points {
            #expect((0...1).contains(point.x) && (0...1).contains(point.y))
        }
    }

    @Test func traceKeepsEveryCableOnOneScale() throws {
        let park = Park(
            id: "t", name: "T", location: ParkCoordinate(lat: 52, lon: 5),
            cables: [
                ParkCable(direction: .clockwise, points: [
                    ParkCablePoint(lat: 52.000, lon: 5.000),
                    ParkCablePoint(lat: 52.002, lon: 5.000),
                ]),
                ParkCable(direction: .twoPointZero, points: [
                    ParkCablePoint(lat: 52.000, lon: 5.001),
                    ParkCablePoint(lat: 52.001, lon: 5.001),
                ]),
                ParkCable(points: [ParkCablePoint(lat: 52, lon: 5)]),
            ]
        )
        let trace = try #require(ParkTrace.make(for: park))
        #expect(trace.lines.count == 2)
        let lengths = trace.lines.map { abs($0.points[1].y - $0.points[0].y) }
        #expect(abs(lengths[0] - 2 * lengths[1]) < 1e-9)
        #expect(trace.lines[0].isLoop && !trace.lines[1].isLoop)
    }

    @Test func traceNeedsTwoPoints() {
        let park = Park(id: "t", name: "T", location: ParkCoordinate(lat: 52, lon: 5), cables: [ParkCable(points: [ParkCablePoint(lat: 52, lon: 5)])])
        #expect(ParkTrace.make(for: park) == nil)
    }

    @Test func deepLinkRoundTrips() throws {
        let url = try #require(ParkDeepLink.url(forParkID: "project7-rotterdam"))
        #expect(url.absoluteString == "rppl://park/project7-rotterdam")
        #expect(ParkDeepLink.parkID(from: url) == "project7-rotterdam")
        #expect(ParkDeepLink.parkID(from: URL(string: "https://park/x")!) == nil)
    }

    @Test func favoritesLinkRoundTrips() throws {
        let url = try #require(ParkDeepLink.favoritesURL)
        #expect(url.absoluteString == "rppl://parks/favorites")
        #expect(ParkDeepLink.isFavorites(url))
        #expect(ParkDeepLink.parkID(from: url) == nil)
        #expect(!ParkDeepLink.isFavorites(try #require(ParkDeepLink.url(forParkID: "favorites"))))
        #expect(!ParkDeepLink.isFavorites(URL(string: "rppl://parks/other")!))
    }

    @Test func timeZoneNoteOnlyWhenTheClockDiffers() {
        let park = Park(id: "t", name: "T", location: ParkCoordinate(lat: 52, lon: 5), timezone: "Europe/Amsterdam")
        let moment = date("2026-10-12", hour: 12)
        let london = TimeZone(identifier: "Europe/London")!
        let brussels = TimeZone(identifier: "Europe/Brussels")!
        #expect(ParkTimeZoneNote.label(for: park, deviceZone: london, at: moment) == "Europe/Amsterdam")
        #expect(ParkTimeZoneNote.label(for: park, deviceZone: amsterdam, at: moment) == nil)
        // Same clock, other name: nothing to explain.
        #expect(ParkTimeZoneNote.label(for: park, deviceZone: brussels, at: moment) == nil)
    }

    @Test func noOpeningTimesIsUnknown() {
        #expect(ParkWidgetState.make(for: nil, at: date("2026-10-12", hour: 12), timeZone: amsterdam) == .unknown)
    }

    @Test func changeDatesCoverWindowEdgesAndMidnights() {
        let now = date("2026-10-12", hour: 15)
        let dates = ParkWidgetTimeline.changeDates(for: weekdaysOnly, after: now, timeZone: amsterdam, days: 2)
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
        let dates = ParkWidgetTimeline.changeDates(for: nil, after: now, timeZone: amsterdam, days: 2)
        #expect(dates == [date("2026-10-13", hour: 0), date("2026-10-14", hour: 0)])
    }
}
