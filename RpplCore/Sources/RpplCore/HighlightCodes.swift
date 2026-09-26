import Foundation

/// Derived set record badges (not detection taxonomy).
public enum SetHighlight: String, Sendable, Equatable, Codable, CaseIterable {
    case longest
    case longestTime
    case shortest
    case fastest
}

/// Derived session record badges across the logbook.
public enum SessionHighlight: String, Sendable, Equatable, CaseIterable {
    case longest
    case mostWaterTime
    case mostLaps
    case highestRidePercentage
    case mostCalories
    case longestSetEver
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

    public init(
        id: String,
        totalDuration: TimeInterval,
        ridingDuration: TimeInterval,
        lapCount: Int,
        ridingInactiveRatio: Double? = nil,
        totalEnergyKilocalories: Double? = nil,
        longestSetDistanceMeters: Double? = nil
    ) {
        self.id = id
        self.totalDuration = totalDuration
        self.ridingDuration = ridingDuration
        self.lapCount = lapCount
        self.ridingInactiveRatio = ridingInactiveRatio
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.longestSetDistanceMeters = longestSetDistanceMeters
    }
}
