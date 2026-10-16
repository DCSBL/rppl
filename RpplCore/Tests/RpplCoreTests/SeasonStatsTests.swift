import Foundation
import Testing
@testable import RpplCore

struct SeasonStatsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func totalsAndOrder() {
        let stats = SeasonStats(
            sessions: [
                SeasonSession(date: day(6, 2), distanceMeters: 2000, duration: 3600, ridingDuration: 1800, sets: 3, laps: 10, topSpeedKmh: 30),
                SeasonSession(date: day(5, 1), distanceMeters: 1000, duration: 1800, ridingDuration: 600, sets: nil, laps: nil, topSpeedKmh: 35),
            ],
            calendar: calendar
        )
        #expect(stats.sessionCount == 2)
        #expect(stats.totalDistanceMeters == 3000)
        #expect(stats.totalDuration == 5400)
        #expect(stats.totalRidingDuration == 2400)
        #expect(stats.totalSets == 3)
        #expect(stats.totalLaps == 10)
        #expect(stats.topSpeedKmh == 35)
        #expect(stats.distanceMeters.map(\.value) == [1000, 2000])
    }

    @Test func seriesSkipEmptySessions() {
        let stats = SeasonStats(
            sessions: [
                SeasonSession(date: day(5, 1), distanceMeters: 1000, laps: 0, kilocalories: nil),
                SeasonSession(date: day(5, 2), distanceMeters: 0, laps: 4, kilocalories: 300),
            ],
            calendar: calendar
        )
        #expect(stats.distanceMeters.count == 1)
        #expect(stats.laps.map(\.value) == [4])
        #expect(stats.kilocalories.map(\.value) == [300])
    }

    @Test func typicalSpeedIsModeTiesGoFaster() {
        func stats(_ speeds: [Double?]) -> SeasonStats {
            SeasonStats(
                sessions: speeds.enumerated().map { SeasonSession(date: day(5, $0.offset + 1), typicalSpeedKmh: $0.element) },
                calendar: calendar
            )
        }
        #expect(stats([27, 27.5, 27, nil]).typicalSpeedKmh == 27)
        #expect(stats([27, 27.5]).typicalSpeedKmh == 27.5)
        #expect(stats([nil]).typicalSpeedKmh == nil)
    }

    @Test func dailyTemperatureAverages() {
        let stats = SeasonStats(
            sessions: [
                SeasonSession(date: day(5, 1), airCelsius: 10, waterCelsius: 12),
                SeasonSession(date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 18))!, airCelsius: 20),
                SeasonSession(date: day(5, 9), airCelsius: 16),
                SeasonSession(date: day(6, 3)),
                SeasonSession(date: day(7, 3), waterCelsius: 18),
            ],
            calendar: calendar
        )
        #expect(stats.days.count == 3)
        #expect(stats.days[0].airCelsius == 15)
        #expect(stats.days[0].waterCelsius == 12)
        #expect(stats.days[1].airCelsius == 16)
        #expect(stats.days[1].waterCelsius == nil)
        #expect(stats.days[2].airCelsius == nil)
        #expect(stats.days[2].waterCelsius == 18)
    }

    @Test func chartsNeedFiveSessions() {
        let four = SeasonStats(sessions: (1...4).map { SeasonSession(date: day(5, $0)) }, calendar: calendar)
        let five = SeasonStats(sessions: (1...5).map { SeasonSession(date: day(5, $0)) }, calendar: calendar)
        #expect(!four.showsCharts)
        #expect(five.showsCharts)
    }

    @Test func totalsCycleAndWrap() {
        #expect(SpeedTotal.max.cycled() == .typical)
        #expect(SpeedTotal.typical.cycled() == .max)
        #expect(DistanceTotal.distance.cycled() == .duration)
        #expect(DistanceTotal.riding.cycled() == .distance)
        #expect(DistanceTotal(rawValue: "gone") == nil)
    }
}
