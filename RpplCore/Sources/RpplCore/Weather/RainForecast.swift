import Foundation

/// When rain is next expected, distilled from an hourly precipitation-chance forecast.
public enum RainForecast: Equatable, Sendable {
    case notExpected
    case now
    case at(Date)

    public var label: String {
        switch self {
        case .notExpected:
            String(localized: "Not expected", bundle: .module)
        case .now:
            String(localized: "Raining now", bundle: .module)
        case .at(let date):
            String(localized: "Rain \(date.formatted(.relative(presentation: .numeric)))", bundle: .module)
        }
    }
}

/// One hour's precipitation chance (0–1) from a weather forecast, the minimal input
/// `RainForecastPlanner` needs — kept free of any specific weather framework's types.
public struct HourlyRainChance: Equatable, Sendable {
    public var date: Date
    public var chance: Double

    public init(date: Date, chance: Double) {
        self.date = date
        self.chance = chance
    }
}

public enum RainForecastPlanner {
    /// Chance (0–1) above which an hour counts as "rain expected".
    public static let chanceThreshold = 0.4
    /// How far ahead to look before calling it "not expected".
    public static let lookahead: TimeInterval = 12 * 3600
    /// An hour within this many seconds of `now` reads as "now" rather than a relative time.
    private static let nowWindow: TimeInterval = 20 * 60

    /// Earliest hour at/after `now` that clears `chanceThreshold`, within `lookahead`.
    public static func forecast(from hourly: [HourlyRainChance], now: Date = Date()) -> RainForecast {
        let horizon = now.addingTimeInterval(lookahead)
        let earliestPastCutoff = now.addingTimeInterval(-nowWindow)
        let hit = hourly
            .filter { $0.date >= earliestPastCutoff && $0.date <= horizon && $0.chance >= chanceThreshold }
            .min { $0.date < $1.date }
        guard let hit else { return .notExpected }
        return hit.date <= now.addingTimeInterval(nowWindow) ? .now : .at(hit.date)
    }
}
