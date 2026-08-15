import Foundation

/// Derived ride record badges (not detection taxonomy).
public enum RideHighlight: String, Sendable, Equatable, CaseIterable {
    case longest
    case longestTime
    case fastest
}

/// Derived session record badges across the logbook.
public enum SessionHighlight: String, Sendable, Equatable, CaseIterable {
    case longest
    case mostWaterTime
    case mostLaps
}
