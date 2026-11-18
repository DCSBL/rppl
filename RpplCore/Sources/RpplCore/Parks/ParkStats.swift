import Foundation

/// Totals over the park catalog for the Statistics tab. Park data only changes when the catalog reloads,
/// so the store computes this once per reload instead of on every screen load.
public struct ParkStats: Equatable, Sendable {
    public var parkCount = 0
    public var cableCount = 0
    /// Sum of the cable lengths (`ParkCable.effectiveLengthM`); cables without a trace add nothing.
    public var totalLengthM = 0.0
    public var counterClockwise = 0
    public var clockwise = 0
    public var twoPointZero = 0

    public init() {}

    public init(parks: [Park]) {
        parkCount = parks.count
        for cable in parks.flatMap({ $0.cables ?? [] }) {
            cableCount += 1
            totalLengthM += cable.effectiveLengthM ?? 0
            switch cable.direction {
            case .some(.counterClockwise): counterClockwise += 1
            case .some(.clockwise): clockwise += 1
            case .some(.twoPointZero): twoPointZero += 1
            default: break
            }
        }
    }

    /// Distinct parks among the sessions of `year` (all sessions when nil). Sessions without a park are skipped.
    public static func visitedParkCount(
        sessions: [(date: Date, parkId: String?)],
        year: Int? = nil,
        calendar: Calendar = .current
    ) -> Int {
        Set(sessions.compactMap { session -> String? in
            guard let parkId = session.parkId else { return nil }
            if let year, calendar.component(.year, from: session.date) != year { return nil }
            return parkId
        }).count
    }
}
