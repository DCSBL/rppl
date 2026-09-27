import Foundation
import Testing
@testable import RpplCore

struct RainForecastPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func notExpectedWhenNoHourClearsTheThreshold() {
        let hourly = [
            HourlyRainChance(date: now.addingTimeInterval(3600), chance: 0.1),
            HourlyRainChance(date: now.addingTimeInterval(7200), chance: 0.3),
        ]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) == .notExpected)
    }

    @Test func notExpectedWhenTheOnlyHitIsBeyondTheLookahead() {
        let hourly = [
            HourlyRainChance(date: now.addingTimeInterval(RainForecastPlanner.lookahead + 3600), chance: 0.9)
        ]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) == .notExpected)
    }

    @Test func picksTheEarliestQualifyingHour() {
        let hourly = [
            HourlyRainChance(date: now.addingTimeInterval(4 * 3600), chance: 0.6),
            HourlyRainChance(date: now.addingTimeInterval(2 * 3600), chance: 0.5),
            HourlyRainChance(date: now.addingTimeInterval(6 * 3600), chance: 0.8),
        ]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) == .at(now.addingTimeInterval(2 * 3600)))
    }

    @Test func withinTheNowWindowReadsAsNow() {
        let hourly = [HourlyRainChance(date: now.addingTimeInterval(300), chance: 0.9)]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) == .now)
    }

    @Test func aRecentPastHourStillCountsAsNow() {
        let hourly = [HourlyRainChance(date: now.addingTimeInterval(-300), chance: 0.9)]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) == .now)
    }

    @Test func exactlyAtTheThresholdCounts() {
        let hourly = [HourlyRainChance(date: now.addingTimeInterval(3600), chance: RainForecastPlanner.chanceThreshold)]
        #expect(RainForecastPlanner.forecast(from: hourly, now: now) != .notExpected)
    }
}
