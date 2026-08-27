import Foundation

/// One detected ride segment (enter → exit or session end).
public struct RideSegmentStats: Codable, Equatable, Sendable, Identifiable {
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
    /// Peak usable GPS sample speed (km/h); see `LocationSpeedStats.peakSpeedKmh`.
    public var peakSpeedKmh: Double?
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
        peakSpeedKmh: Double? = nil,
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
        self.peakSpeedKmh = peakSpeedKmh
        self.highlights = highlights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        // Canonical `lapCount`. Accept short-lived slang mis-rename `setCount` (forward only).
        if let laps = try container.decodeIfPresent(Int.self, forKey: .lapCount) {
            lapCount = laps
        } else {
            lapCount = try container.decodeIfPresent(Int.self, forKey: .setCount) ?? 0
        }
        sustainedSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .sustainedSpeedKmh)
        averageSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .averageSpeedKmh)
        peakSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .peakSpeedKmh)
        highlights = try container.decodeIfPresent([RideHighlight].self, forKey: .highlights) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(lapCount, forKey: .lapCount)
        try container.encodeIfPresent(sustainedSpeedKmh, forKey: .sustainedSpeedKmh)
        try container.encodeIfPresent(averageSpeedKmh, forKey: .averageSpeedKmh)
        try container.encodeIfPresent(peakSpeedKmh, forKey: .peakSpeedKmh)
        try container.encode(highlights, forKey: .highlights)
    }

    private enum CodingKeys: String, CodingKey {
        case index, startedAt, endedAt, duration, distanceMeters
        case lapCount
        /// Intermediate slang mis-rename (circuit crossings briefly called sets).
        case setCount
        case sustainedSpeedKmh, averageSpeedKmh, peakSpeedKmh, highlights
    }
}

/// Derived session summary from detections + GPS + health.
/// Persisted in `derived/view.json` when present (see `DerivedSessionView`).
public struct SessionStats: Codable, Equatable, Sendable {
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

    /// Max sustained speed across rides (km/h). Used for fastest-ride highlights.
    public var topSpeedKmh: Double? {
        rides.compactMap(\.sustainedSpeedKmh).max()
    }

    /// Max usable GPS sample speed across rides (km/h).
    public var maxSpeedKmh: Double? {
        rides.compactMap(\.peakSpeedKmh).max()
    }

    /// Ride meters / riding duration (km/h).
    public var averageSpeedKmh: Double? {
        LocationSpeedStats.averageSpeedKmh(
            distanceMeters: totalDistanceMeters,
            duration: ridingDuration
        )
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
