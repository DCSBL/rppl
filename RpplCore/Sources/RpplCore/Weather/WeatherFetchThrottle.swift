import Foundation

/// Internal rate limit for WeatherKit calls (Apple caps monthly calls per developer account).
///
/// At most one network attempt per location per `minInterval`. Failed attempts count too, so an
/// outage or flaky connection cannot turn into a retry storm. Locations are bucketed to a coarse
/// grid so a park and a nearby GPS fix on the Watch share one slot.
public struct WeatherFetchThrottle: Sendable {
    public static let minInterval: TimeInterval = 60 * 60
    /// Grid cell size in degrees (~5 km north-south).
    public static let cellDegrees = 0.05

    private var lastAttempt: [String: Date] = [:]

    public init() {}

    public static func key(latitude: Double, longitude: Double) -> String {
        let lat = (latitude / cellDegrees).rounded()
        let lon = (longitude / cellDegrees).rounded()
        return "\(Int(lat)),\(Int(lon))"
    }

    /// True when a fetch is allowed now for this location.
    public func canFetch(latitude: Double, longitude: Double, now: Date = Date()) -> Bool {
        guard let last = lastAttempt[Self.key(latitude: latitude, longitude: longitude)] else { return true }
        return now.timeIntervalSince(last) >= Self.minInterval || now < last
    }

    /// Record an attempt (success or failure).
    public mutating func recordAttempt(latitude: Double, longitude: Double, now: Date = Date()) {
        lastAttempt[Self.key(latitude: latitude, longitude: longitude)] = now
    }
}
