import Foundation
import RpplCore

enum SessionFormatters {
    static func elapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func segmentDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Watch set rows — explicit minute/second units.
    static func rideDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %dm %ds", hours, remainingMinutes, seconds)
        }
        return String(format: "%dm %ds", minutes, seconds)
    }

    static func averageSpeed(_ kmh: Double) -> String {
        DistanceFormat.kilometersPerHour(kmh)
    }

    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return DistanceFormat.kilometers(meters)
        }
        return DistanceFormat.meters(meters)
    }

    static func waterTemp(_ celsius: Double) -> String {
        TemperatureFormat.celsius(celsius)
    }
}
