import Foundation

/// Assigns per-set and per-session record badges from derived stats.
public enum HighlightAssigner {
    /// Fixed display order for set badges.
    public static let setOrder: [SetHighlight] = [.longest, .longestTime, .fastest]

    /// Fixed display order for session badges.
    public static let sessionOrder: [SessionHighlight] = [.longest, .mostWaterTime, .mostLaps]

    public static func assignSetHighlights(_ sets: [SetSegmentStats]) -> [SetSegmentStats] {
        guard sets.count >= 2 else {
            return sets.map { clearedSet($0) }
        }

        var byIndex: [Int: [SetHighlight]] = Dictionary(
            uniqueKeysWithValues: sets.map { ($0.index, []) }
        )

        if let winner = uniqueMaxSet(sets, value: { $0.distanceMeters }) {
            byIndex[winner.index, default: []].append(.longest)
        }

        if let durationWinner = uniqueMaxSet(sets, value: { $0.duration }),
           !(byIndex[durationWinner.index]?.contains(.longest) ?? false) {
            byIndex[durationWinner.index, default: []].append(.longestTime)
        }

        if let speedWinner = uniqueMaxSet(sets, value: { $0.sustainedSpeedKmh }) {
            byIndex[speedWinner.index, default: []].append(.fastest)
        }

        return sets.map { set in
            var copy = set
            let raw = byIndex[set.index] ?? []
            copy.highlights = setOrder.filter { raw.contains($0) }
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

    private static func clearedSet(_ set: SetSegmentStats) -> SetSegmentStats {
        var copy = set
        copy.highlights = []
        return copy
    }

    /// Unique max among comparable values; ties → lowest set index. Nil when all equal or empty.
    private static func uniqueMaxSet(
        _ sets: [SetSegmentStats],
        value: (SetSegmentStats) -> Double?
    ) -> SetSegmentStats? {
        let scored = sets.compactMap { set -> (SetSegmentStats, Double)? in
            guard let scoredValue = value(set) else { return nil }
            return (set, scoredValue)
        }
        guard scored.count >= 2 else { return nil }
        guard let best = scored.map(\.1).max() else { return nil }
        if scored.allSatisfy({ $0.1 == best }) { return nil }
        return scored
            .filter { $0.1 == best }
            .map(\.0)
            .min(by: { $0.index < $1.index })
    }

    private static func uniqueMaxSet(
        _ sets: [SetSegmentStats],
        value: (SetSegmentStats) -> Double
    ) -> SetSegmentStats? {
        uniqueMaxSet(sets, value: { Optional(value($0)) })
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
