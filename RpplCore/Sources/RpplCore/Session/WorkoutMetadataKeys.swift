import Foundation

/// HealthKit workout metadata keys shared across Watch save paths.
public enum WorkoutMetadataKeys {
    public static let sessionId = "nl.dcsbl.rppl.sessionId"
    public static let detectionCode = "nl.dcsbl.rppl.detectionCode"
    public static let setCount = "nl.dcsbl.rppl.setCount"
    public static let totalDistanceMeters = "nl.dcsbl.rppl.totalDistanceMeters"
    public static let setDistanceMeters = "nl.dcsbl.rppl.distanceMeters"
    /// Estimated park water temperature (°C `HKQuantity`), only when the Watch measured none.
    public static let waterTemperatureEstimate = "nl.dcsbl.rppl.waterTemperatureEstimate"
}
