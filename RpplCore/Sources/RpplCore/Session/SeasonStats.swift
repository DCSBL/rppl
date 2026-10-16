import Foundation

/// One session's numbers for the logbook totals and season charts. Missing values are nil or 0.
public struct SeasonSession: Equatable, Sendable {
    public var date: Date
    public var distanceMeters: Double
    public var duration: TimeInterval
    public var ridingDuration: TimeInterval
    public var sets: Int?
    public var laps: Int?
    public var kilocalories: Double?
    public var topSpeedKmh: Double?
    /// Most common riding speed of the session (`SessionStats.cableSpeedKmh`).
    public var typicalSpeedKmh: Double?
    public var airCelsius: Double?
    public var waterCelsius: Double?

    public init(
        date: Date,
        distanceMeters: Double = 0,
        duration: TimeInterval = 0,
        ridingDuration: TimeInterval = 0,
        sets: Int? = nil,
        laps: Int? = nil,
        kilocalories: Double? = nil,
        topSpeedKmh: Double? = nil,
        typicalSpeedKmh: Double? = nil,
        airCelsius: Double? = nil,
        waterCelsius: Double? = nil
    ) {
        self.date = date
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.ridingDuration = ridingDuration
        self.sets = sets
        self.laps = laps
        self.kilocalories = kilocalories
        self.topSpeedKmh = topSpeedKmh
        self.typicalSpeedKmh = typicalSpeedKmh
        self.airCelsius = airCelsius
        self.waterCelsius = waterCelsius
    }
}

/// Logbook totals plus the series behind the season charts. Pure; the view only formats and draws.
public struct SeasonStats: Equatable, Sendable {
    /// Charts stay hidden until the logbook has this many sessions.
    public static let minSessionsForCharts = 5

    public struct Point: Equatable, Sendable {
        public var date: Date
        public var value: Double
    }

    public struct Day: Equatable, Sendable {
        public var start: Date
        public var airCelsius: Double?
        public var waterCelsius: Double?
    }

    public let sessionCount: Int
    public let totalDistanceMeters: Double
    public let totalDuration: TimeInterval
    public let totalRidingDuration: TimeInterval
    public let totalSets: Int
    public let totalLaps: Int
    public let topSpeedKmh: Double?
    /// Most common session cable speed across the logbook; ties go to the faster one.
    public let typicalSpeedKmh: Double?
    /// One point per session that has the value, oldest first. Sessions without it are skipped, not zero.
    public let distanceMeters: [Point]
    public let duration: [Point]
    public let laps: [Point]
    public let kilocalories: [Point]
    /// Per-day averages (sessions of one calendar day merged), oldest first. Days with no temperature are skipped.
    public let days: [Day]

    public var showsCharts: Bool { sessionCount >= Self.minSessionsForCharts }

    public init(sessions: [SeasonSession], calendar: Calendar = .current) {
        let sorted = sessions.sorted { $0.date < $1.date }
        func series(_ value: (SeasonSession) -> Double?) -> [Point] {
            sorted.compactMap { session in
                guard let v = value(session), v > 0 else { return nil }
                return Point(date: session.date, value: v)
            }
        }
        sessionCount = sorted.count
        totalDistanceMeters = sorted.reduce(0) { $0 + $1.distanceMeters }
        totalDuration = sorted.reduce(0) { $0 + $1.duration }
        totalRidingDuration = sorted.reduce(0) { $0 + $1.ridingDuration }
        totalSets = sorted.reduce(0) { $0 + ($1.sets ?? 0) }
        totalLaps = sorted.reduce(0) { $0 + ($1.laps ?? 0) }
        topSpeedKmh = sorted.compactMap(\.topSpeedKmh).max()
        typicalSpeedKmh = Self.mode(sorted.compactMap(\.typicalSpeedKmh))
        distanceMeters = series(\.distanceMeters)
        duration = series(\.duration)
        laps = series { $0.laps.map(Double.init) }
        kilocalories = series(\.kilocalories)

        var buckets: [Date: [SeasonSession]] = [:]
        for session in sorted {
            buckets[calendar.startOfDay(for: session.date), default: []].append(session)
        }
        days = buckets.keys.sorted().compactMap { start in
            let group = buckets[start] ?? []
            let air = Self.mean(group.compactMap(\.airCelsius))
            let water = Self.mean(group.compactMap(\.waterCelsius))
            return air == nil && water == nil ? nil : Day(start: start, airCelsius: air, waterCelsius: water)
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func mode(_ values: [Double]) -> Double? {
        let counts = values.reduce(into: [Double: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

/// Easter egg: the "Max speed" total cycles to "Average speed" (really the most common speed).
public enum SpeedTotal: String, CaseIterable, Sendable {
    case max
    case typical
}

/// Easter egg: the "Distance" total cycles to total time and total riding time.
public enum DistanceTotal: String, CaseIterable, Sendable {
    case distance
    case duration
    case riding
}

/// Easter egg: the "Sessions" total cycles to total sets and total laps.
public enum CountTotal: String, CaseIterable, Sendable {
    case sessions
    case sets
    case laps
}

extension CaseIterable where Self: Equatable {
    /// The next case, wrapping around.
    public func cycled() -> Self {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return self }
        return all[(index + 1) % all.count]
    }
}
