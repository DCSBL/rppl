import Foundation

/// Converts a sensor timestamp (seconds since the device booted, as `CMDeviceMotion.timestamp`
/// reports it) to wall-clock time.
///
/// Stamping a sample with `Date()` in the delivery callback records when the handler ran, not when
/// the sensor measured. When the main thread is busy, queued 25 Hz updates then all get nearly the
/// same time. The sensor timestamp does not depend on delivery.
public enum SensorClock {
    /// Seconds to add to a boot-relative sensor timestamp to get a Unix timestamp. Measure once
    /// when the sensor starts.
    public static func bootOffset(now: Date, systemUptime: TimeInterval) -> TimeInterval {
        now.timeIntervalSince1970 - systemUptime
    }

    /// A converted time further than this ahead of `now` cannot be right (a sample is never from
    /// the future), so the offset has drifted.
    public static let maxFutureSkew: TimeInterval = 2
    /// Delivery can lag, but not by more than this; older means the offset has drifted.
    public static let maxDeliveryLag: TimeInterval = 10 * 60

    /// Wall-clock time of a sensor sample. Falls back to `now` when the conversion lands in the
    /// future or implausibly far in the past (a stale offset after the clock was adjusted), so a
    /// bad offset can never poison the time series.
    public static func wallDate(bootOffset: TimeInterval, sensorTimestamp: TimeInterval, now: Date) -> Date {
        let converted = Date(timeIntervalSince1970: bootOffset + sensorTimestamp)
        if converted > now.addingTimeInterval(maxFutureSkew) { return now }
        if converted < now.addingTimeInterval(-maxDeliveryLag) { return now }
        return converted
    }
}
