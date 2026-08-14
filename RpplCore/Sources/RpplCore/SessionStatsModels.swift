import Foundation

/// One detected ride segment (enter → exit or session end).
public struct RideSegmentStats: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    public var distanceMeters: Double

    public init(
        index: Int,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double
    ) {
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
    }
}

/// Derived session summary from detections + GPS + health (not persisted).
public struct SessionStats: Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var totalDuration: TimeInterval
    public var totalDistanceMeters: Double
    public var activeEnergyKilocalories: Double?
    public var rideCount: Int
    public var ridingDuration: TimeInterval
    public var pausedDuration: TimeInterval
    /// `ridingDuration / (ridingDuration + pausedDuration)`; 0 when no active time.
    public var ridingPausedRatio: Double
    public var rides: [RideSegmentStats]

    public init(
        startedAt: Date,
        endedAt: Date,
        totalDuration: TimeInterval,
        totalDistanceMeters: Double,
        activeEnergyKilocalories: Double?,
        rideCount: Int,
        ridingDuration: TimeInterval,
        pausedDuration: TimeInterval,
        ridingPausedRatio: Double,
        rides: [RideSegmentStats]
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalDuration = totalDuration
        self.totalDistanceMeters = totalDistanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.rideCount = rideCount
        self.ridingDuration = ridingDuration
        self.pausedDuration = pausedDuration
        self.ridingPausedRatio = ridingPausedRatio
        self.rides = rides
    }
}
