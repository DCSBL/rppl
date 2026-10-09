import Foundation

/// A session typed in by hand: no sensor streams, so these counts are the source of truth for its
/// derived stats (`SessionStatsBuilder`). Tracked sessions leave `SessionManifest.manual` nil.
public struct ManualEntry: Codable, Equatable, Sendable {
    public struct Tally: Codable, Equatable, Sendable {
        /// Nil = not known (a session logged long after the fact); distinct from a real 0.
        public var sets: Int?
        public var laps: Int?

        public init(sets: Int? = nil, laps: Int? = nil) {
            self.sets = sets
            self.laps = laps
        }
    }

    /// One per cable of the park (index = cable position); a single entry for an own or no location.
    public var tallies: [Tally]
    /// Estimated distance (laps x lap length); nil when a ridden cable has no known length.
    public var distanceM: Double?
    /// Park pin or picked spot. Centers the derived map frame, so park matching and visits work.
    public var location: ParkCoordinate?

    public init(tallies: [Tally] = [Tally()], distanceM: Double? = nil, location: ParkCoordinate? = nil) {
        self.tallies = tallies
        self.distanceM = distanceM
        self.location = location
    }

    /// Sum of the known sets; nil when no cable has a known value.
    public var setCount: Int? { Self.sum(tallies.map(\.sets)) }
    /// Sum of the known laps; nil when no cable has a known value.
    public var lapCount: Int? { Self.sum(tallies.map(\.laps)) }

    private static func sum(_ values: [Int?]) -> Int? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// `laps x lap length` per ridden cable, tallies matched to cables by index. Nil when a ridden
    /// cable has no known length, or nothing was ridden.
    public static func distanceM(tallies: [Tally], cables: [ParkCable]) -> Double? {
        var total = 0.0
        for (index, tally) in tallies.enumerated() where (tally.laps ?? 0) > 0 {
            guard cables.indices.contains(index), let lap = cables[index].lapLengthM else { return nil }
            total += Double(tally.laps ?? 0) * lap
        }
        return total > 0 ? total : nil
    }
}

extension ParkCable {
    /// Distance of one lap: a loop cable is its length, a 2.0 cable is ridden there and back.
    public var lapLengthM: Double? {
        effectiveLengthM.map { direction == ParkCableDirection.twoPointZero ? $0 * 2 : $0 }
    }
}

/// Start / end rules for a hand-entered session.
public enum ManualTimeRange {
    /// Longer than this asks for confirmation before saving (still always allowed).
    public static let longThreshold: TimeInterval = 12 * 3_600

    /// End before start: cannot be stored.
    public static func isReversed(start: Date, end: Date) -> Bool { end < start }

    public static func isLong(start: Date, end: Date) -> Bool {
        end.timeIntervalSince(start) > longThreshold
    }

    /// `other` moved onto the calendar day of `anchor`, time of day kept, never past `now`.
    public static func moved(
        _ other: Date, toDayOf anchor: Date, now: Date, calendar: Calendar = .current
    ) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: anchor)
        let time = calendar.dateComponents([.hour, .minute], from: other)
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = time.hour
        parts.minute = time.minute
        return min(calendar.date(from: parts) ?? other, now)
    }
}
