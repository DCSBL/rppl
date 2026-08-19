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

    static func distanceKilometers(_ meters: Double) -> String {
        DistanceFormat.kilometers(meters)
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

    static func rideCount(_ count: Int) -> String {
        String(localized: "\(count) rides")
    }

    static func lapCount(_ count: Int) -> String {
        String(localized: "\(count) laps")
    }

    static func sessionCount(_ count: Int) -> String {
        String(localized: "\(count) total")
    }

    static func totalsFooter(rides: Int, laps: Int) -> String {
        let ridesText = String(localized: "\(rides) total rides")
        let lapsText = lapCount(laps)
        return String(localized: "\(ridesText) · \(lapsText)")
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

    static func rideHighlightLabel(_ highlight: RideHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Longest")
        case .longestTime: return String(localized: "Longest time")
        case .fastest: return String(localized: "Fastest")
        }
    }

    static func sessionHighlightLabel(_ highlight: SessionHighlight) -> String {
        switch highlight {
        case .longest: return String(localized: "Longest")
        case .mostWaterTime: return String(localized: "Most water time")
        case .mostLaps: return String(localized: "Most laps")
        }
    }

    static func joinedRideHighlights(_ highlights: [RideHighlight]) -> String {
        highlights.map(rideHighlightLabel).joined(separator: " ")
    }

    static func joinedSessionHighlights(_ highlights: [SessionHighlight]) -> String {
        highlights.map(sessionHighlightLabel).joined(separator: " ")
    }
}
