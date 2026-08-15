import Foundation
import RpplCore

enum LogbookFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        formatDuration(interval, minutesUnit: "m")
    }

    /// Ride cards spell out minutes; other surfaces keep compact `m`.
    static func rideCardDuration(_ interval: TimeInterval) -> String {
        formatDuration(interval, minutesUnit: "minutes")
    }

    static func distanceKilometers(_ meters: Double) -> String {
        let km = meters / 1000
        if km >= 10 {
            return String(format: "%.0f km", km)
        }
        return String(format: "%.2f km", km)
    }

    static func speedKilometersPerHour(_ kmh: Double) -> String {
        String(format: "%.1f km/h", kmh)
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

    private static func formatDuration(_ interval: TimeInterval, minutesUnit: String) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0 || hours > 0 {
            if minutesUnit == "m" {
                parts.append("\(minutes)m")
            } else {
                parts.append("\(minutes) \(minutesUnit)")
            }
        }
        parts.append("\(seconds)s")
        return parts.joined(separator: " ")
    }
}
