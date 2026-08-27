import Foundation

/// Input row for cross-session record badges.
public struct SessionHighlightInput: Equatable, Sendable {
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

/// Assigns per-ride and per-session record badges from derived stats.
public enum HighlightAssigner {
    /// Fixed display order for ride badges.
    public static let rideOrder: [RideHighlight] = [.longest, .longestTime, .fastest]

    /// Fixed display order for session badges.
    public static let sessionOrder: [SessionHighlight] = [.longest, .mostWaterTime, .mostLaps]

    public static func assignRideHighlights(_ rides: [RideSegmentStats]) -> [RideSegmentStats] {
        guard rides.count >= 2 else {
            return rides.map { clearedRide($0) }
        }

        var byIndex: [Int: [RideHighlight]] = Dictionary(
            uniqueKeysWithValues: rides.map { ($0.index, []) }
        )

        if let winner = uniqueMaxRide(rides, value: { $0.distanceMeters }) {
            byIndex[winner.index, default: []].append(.longest)
        }

        if let durationWinner = uniqueMaxRide(rides, value: { $0.duration }),
           !(byIndex[durationWinner.index]?.contains(.longest) ?? false) {
            byIndex[durationWinner.index, default: []].append(.longestTime)
        }

        if let speedWinner = uniqueMaxRide(rides, value: { $0.sustainedSpeedKmh }) {
            byIndex[speedWinner.index, default: []].append(.fastest)
        }

        return rides.map { ride in
            var copy = ride
            let raw = byIndex[ride.index] ?? []
            copy.highlights = rideOrder.filter { raw.contains($0) }
            return copy
        }
    }

    public static func assignSessionHighlights(
        _ sessions: [SessionHighlightInput]
    ) -> [String: [SessionHighlight]] {
        guard sessions.count >= 2 else { return [:] }

        var byId: [String: [SessionHighlight]] = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, []) }
        )

        if let longest = uniqueMaxSession(sessions, value: \.totalDuration) {
            byId[longest.id, default: []].append(.longest)
        }

        if let water = uniqueMaxSession(sessions, value: \.ridingDuration),
           !(byId[water.id]?.contains(.longest) ?? false) {
            byId[water.id, default: []].append(.mostWaterTime)
        }

        if let laps = uniqueMaxSession(sessions, value: \.lapCount) {
            byId[laps.id, default: []].append(.mostLaps)
        }

        return byId
            .mapValues { raw in sessionOrder.filter { raw.contains($0) } }
            .filter { !$0.value.isEmpty }
    }

    // MARK: - Helpers

    private static func clearedRide(_ ride: RideSegmentStats) -> RideSegmentStats {
        var copy = ride
        copy.highlights = []
        return copy
    }

    /// Unique max among comparable values; ties → lowest ride index. Nil when all equal or empty.
    private static func uniqueMaxRide(
        _ rides: [RideSegmentStats],
        value: (RideSegmentStats) -> Double?
    ) -> RideSegmentStats? {
        let scored = rides.compactMap { ride -> (RideSegmentStats, Double)? in
            guard let scoredValue = value(ride) else { return nil }
            return (ride, scoredValue)
        }
        guard scored.count >= 2 else { return nil }
        guard let best = scored.map(\.1).max() else { return nil }
        if scored.allSatisfy({ $0.1 == best }) { return nil }
        return scored
            .filter { $0.1 == best }
            .map(\.0)
            .min(by: { $0.index < $1.index })
    }

    private static func uniqueMaxRide(
        _ rides: [RideSegmentStats],
        value: (RideSegmentStats) -> Double
    ) -> RideSegmentStats? {
        uniqueMaxRide(rides, value: { Optional(value($0)) })
    }

    private static func uniqueMaxSession<T: Comparable>(
        _ sessions: [SessionHighlightInput],
        value: KeyPath<SessionHighlightInput, T>
    ) -> SessionHighlightInput? {
        guard let best = sessions.map({ $0[keyPath: value] }).max() else { return nil }
        let winners = sessions.filter { $0[keyPath: value] == best }
        guard winners.count < sessions.count else { return nil }
        return winners.first
    }
}
