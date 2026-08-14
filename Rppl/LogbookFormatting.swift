import Foundation
import RpplCore

enum LogbookFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "0m"
    }

    static func distanceKilometers(_ meters: Double) -> String {
        let km = meters / 1000
        if km >= 10 {
            return String(format: "%.0f km", km)
        }
        return String(format: "%.1f km", km)
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
}
