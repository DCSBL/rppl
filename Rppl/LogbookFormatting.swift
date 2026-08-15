import Foundation
import RpplCore

enum LogbookFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var compactParts: [String] = []
        if hours > 0 {
            compactParts.append("\(hours)h")
        }
        if minutes > 0 {
            compactParts.append("\(minutes)m")
        }
        if seconds > 0 {
            compactParts.append("\(seconds)s")
        }

        if compactParts.isEmpty {
            return "0 seconds"
        }
        if compactParts.count == 1 {
            if hours > 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }
            if minutes > 0 {
                return minutes == 1 ? "1 minute" : "\(minutes) minutes"
            }
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        return compactParts.joined(separator: " ")
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

    static func rideHighlightLabel(_ highlight: RideHighlight) -> String {
        switch highlight {
        case .longest: return "Longest"
        case .longestTime: return "Longest time"
        case .fastest: return "Fastest"
        }
    }

    static func sessionHighlightLabel(_ highlight: SessionHighlight) -> String {
        switch highlight {
        case .longest: return "Longest"
        case .mostWaterTime: return "Most water time"
        case .mostLaps: return "Most laps"
        }
    }

    static func joinedRideHighlights(_ highlights: [RideHighlight]) -> String {
        highlights.map(rideHighlightLabel).joined(separator: " ")
    }

    static func joinedSessionHighlights(_ highlights: [SessionHighlight]) -> String {
        highlights.map(sessionHighlightLabel).joined(separator: " ")
    }
}
