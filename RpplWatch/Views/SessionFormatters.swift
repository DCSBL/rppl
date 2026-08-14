import Foundation

enum SessionFormatters {
    static func elapsed(_ interval: TimeInterval) -> String {
        let totalCentiseconds = max(0, Int((interval * 100).rounded()))
        let hours = totalCentiseconds / 360_000
        let minutes = (totalCentiseconds / 6_000) % 60
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d,%02d", minutes, seconds, centiseconds)
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
            return String(format: "%.2f KM", meters / 1000)
        }
        return String(format: "%.0f M", meters)
    }

    static func speedKmh(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond >= 0 else { return "--" }
        return String(format: "%.1f", metersPerSecond * 3.6)
    }
}
