import Foundation

/// Assigns per-set and per-session record badges from derived stats.
public enum HighlightAssigner {
    /// Fixed display order for set badges.
    public static let setOrder: [SetHighlight] = [
        .longest, .longestTime, .shortest, .fastest, .mostLaps, .comeback, .backToBack,
    ]

    /// A "lowest" badge (shortest, coldest, laziest, …) only says something when there is a
    /// middle to be lower than; with two values it is just "the other one". For `shortest` it is
    /// also only honest once the engine can revoke a failed start that never was a set.
    static let minimumValuesForMinBadge = 3

    /// "Highest" badges need something to beat.
    static let minimumValuesForMaxBadge = 2

    // Character badges go to the record holder only when the record is worth a badge.
    // The UI never names these lines.

    /// Night owl: session ends after 21:00 (minutes since start-day midnight).
    static let nightOwlAfterMinuteOfDay = 21.0 * 60
    /// Early bird: session starts before 10:00.
    static let earlyBirdBeforeMinuteOfDay = 10.0 * 60
    /// Ice bath: water below 17 °C.
    static let iceBathBelowCelsius = 17.0
    /// Windiest: above Bft 4.
    static let windiestAboveBeaufort = 4
    /// Hottest: air above 25 °C.
    static let hottestAboveCelsius = 25.0
    /// Coldest: air below 10 °C.
    static let coldestBelowCelsius = 10.0
    /// Rain rider: real rain, not drizzle.
    static let rainiestAtLeastMmPerHour = 0.5
    /// Laziest: under a quarter of the session riding.
    static let laziestBelowRidingRatio = 0.25
    /// Highest ride %: over half of the session riding.
    static let highestRidePercentageAboveRidingRatio = 0.5
    /// Comeback: break before the set longer than 15 min.
    static let comebackAboveBreakSeconds: TimeInterval = 15 * 60
    /// Back to back: break before the set under 2 min.
    static let backToBackBelowBreakSeconds: TimeInterval = 2 * 60

    /// Fixed display order for session badges.
    public static let sessionOrder: [SessionHighlight] = [
        .longest, .mostWaterTime, .mostLaps, .highestRidePercentage, .mostCalories, .longestSetEver,
        .mostSets, .mostDistance, .topSpeed, .laziest,
        .coldest, .hottest, .windiest, .rainiest, .iceBath, .earlyBird, .nightOwl,
    ]

    public static func assignSetHighlights(_ sets: [SetSegmentStats]) -> [SetSegmentStats] {
        guard sets.count >= 2 else {
            return sets.map { clearedSet($0) }
        }

        // Ties go to the lowest set index.
        let ordered = sets.sorted { $0.index < $1.index }
        var byIndex: [Int: [SetHighlight]] = Dictionary(
            uniqueKeysWithValues: sets.map { ($0.index, []) }
        )

        if let winner = uniqueMax(ordered, value: { $0.distanceMeters }) {
            byIndex[winner.index, default: []].append(.longest)
        }

        if let durationWinner = uniqueMax(ordered, value: { $0.duration }),
           !(byIndex[durationWinner.index]?.contains(.longest) ?? false) {
            byIndex[durationWinner.index, default: []].append(.longestTime)
        }

        if let shortest = uniqueMin(ordered, value: { $0.duration }),
           !(byIndex[shortest.index]?.contains(.longest) ?? false) {
            byIndex[shortest.index, default: []].append(.shortest)
        }

        if let speedWinner = uniqueMax(ordered, value: { $0.sustainedSpeedKmh }) {
            byIndex[speedWinner.index, default: []].append(.fastest)
        }

        if let lapsWinner = uniqueMax(ordered, value: { Double($0.lapCount) }),
           lapsWinner.lapCount > 0 {
            byIndex[lapsWinner.index, default: []].append(.mostLaps)
        }

        let breaks = breaksBefore(ordered)
        if let comeback = uniqueMax(breaks, value: { $0.seconds }),
           comeback.seconds > comebackAboveBreakSeconds {
            byIndex[comeback.index, default: []].append(.comeback)
        }
        if let quick = uniqueMin(breaks, value: { $0.seconds }),
           quick.seconds < backToBackBelowBreakSeconds {
            byIndex[quick.index, default: []].append(.backToBack)
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
        func award(
            _ highlight: SessionHighlight,
            to session: SessionHighlightInput?,
            if qualifies: (SessionHighlightInput) -> Bool = { _ in true }
        ) {
            guard let session, qualifies(session) else { return }
            byId[session.id, default: []].append(highlight)
        }

        award(.longest, to: uniqueMax(sessions, value: { $0.totalDuration }))

        if let water = uniqueMax(sessions, value: { $0.ridingDuration }),
           !(byId[water.id]?.contains(.longest) ?? false) {
            award(.mostWaterTime, to: water)
        }

        award(.mostLaps, to: uniqueMax(sessions, value: { Double($0.lapCount) }))
        award(
            .highestRidePercentage,
            to: uniqueMax(sessions, value: { $0.ridingInactiveRatio }),
            if: { ($0.ridingInactiveRatio ?? 0) > highestRidePercentageAboveRidingRatio }
        )
        award(.mostCalories, to: uniqueMax(sessions, value: { $0.totalEnergyKilocalories }))
        award(.longestSetEver, to: uniqueMax(sessions, value: { $0.longestSetDistanceMeters }))
        award(.mostSets, to: uniqueMax(sessions, value: { $0.setCount.map(Double.init) }))
        award(.mostDistance, to: uniqueMax(sessions, value: { $0.totalDistanceMeters }))
        award(.topSpeed, to: uniqueMax(sessions, value: { $0.topSpeedKmh }))
        award(
            .laziest,
            to: uniqueMin(sessions, value: { $0.ridingInactiveRatio }),
            if: { ($0.ridingInactiveRatio ?? 1) < laziestBelowRidingRatio }
        )

        award(
            .coldest,
            to: uniqueMin(sessions, value: { $0.airTemperatureCelsius }),
            if: { ($0.airTemperatureCelsius ?? .infinity) < coldestBelowCelsius }
        )
        award(
            .hottest,
            to: uniqueMax(sessions, value: { $0.airTemperatureCelsius }),
            if: { ($0.airTemperatureCelsius ?? -.infinity) > hottestAboveCelsius }
        )
        award(
            .windiest,
            to: uniqueMax(sessions, value: { $0.windSpeedKmh }),
            if: { BeaufortScale.number(forKmh: $0.windSpeedKmh ?? 0) > windiestAboveBeaufort }
        )
        award(
            .rainiest,
            to: uniqueMax(sessions, value: { $0.precipitationMmPerHour }),
            if: { ($0.precipitationMmPerHour ?? 0) >= rainiestAtLeastMmPerHour }
        )
        award(
            .iceBath,
            to: uniqueMin(sessions, value: { $0.waterTemperatureCelsius }),
            if: { ($0.waterTemperatureCelsius ?? .infinity) < iceBathBelowCelsius }
        )
        award(
            .earlyBird,
            to: uniqueMin(sessions, value: { $0.startMinuteOfDay }),
            if: { ($0.startMinuteOfDay ?? .infinity) < earlyBirdBeforeMinuteOfDay }
        )
        award(
            .nightOwl,
            to: uniqueMax(sessions, value: { $0.endMinuteOfDay }),
            if: { ($0.endMinuteOfDay ?? -.infinity) > nightOwlAfterMinuteOfDay }
        )

        return byId
            .mapValues { raw in sessionOrder.filter { raw.contains($0) } }
            .filter { !$0.value.isEmpty }
    }

    // MARK: - Helpers

    private struct SetBreak {
        var index: Int
        var seconds: TimeInterval
    }

    /// Rest before each set after the first, from the previous set's end to this set's start.
    private static func breaksBefore(_ ordered: [SetSegmentStats]) -> [SetBreak] {
        zip(ordered, ordered.dropFirst()).map { previous, set in
            SetBreak(index: set.index, seconds: max(0, set.startedAt.timeIntervalSince(previous.endedAt)))
        }
    }

    private static func clearedSet(_ set: SetSegmentStats) -> SetSegmentStats {
        var copy = set
        copy.highlights = []
        return copy
    }

    /// Unique max among items with a value; ties → first in order. Nil when fewer than
    /// `minimumValuesForMaxBadge` values or all equal.
    private static func uniqueMax<T>(_ items: [T], value: (T) -> Double?) -> T? {
        uniqueExtreme(items, minimumCount: minimumValuesForMaxBadge, value: value, isBetter: >)
    }

    /// Unique min among items with a value; ties → first in order. Nil when fewer than
    /// `minimumValuesForMinBadge` values or all equal.
    private static func uniqueMin<T>(_ items: [T], value: (T) -> Double?) -> T? {
        uniqueExtreme(items, minimumCount: minimumValuesForMinBadge, value: value, isBetter: <)
    }

    private static func uniqueExtreme<T>(
        _ items: [T],
        minimumCount: Int,
        value: (T) -> Double?,
        isBetter: (Double, Double) -> Bool
    ) -> T? {
        let scored = items.compactMap { item -> (T, Double)? in
            guard let scoredValue = value(item) else { return nil }
            return (item, scoredValue)
        }
        guard scored.count >= minimumCount, let first = scored.first else { return nil }
        if scored.allSatisfy({ $0.1 == first.1 }) { return nil }
        return scored.reduce(first) { best, next in isBetter(next.1, best.1) ? next : best }.0
    }
}
