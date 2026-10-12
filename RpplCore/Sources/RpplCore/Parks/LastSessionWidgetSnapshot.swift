import Foundation

/// The newest logbook session, as the last session widget shows it. The widget extension cannot
/// read the logbook, so the app writes this small snapshot to the App Group (like `ParkWidgetSnapshot`).
public struct LastSessionWidgetSnapshot: Codable, Equatable, Sendable {
    public var sessionId: String
    /// Park short name or city; nil when the session has no place yet.
    public var place: String?
    public var startedAt: Date
    public var endedAt: Date
    /// Nil for a manual session: typed-in sessions have no measured time.
    public var duration: TimeInterval?
    /// Share of the session spent riding (0...1). Nil for a manual session.
    public var ridingRatio: Double?
    /// Time spent riding / inactive (as the session detail's Riding tile). Nil for a manual session
    /// and for snapshots written before these fields existed.
    public var ridingDuration: TimeInterval?
    public var inactiveDuration: TimeInterval?
    /// Nil when the rider did not fill it in (manual).
    public var setCount: Int?
    public var lapCount: Int?
    /// Every set as a fraction of the session (`MetricDisplay.span`), for the timeline bar.
    public var setSpans: [ClosedRange<Double>]

    public init(
        sessionId: String,
        place: String?,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval?,
        ridingRatio: Double?,
        ridingDuration: TimeInterval? = nil,
        inactiveDuration: TimeInterval? = nil,
        setCount: Int?,
        lapCount: Int?,
        setSpans: [ClosedRange<Double>]
    ) {
        self.sessionId = sessionId
        self.place = place
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.ridingRatio = ridingRatio
        self.ridingDuration = ridingDuration
        self.inactiveDuration = inactiveDuration
        self.setCount = setCount
        self.lapCount = lapCount
        self.setSpans = setSpans
    }

    public init(manifest: SessionManifest, stats: SessionStats, place: String?) {
        let isManual = manifest.manual != nil
        self.init(
            sessionId: manifest.sessionId,
            place: place,
            startedAt: stats.startedAt,
            endedAt: stats.endedAt,
            duration: isManual ? nil : stats.totalDuration,
            ridingRatio: isManual ? nil : stats.ridingInactiveRatio,
            ridingDuration: isManual ? nil : stats.ridingDuration,
            inactiveDuration: isManual ? nil : stats.inactiveDuration,
            setCount: stats.knownSetCount,
            lapCount: stats.knownLapCount,
            setSpans: isManual ? [] : stats.sets.map {
                MetricDisplay.span(from: $0.startedAt, to: $0.endedAt, inRangeFrom: stats.startedAt, to: stats.endedAt)
            }
        )
    }
}

public enum LastSessionWidgetStore {
    static let key = "nl.dcsbl.rppl.lastSessionWidgetSnapshot"

    /// Nil when nothing was written yet or the stored data is unreadable.
    public static func load(from defaults: UserDefaults = ParkWidgetSnapshotStore.shared) -> LastSessionWidgetSnapshot? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LastSessionWidgetSnapshot.self, from: $0) }
    }

    /// Returns `true` only when the stored snapshot changed, so callers reload widget timelines only then.
    @discardableResult
    public static func save(
        _ snapshot: LastSessionWidgetSnapshot,
        in defaults: UserDefaults = ParkWidgetSnapshotStore.shared
    ) -> Bool {
        guard load(from: defaults) != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// `rppl://session/<id>`: the widget opens that session's detail in the logbook.
public enum SessionDeepLink {
    private static let host = "session"

    public static func url(forSessionID id: String) -> URL? {
        var components = URLComponents()
        components.scheme = ParkDeepLink.scheme
        components.host = host
        components.path = "/" + id
        return components.url
    }

    public static func sessionID(from url: URL) -> String? {
        guard url.scheme == ParkDeepLink.scheme, url.host == host else { return nil }
        let id = url.path.split(separator: "/").first.map(String.init)
        return (id?.isEmpty ?? true) ? nil : id
    }
}
