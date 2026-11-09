import Foundation

/// A session being tracked live on the iPhone (no Watch): start, park and the "next set" taps. Set 1 starts
/// with the session. Written to disk on every change (`LiveSessionFile`) so a force quit loses nothing, and
/// turned into a manual session (`ManualEntry`) when it ends. Never touches HealthKit.
public struct LiveSession: Codable, Equatable, Sendable {
    /// No tap for this long asks "is your session still running?".
    public static let stillRunningAfter: TimeInterval = 2 * 3_600
    /// A session shorter than this without a second set can be thrown away on stop.
    public static let discardableBelow: TimeInterval = 30
    /// Taps closer together than this count once (a double tap).
    public static let tapDebounce: TimeInterval = 1

    public var id: String
    public var startedAt: Date
    public var parkId: String?
    /// Own spot, when no park is picked.
    public var spot: ParkCoordinate?
    public var spotName: String?
    public var setStarts: [Date]
    /// Last start, tap or "keep going". The end of an orphaned session.
    public var lastActivityAt: Date

    public init(
        id: String = UUID().uuidString, startedAt: Date,
        parkId: String? = nil, spot: ParkCoordinate? = nil, spotName: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.parkId = parkId
        self.spot = spot
        self.spotName = spotName
        setStarts = [startedAt]
        lastActivityAt = startedAt
    }

    public var setCount: Int { setStarts.count }
    public var currentSetStart: Date { setStarts.last ?? startedAt }
    public var stillRunningCheckAt: Date { lastActivityAt.addingTimeInterval(Self.stillRunningAfter) }

    /// Starts the next set. Returns false when ignored: a double tap.
    @discardableResult
    public mutating func nextSet(at now: Date) -> Bool {
        if now.timeIntervalSince(currentSetStart) < Self.tapDebounce { return false }
        setStarts.append(max(now, startedAt))
        lastActivityAt = now
        return true
    }

    /// "Keep going" after the still-running question or a relaunch.
    public mutating func touch(at now: Date) { lastActivityAt = now }

    public func isDiscardable(at now: Date) -> Bool {
        setCount <= 1 && now.timeIntervalSince(startedAt) < Self.discardableBelow
    }

    /// The manual session this becomes. Without a second set tap only the duration is known, so the set
    /// count stays unknown, as for a typed-in session.
    public func entry(location: ParkCoordinate?) -> ManualEntry {
        guard setCount > 1 else { return ManualEntry(location: location ?? spot) }
        return ManualEntry(tallies: [.init(sets: setCount)], location: location ?? spot, setStarts: setStarts)
    }
}

/// Where the running `LiveSession` lives between launches: one small JSON file.
public struct LiveSessionFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> LiveSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(LiveSession.self, from: data)
    }

    public func save(_ session: LiveSession) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(session).write(to: url, options: .atomic)
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
