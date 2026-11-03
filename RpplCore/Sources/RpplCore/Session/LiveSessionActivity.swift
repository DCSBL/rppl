#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents
import Foundation

/// The Live Activity of a session tracked on iPhone. Shared by the app (starts and updates it) and the
/// widget extension (draws it). The timers run on the system (`Text(_:style: .timer)`), so the app does not
/// update it every second, only when a set starts.
public struct LiveSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var setCount: Int
        /// Start of the running set; nil before the first tap.
        public var setStartedAt: Date?
        /// Time-only sessions have no sets and no Next set button.
        public var timeOnly: Bool
        /// A session recorded on the Apple Watch: more numbers, no Next set button.
        public var watch: WatchNumbers?

        public struct WatchNumbers: Codable, Hashable, Sendable {
            public var speedKmh: Double?
            public var heartRate: Double?
            public var waterCelsius: Double?
            public var lapCount: Int
        }

        public init(setCount: Int, setStartedAt: Date?, timeOnly: Bool, watch: WatchNumbers? = nil) {
            self.setCount = setCount
            self.setStartedAt = setStartedAt
            self.timeOnly = timeOnly
            self.watch = watch
        }

        public init(_ snapshot: WatchLiveSnapshot) {
            self.init(
                setCount: snapshot.setCount, setStartedAt: snapshot.setStartedAt, timeOnly: false,
                watch: WatchNumbers(
                    speedKmh: snapshot.speedKmh, heartRate: snapshot.heartRate,
                    waterCelsius: snapshot.waterCelsius, lapCount: snapshot.lapCount
                )
            )
        }

        public init(_ session: LiveSession) {
            self.init(setCount: session.setCount, setStartedAt: session.currentSetStart, timeOnly: session.mode == .timeOnly)
        }
    }

    public var startedAt: Date
    public var parkName: String?

    public init(startedAt: Date, parkName: String?) {
        self.startedAt = startedAt
        self.parkName = parkName
    }
}

/// "Next set" on the lock screen or in the Dynamic Island. Runs in the app process; the app sets `handler`.
public struct NextSetIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Next set"
    nonisolated(unsafe) public static var handler: (@MainActor @Sendable () -> Void)?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
#endif
