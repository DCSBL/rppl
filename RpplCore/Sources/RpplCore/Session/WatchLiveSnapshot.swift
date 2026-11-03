import Foundation

/// What the Watch tells the iPhone while it records: a few numbers every few seconds over the mirrored
/// workout session (`sendToRemoteWorkoutSession`). A viewing window only: the session itself still
/// reaches the iPhone through the normal transfer, and nothing here is stored.
public struct WatchLiveSnapshot: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var sentAt: Date
    public var setCount: Int
    /// Start of the set being ridden; nil between sets.
    public var setStartedAt: Date?
    public var speedKmh: Double?
    public var heartRate: Double?
    public var waterCelsius: Double?
    /// Laps of the running set, or of the last one between sets.
    public var lapCount: Int
    public var isPaused: Bool

    public init(
        startedAt: Date, sentAt: Date, setCount: Int, setStartedAt: Date? = nil, speedKmh: Double? = nil,
        heartRate: Double? = nil, waterCelsius: Double? = nil, lapCount: Int = 0, isPaused: Bool = false
    ) {
        self.startedAt = startedAt
        self.sentAt = sentAt
        self.setCount = setCount
        self.setStartedAt = setStartedAt
        self.speedKmh = speedKmh
        self.heartRate = heartRate
        self.waterCelsius = waterCelsius
        self.lapCount = lapCount
        self.isPaused = isPaused
    }

    /// Whole-number speed and heart rate, tenths of a degree: what the dashboard shows. A new snapshot is
    /// only worth sending when this changes.
    public func showsSame(as other: WatchLiveSnapshot) -> Bool {
        startedAt == other.startedAt && setCount == other.setCount && lapCount == other.lapCount
            && isPaused == other.isPaused && (setStartedAt == nil) == (other.setStartedAt == nil)
            && speedKmh.map { $0.rounded() } == other.speedKmh.map { $0.rounded() }
            && heartRate.map { $0.rounded() } == other.heartRate.map { $0.rounded() }
            && waterCelsius.map { ($0 * 10).rounded() } == other.waterCelsius.map { ($0 * 10).rounded() }
    }

    /// Older than this and the numbers are no longer "live".
    public static let staleAfter: TimeInterval = 30

    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(sentAt) > Self.staleAfter }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// Nil for anything unreadable: the sender may be a newer build.
    public static func decode(_ data: Data) -> WatchLiveSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WatchLiveSnapshot.self, from: data)
    }
}
