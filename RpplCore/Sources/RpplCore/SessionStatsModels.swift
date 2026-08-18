import Foundation

/// One detected ride segment (enter → exit or session end).
public struct RideSegmentStats: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    public var distanceMeters: Double
    /// Crossing-based laps for this ride (0 until assumed return to start).
    public var lapCount: Int
    /// Best sustained-window mean speed (km/h); see `LocationSpeedStats.sustainedSpeedKmh`.
    public var sustainedSpeedKmh: Double?
    /// Trimmed path average (km/h); see `LocationSpeedStats.trimmedAverageSpeedKmh`.
    public var averageSpeedKmh: Double?
    /// Record badges for this ride within the session (empty if none).
    public var highlights: [RideHighlight]

    public init(
        index: Int,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        lapCount: Int = 0,
        sustainedSpeedKmh: Double? = nil,
        averageSpeedKmh: Double? = nil,
        highlights: [RideHighlight] = []
    ) {
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.lapCount = lapCount
        self.sustainedSpeedKmh = sustainedSpeedKmh
        self.averageSpeedKmh = averageSpeedKmh
        self.highlights = highlights
    }
}

/// Derived session summary from detections + GPS + health (not persisted).
public struct SessionStats: Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var totalDuration: TimeInterval
    public var totalDistanceMeters: Double
    /// Ride-scoped active energy (max mirrored HK activeEnergyBurned).
    public var activeEnergyKilocalories: Double?
    /// Active + basal when both available (Apple-like total).
    public var totalEnergyKilocalories: Double?
    public var rideCount: Int
    public var ridingDuration: TimeInterval
    public var inactiveDuration: TimeInterval
    /// `ridingDuration / (ridingDuration + inactiveDuration)`; 0 when no active time.
    public var ridingInactiveRatio: Double
    public var rides: [RideSegmentStats]
    /// Mean of persisted water-temp samples; nil when none.
    public var averageWaterTemperatureCelsius: Double?
    /// Watch could measure (Ultra). Drives hide vs `- C`.
    public var waterTemperatureAvailable: Bool

    /// Max sustained speed across rides (km/h).
    public var topSpeedKmh: Double? {
        rides.compactMap(\.sustainedSpeedKmh).max()
    }

    /// Sum of per-ride crossing counts.
    public var totalLapCount: Int {
        rides.reduce(0) { $0 + $1.lapCount }
    }

    public init(
        startedAt: Date,
        endedAt: Date,
        totalDuration: TimeInterval,
        totalDistanceMeters: Double,
        activeEnergyKilocalories: Double?,
        totalEnergyKilocalories: Double? = nil,
        rideCount: Int,
        ridingDuration: TimeInterval,
        inactiveDuration: TimeInterval,
        ridingInactiveRatio: Double,
        rides: [RideSegmentStats],
        averageWaterTemperatureCelsius: Double? = nil,
        waterTemperatureAvailable: Bool = false
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalDuration = totalDuration
        self.totalDistanceMeters = totalDistanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.rideCount = rideCount
        self.ridingDuration = ridingDuration
        self.inactiveDuration = inactiveDuration
        self.ridingInactiveRatio = ridingInactiveRatio
        self.rides = rides
        self.averageWaterTemperatureCelsius = averageWaterTemperatureCelsius
        self.waterTemperatureAvailable = waterTemperatureAvailable
    }
}
