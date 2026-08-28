import Foundation

/// Frozen stats shown after Stop until the rider taps Done.
struct EndedSessionSummary: Equatable, Sendable {
    let sessionId: String
    let duration: TimeInterval
    let setCount: Int
    let distanceMeters: Double
    let lastSetDuration: TimeInterval
    let lastSetMeters: Double
    let lastSetLapCount: Int
    let didCompleteSet: Bool
    let startLatitude: Double?
    let startLongitude: Double?
}
