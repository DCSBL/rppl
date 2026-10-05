import Foundation

/// Derived set record badges (not detection taxonomy).
public enum SetHighlight: String, Sendable, Equatable, Codable, CaseIterable {
    case longest
    case longestTime
    case shortest
    case fastest
    case mostLaps
    /// Longest break before this set (start minus previous set's end).
    case comeback
    /// Shortest break before this set.
    case backToBack
}

/// Derived session record badges across the logbook.
public enum SessionHighlight: String, Sendable, Equatable, CaseIterable {
    case longest
    case mostWaterTime
    case mostLaps
    case highestRidePercentage
    case mostCalories
    case longestSetEver
    case mostSets
    case mostDistance
    case topSpeed
    case laziest
    case coldest
    case hottest
    case windiest
    case rainiest
    case iceBath
    case earlyBird
    case nightOwl
}

/// Per-session inputs for cross-logbook highlight assignment.
public struct SessionHighlightInput: Sendable, Equatable {
    public var id: String
    public var totalDuration: TimeInterval
    public var ridingDuration: TimeInterval
    public var lapCount: Int
    /// `ridingDuration / (ridingDuration + inactiveDuration)`; nil when no active time.
    public var ridingInactiveRatio: Double?
    /// Active + basal when both available; falls back to active-only.
    public var totalEnergyKilocalories: Double?
    /// Longest set (by distance) within this session; nil when no sets.
    public var longestSetDistanceMeters: Double?
    public var setCount: Int?
    public var totalDistanceMeters: Double?
    /// Peak speed (km/h) across the session's sets.
    public var topSpeedKmh: Double?
    /// Air temperature from the session weather snapshot.
    public var airTemperatureCelsius: Double?
    public var windSpeedKmh: Double?
    public var precipitationMmPerHour: Double?
    /// Measured mean water temperature, else the park station estimate.
    public var waterTemperatureCelsius: Double?
    /// Minutes since local midnight of the start day; see `minutesOfDay(start:end:calendar:)`.
    public var startMinuteOfDay: Double?
    /// Minutes since local midnight of the start day, so past midnight stays later than 23:59.
    public var endMinuteOfDay: Double?

    public init(
        id: String,
        totalDuration: TimeInterval,
        ridingDuration: TimeInterval,
        lapCount: Int,
        ridingInactiveRatio: Double? = nil,
        totalEnergyKilocalories: Double? = nil,
        longestSetDistanceMeters: Double? = nil,
        setCount: Int? = nil,
        totalDistanceMeters: Double? = nil,
        topSpeedKmh: Double? = nil,
        airTemperatureCelsius: Double? = nil,
        windSpeedKmh: Double? = nil,
        precipitationMmPerHour: Double? = nil,
        waterTemperatureCelsius: Double? = nil,
        startMinuteOfDay: Double? = nil,
        endMinuteOfDay: Double? = nil
    ) {
        self.id = id
        self.totalDuration = totalDuration
        self.ridingDuration = ridingDuration
        self.lapCount = lapCount
        self.ridingInactiveRatio = ridingInactiveRatio
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.longestSetDistanceMeters = longestSetDistanceMeters
        self.setCount = setCount
        self.totalDistanceMeters = totalDistanceMeters
        self.topSpeedKmh = topSpeedKmh
        self.airTemperatureCelsius = airTemperatureCelsius
        self.windSpeedKmh = windSpeedKmh
        self.precipitationMmPerHour = precipitationMmPerHour
        self.waterTemperatureCelsius = waterTemperatureCelsius
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }

    /// Start and end as minutes since local midnight of the start day. End is nil when the
    /// session has no end yet.
    public static func minutesOfDay(
        start: Date,
        end: Date?,
        calendar: Calendar
    ) -> (start: Double, end: Double?) {
        let midnight = calendar.startOfDay(for: start)
        let startMinutes = start.timeIntervalSince(midnight) / 60
        let endMinutes = end.map { $0.timeIntervalSince(midnight) / 60 }
        return (startMinutes, endMinutes)
    }
}
