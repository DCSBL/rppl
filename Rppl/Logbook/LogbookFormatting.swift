import Foundation
import RpplCore

enum LogbookFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        // Single-unit spans use wide words ("1 minute"); mixed spans stay compact ("1h 2m").
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let nonZero = [hours, minutes, seconds].filter { $0 > 0 }.count
        let width: Duration.UnitsFormatStyle.UnitWidth = nonZero <= 1 ? .wide : .abbreviated
        let formatted = DurationFormat.units(TimeInterval(total), width: width)
        return formatted.isEmpty ? DurationFormat.units(0, width: .wide) : formatted
    }

    /// Narrow units ("1h 19m 36s") for tiles and chips where width is tight.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let total = max(0, interval.rounded())
        let formatted = DurationFormat.units(total, width: .narrow)
        return formatted.isEmpty ? DurationFormat.units(0, width: .narrow) : formatted
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func distanceKilometers(_ meters: Double) -> String {
        DistanceFormat.kilometers(meters)
    }

    static func approximateDistance(_ meters: Double) -> String {
        DistanceFormat.approximateKilometers(meters)
    }

    static func speedKilometersPerHour(_ kmh: Double) -> String {
        DistanceFormat.kilometersPerHour(kmh)
    }

    static func kilocalories(_ value: Double) -> String {
        EnergyFormat.kilocalories(value)
    }

    static func waterTemperature(_ celsius: Double) -> String {
        TemperatureFormat.celsius(celsius)
    }

    static func airTemperature(_ celsius: Double) -> String {
        TemperatureFormat.celsius(celsius)
    }

    static func humidityPercent(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func windSummary(kmh: Double, directionDegrees: Double) -> String {
        let compass = CompassDirection8(degrees: directionDegrees).abbreviation
        return "\(DistanceFormat.kilometersPerHour(kmh)) · \(compass)"
    }

    /// mm/h doesn't localize like temperature or speed — there's no imperial rain-rate unit in
    /// everyday use, so only the decimal separator follows locale.
    static func precipitation(_ millimetersPerHour: Double) -> String {
        let fractionDigits = millimetersPerHour < 10 ? 1 : 0
        let value = millimetersPerHour.formatted(.number.precision(.fractionLength(fractionDigits)))
        return "\(value) mm/h"
    }

    static func setCount(_ count: Int) -> String {
        String(localized: "\(count) sets")
    }

    static func lapCount(_ count: Int) -> String {
        String(localized: "\(count) laps")
    }

    static func setsAndLaps(sets: Int, laps: Int) -> String {
        let setsText = setCount(sets)
        let lapsText = lapCount(laps)
        return String(localized: "\(setsText) · \(lapsText)")
    }

    static func sessionCount(_ count: Int) -> String {
        String(localized: "\(count) total")
    }

    static func totalsFooter(sets: Int, laps: Int) -> String {
        let setsText = String(localized: "\(sets) total sets")
        let lapsText = lapCount(laps)
        return String(localized: "\(setsText) · \(lapsText)")
    }

    static func sessionDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func sessionTimeRange(start: Date, end: Date?) -> String {
        let startText = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return startText }
        let endText = end.formatted(date: .omitted, time: .shortened)
        return "\(startText) – \(endText)"
    }

    static func setHighlightLabel(_ highlight: SetHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Longest")
        case .longestTime: return String(localized: "Longest time")
        case .shortest: return String(localized: "Shortest")
        case .fastest: return String(localized: "Fastest")
        case .mostLaps: return String(localized: "Most laps")
        case .comeback: return String(localized: "Comeback")
        case .backToBack: return String(localized: "Back to back")
        }
    }

    static func setHighlightExplanation(_ highlight: SetHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Most distance of all sets this session.")
        case .longestTime: return String(localized: "Longest time on the water of all sets this session.")
        case .shortest: return String(localized: "Shortest set this session. Happens to everyone.")
        case .fastest: return String(localized: "Highest sustained speed of all sets this session.")
        case .mostLaps: return String(localized: "Most laps in one set this session.")
        case .comeback: return String(localized: "Back on the water after a long break, the longest this session.")
        case .backToBack: return String(localized: "Shortest break before a set this session. Barely dried off.")
        }
    }

    static func sessionHighlightLabel(_ highlight: SessionHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Longest")
        case .mostWaterTime: return String(localized: "Most water time")
        case .mostLaps: return String(localized: "Most laps")
        case .highestRidePercentage: return String(localized: "Highest ride %")
        case .mostCalories: return String(localized: "Most calories")
        case .longestSetEver: return String(localized: "Longest set ever")
        case .mostSets: return String(localized: "Most sets")
        case .mostDistance: return String(localized: "Most distance")
        case .topSpeed: return String(localized: "Top speed")
        case .laziest: return String(localized: "Laziest")
        case .coldest: return String(localized: "Coldest")
        case .hottest: return String(localized: "Hottest")
        case .windiest: return String(localized: "Windiest")
        case .rainiest: return String(localized: "Rain rider")
        case .iceBath: return String(localized: "Ice bath")
        case .earlyBird: return String(localized: "Early bird")
        case .nightOwl: return String(localized: "Night owl")
        }
    }

    static func sessionHighlightExplanation(_ highlight: SessionHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Longest session in your logbook.")
        case .mostWaterTime: return String(localized: "Most time riding of all your sessions.")
        case .mostLaps: return String(localized: "Most laps of all your sessions.")
        case .highestRidePercentage: return String(localized: "Biggest share of the session spent riding. Hardly sat on the dock.")
        case .mostCalories: return String(localized: "Most calories burned of all your sessions.")
        case .longestSetEver: return String(localized: "Your longest set ever, by distance.")
        case .mostSets: return String(localized: "Most sets of all your sessions.")
        case .mostDistance: return String(localized: "Most distance of all your sessions.")
        case .topSpeed: return String(localized: "Highest speed of all your sessions.")
        case .laziest: return String(localized: "Smallest share of the session spent riding. More dock than cable.")
        case .coldest: return String(localized: "Coldest air of all your sessions. Wetsuit weather.")
        case .hottest: return String(localized: "Warmest air of all your sessions. A proper summer day.")
        case .windiest: return String(localized: "Most wind of all your sessions, and it was properly windy.")
        case .rainiest: return String(localized: "Most rain of all your sessions. You were getting wet anyway.")
        case .iceBath: return String(localized: "Coldest water of all your sessions. Properly cold, too.")
        case .earlyBird: return String(localized: "Earliest start of all your sessions. On the cable before most people have had breakfast.")
        case .nightOwl: return String(localized: "Latest finish of all your sessions. Riding well into the evening.")
        }
    }
}
