import Foundation

/// One detected set segment (enter → exit or session end).
public struct SetSegmentStats: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    public var distanceMeters: Double
    /// Crossing-based laps for this set (0 until assumed return to start).
    public var lapCount: Int
    /// Best sustained-window mean speed (km/h); see `LocationSpeedStats.sustainedSpeedKmh`.
    public var sustainedSpeedKmh: Double?
    /// Trimmed path average (km/h); see `LocationSpeedStats.trimmedAverageSpeedKmh`.
    public var averageSpeedKmh: Double?
    /// Peak usable GPS sample speed (km/h); see `LocationSpeedStats.peakSpeedKmh`.
    public var peakSpeedKmh: Double?
    /// This set ran conspicuously shorter than a normal full lap — a fall, a failed trick, or a
    /// failed start cut it short; see `FallDetector`.
    public var fallDetected: Bool
    /// Record badges for this set within the session (empty if none).
    public var highlights: [SetHighlight]

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
        fallDetected: Bool = false,
        highlights: [SetHighlight] = []
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
        self.fallDetected = fallDetected
        self.highlights = highlights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        // Canonical `lapCount`. Accept short-lived slang mis-rename `setCount` on segments (forward only).
        if let laps = try container.decodeIfPresent(Int.self, forKey: .lapCount) {
            lapCount = laps
        } else {
            lapCount = try container.decodeIfPresent(Int.self, forKey: .legacyLapSetCount) ?? 0
        }
        sustainedSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .sustainedSpeedKmh)
        averageSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .averageSpeedKmh)
        peakSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .peakSpeedKmh)
        fallDetected = try container.decodeIfPresent(Bool.self, forKey: .fallDetected) ?? false
        highlights = try container.decodeIfPresent([SetHighlight].self, forKey: .highlights) ?? []
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
        try container.encode(fallDetected, forKey: .fallDetected)
        try container.encode(highlights, forKey: .highlights)
    }

    private enum CodingKeys: String, CodingKey {
        case index, startedAt, endedAt, duration, distanceMeters
        case lapCount
        /// Intermediate slang mis-rename (circuit crossings briefly called sets).
        case legacyLapSetCount = "setCount"
        case sustainedSpeedKmh, averageSpeedKmh, peakSpeedKmh, fallDetected, highlights
    }
}

/// Derived session summary from detections + GPS + health.
/// Persisted in `derived/view.json` when present (see `DerivedSessionView`).
public struct SessionStats: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var totalDuration: TimeInterval
    public var totalDistanceMeters: Double
    /// Set-scoped active energy (max mirrored HK activeEnergyBurned).
    public var activeEnergyKilocalories: Double?
    /// Active + basal when both available (Apple-like total).
    public var totalEnergyKilocalories: Double?
    public var setCount: Int
    public var ridingDuration: TimeInterval
    public var inactiveDuration: TimeInterval
    /// `ridingDuration / (ridingDuration + inactiveDuration)`; 0 when no active time.
    public var ridingInactiveRatio: Double
    public var sets: [SetSegmentStats]
    /// Mean of persisted water-temp samples; nil when none.
    public var averageWaterTemperatureCelsius: Double?
    /// Watch could measure (Ultra). Drives hide vs `- C`.
    public var waterTemperatureAvailable: Bool

    /// Max sustained speed across sets (km/h). Used for fastest-set highlights.
    public var topSpeedKmh: Double? {
        sets.compactMap(\.sustainedSpeedKmh).max()
    }

    /// Max usable GPS sample speed across sets (km/h).
    public var maxSpeedKmh: Double? {
        sets.compactMap(\.peakSpeedKmh).max()
    }

    /// Set meters / riding duration (km/h).
    public var averageSpeedKmh: Double? {
        LocationSpeedStats.averageSpeedKmh(
            distanceMeters: totalDistanceMeters,
            duration: ridingDuration
        )
    }

    /// Sum of per-set crossing counts.
    public var totalLapCount: Int {
        sets.reduce(0) { $0 + $1.lapCount }
    }

    /// Sets flagged by `FallDetector`.
    public var fallCount: Int {
        sets.reduce(0) { $0 + ($1.fallDetected ? 1 : 0) }
    }

    public init(
        startedAt: Date,
        endedAt: Date,
        totalDuration: TimeInterval,
        totalDistanceMeters: Double,
        activeEnergyKilocalories: Double?,
        totalEnergyKilocalories: Double? = nil,
        setCount: Int,
        ridingDuration: TimeInterval,
        inactiveDuration: TimeInterval,
        ridingInactiveRatio: Double,
        sets: [SetSegmentStats],
        averageWaterTemperatureCelsius: Double? = nil,
        waterTemperatureAvailable: Bool = false
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalDuration = totalDuration
        self.totalDistanceMeters = totalDistanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.setCount = setCount
        self.ridingDuration = ridingDuration
        self.inactiveDuration = inactiveDuration
        self.ridingInactiveRatio = ridingInactiveRatio
        self.sets = sets
        self.averageWaterTemperatureCelsius = averageWaterTemperatureCelsius
        self.waterTemperatureAvailable = waterTemperatureAvailable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        totalDuration = try container.decode(TimeInterval.self, forKey: .totalDuration)
        totalDistanceMeters = try container.decode(Double.self, forKey: .totalDistanceMeters)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        totalEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .totalEnergyKilocalories)
        if let count = try container.decodeIfPresent(Int.self, forKey: .setCount) {
            setCount = count
        } else {
            setCount = try container.decodeIfPresent(Int.self, forKey: .legacyRideCount) ?? 0
        }
        ridingDuration = try container.decode(TimeInterval.self, forKey: .ridingDuration)
        inactiveDuration = try container.decode(TimeInterval.self, forKey: .inactiveDuration)
        ridingInactiveRatio = try container.decode(Double.self, forKey: .ridingInactiveRatio)
        if let decodedSets = try container.decodeIfPresent([SetSegmentStats].self, forKey: .sets) {
            sets = decodedSets
        } else {
            sets = try container.decodeIfPresent([SetSegmentStats].self, forKey: .legacyRides) ?? []
        }
        averageWaterTemperatureCelsius = try container.decodeIfPresent(
            Double.self,
            forKey: .averageWaterTemperatureCelsius
        )
        waterTemperatureAvailable = try container.decodeIfPresent(Bool.self, forKey: .waterTemperatureAvailable) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(totalDuration, forKey: .totalDuration)
        try container.encode(totalDistanceMeters, forKey: .totalDistanceMeters)
        try container.encodeIfPresent(activeEnergyKilocalories, forKey: .activeEnergyKilocalories)
        try container.encodeIfPresent(totalEnergyKilocalories, forKey: .totalEnergyKilocalories)
        try container.encode(setCount, forKey: .setCount)
        try container.encode(ridingDuration, forKey: .ridingDuration)
        try container.encode(inactiveDuration, forKey: .inactiveDuration)
        try container.encode(ridingInactiveRatio, forKey: .ridingInactiveRatio)
        try container.encode(sets, forKey: .sets)
        try container.encodeIfPresent(averageWaterTemperatureCelsius, forKey: .averageWaterTemperatureCelsius)
        try container.encode(waterTemperatureAvailable, forKey: .waterTemperatureAvailable)
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, endedAt, totalDuration, totalDistanceMeters
        case activeEnergyKilocalories, totalEnergyKilocalories
        case setCount, sets
        case legacyRideCount = "rideCount"
        case legacyRides = "rides"
        case ridingDuration, inactiveDuration, ridingInactiveRatio
        case averageWaterTemperatureCelsius, waterTemperatureAvailable
    }
}
