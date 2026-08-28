import Foundation

/// HealthKit workout metadata keys shared across Watch save paths.
public enum WorkoutMetadataKeys {
    public static let sessionId = "nl.dcsbl.rppl.sessionId"
    public static let detectionCode = "nl.dcsbl.rppl.detectionCode"
    public static let setCount = "nl.dcsbl.rppl.setCount"
    /// Legacy pre-sets rename; decode only.
    public static let legacyRideCount = "nl.dcsbl.rppl.rideCount"
    public static let totalDistanceMeters = "nl.dcsbl.rppl.totalDistanceMeters"
    public static let setDistanceMeters = "nl.dcsbl.rppl.distanceMeters"
}
