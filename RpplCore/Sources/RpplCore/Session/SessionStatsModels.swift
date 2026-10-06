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
    /// This set's cable speed (km/h), rounded to 0.5; see `CableSpeedEstimator.cableSpeedKmh(setWindow:...)`.
    /// Session-wide value unless this set's own estimate clears the override threshold.
    public var cableSpeedKmh: Double?
    /// Peak g-force (|userAcceleration|) in this set; see `ImpactStats`. Nil without motion data.
    public var peakImpactG: Double?
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
        cableSpeedKmh: Double? = nil,
        peakImpactG: Double? = nil,
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
        self.cableSpeedKmh = cableSpeedKmh
        self.peakImpactG = peakImpactG
        self.highlights = highlights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        lapCount = try container.decodeIfPresent(Int.self, forKey: .lapCount) ?? 0
        sustainedSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .sustainedSpeedKmh)
        averageSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .averageSpeedKmh)
        peakSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .peakSpeedKmh)
        cableSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .cableSpeedKmh)
        peakImpactG = try container.decodeIfPresent(Double.self, forKey: .peakImpactG)
        // Unknown badge codes (written by a newer build) are dropped, not a decode failure.
        highlights = (try container.decodeIfPresent([String].self, forKey: .highlights) ?? [])
            .compactMap(SetHighlight.init(rawValue:))
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
        try container.encodeIfPresent(cableSpeedKmh, forKey: .cableSpeedKmh)
        try container.encodeIfPresent(peakImpactG, forKey: .peakImpactG)
        try container.encode(highlights, forKey: .highlights)
    }

    private enum CodingKeys: String, CodingKey {
        case index, startedAt, endedAt, duration, distanceMeters
        case lapCount
        case sustainedSpeedKmh, averageSpeedKmh, peakSpeedKmh, cableSpeedKmh, peakImpactG, highlights
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

    /// Most common riding speed across the whole session (km/h), an estimate of the cable speed.
    /// Cable speed rarely changes mid-session, so each set's own `cableSpeedKmh` defaults to this
    /// value too; a set only overrides it when its own estimate clearly disagrees (see
    /// `CableSpeedEstimator`).
    public var cableSpeedKmh: Double?

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
        waterTemperatureAvailable: Bool = false,
        cableSpeedKmh: Double? = nil
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
        self.cableSpeedKmh = cableSpeedKmh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        totalDuration = try container.decode(TimeInterval.self, forKey: .totalDuration)
        totalDistanceMeters = try container.decode(Double.self, forKey: .totalDistanceMeters)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        totalEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .totalEnergyKilocalories)
        setCount = try container.decodeIfPresent(Int.self, forKey: .setCount) ?? 0
        ridingDuration = try container.decode(TimeInterval.self, forKey: .ridingDuration)
        inactiveDuration = try container.decode(TimeInterval.self, forKey: .inactiveDuration)
        ridingInactiveRatio = try container.decode(Double.self, forKey: .ridingInactiveRatio)
        sets = try container.decodeIfPresent([SetSegmentStats].self, forKey: .sets) ?? []
        averageWaterTemperatureCelsius = try container.decodeIfPresent(
            Double.self,
            forKey: .averageWaterTemperatureCelsius
        )
        waterTemperatureAvailable = try container.decodeIfPresent(Bool.self, forKey: .waterTemperatureAvailable) ?? false
        cableSpeedKmh = try container.decodeIfPresent(Double.self, forKey: .cableSpeedKmh)
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
        try container.encodeIfPresent(cableSpeedKmh, forKey: .cableSpeedKmh)
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, endedAt, totalDuration, totalDistanceMeters
        case activeEnergyKilocalories, totalEnergyKilocalories
        case setCount, sets
        case ridingDuration, inactiveDuration, ridingInactiveRatio
        case averageWaterTemperatureCelsius, waterTemperatureAvailable, cableSpeedKmh
    }
}
