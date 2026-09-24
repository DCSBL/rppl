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
}

/// Per-session inputs for cross-logbook highlight assignment.
public struct SessionHighlightInput: Sendable, Equatable {
    public var id: String
    public var totalDuration: TimeInterval
    public var ridingDuration: TimeInterval
    public var lapCount: Int

    public init(
        id: String,
        totalDuration: TimeInterval,
        ridingDuration: TimeInterval,
        lapCount: Int
    ) {
        self.id = id
        self.totalDuration = totalDuration
        self.ridingDuration = ridingDuration
        self.lapCount = lapCount
    }
}
