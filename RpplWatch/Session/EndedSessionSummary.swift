import Foundation

/// Frozen stats shown after Stop until the rider taps Done.
struct EndedSessionSummary: Equatable, Sendable {
    let sessionId: String
    let duration: TimeInterval
    let rideCount: Int
    let distanceMeters: Double
    let lastRideDuration: TimeInterval
    let lastRideMeters: Double
    let lastRideLapCount: Int
    let didCompleteRide: Bool
    let startLatitude: Double?
    let startLongitude: Double?
}
