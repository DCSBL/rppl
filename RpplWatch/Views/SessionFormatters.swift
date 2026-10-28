import Foundation
import RpplCore

enum SessionFormatters {
    static func elapsed(_ interval: TimeInterval) -> String {
        let duration = wholeSeconds(interval)
        return duration < .seconds(3600)
            ? duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
            : duration.formatted(.time(pattern: .hourMinuteSecond))
    }

    static func segmentDuration(_ interval: TimeInterval) -> String {
        let duration = wholeSeconds(interval)
        return duration < .seconds(3600)
            ? duration.formatted(.time(pattern: .minuteSecond))
            : duration.formatted(.time(pattern: .hourMinuteSecond))
    }

    private static func wholeSeconds(_ interval: TimeInterval) -> Duration {
        .seconds(max(0, Int(interval.rounded())))
    }

    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return DistanceFormat.kilometers(meters)
        }
        return DistanceFormat.meters(meters)
    }

    /// Estimates get a leading `~` so they read as a guess, not a sensor reading.
    static func waterTemp(_ celsius: Double, isEstimate: Bool = false) -> String {
        let text = TemperatureFormat.celsius(celsius)
        return isEstimate ? "~" + text : text
    }

}
