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

    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return DistanceFormat.kilometers(meters)
        }
        return DistanceFormat.meters(meters)
    }

    static func speedKmh(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond >= 0 else { return "--" }
        return String(format: "%.1f", metersPerSecond * 3.6)
    }
}
