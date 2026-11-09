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
        /// Start of the running set.
        public var setStartedAt: Date?
        /// A session recorded on the Apple Watch: more numbers, no Next set button.
        public var watch: WatchNumbers?

        public struct WatchNumbers: Codable, Hashable, Sendable {
            public var speedKmh: Double?
            public var heartRate: Double?
            public var waterCelsius: Double?
            public var lapCount: Int
        }

        public init(setCount: Int, setStartedAt: Date?, watch: WatchNumbers? = nil) {
            self.setCount = setCount
            self.setStartedAt = setStartedAt
            self.watch = watch
        }

        public init(_ snapshot: WatchLiveSnapshot) {
            self.init(
                setCount: snapshot.setCount, setStartedAt: snapshot.setStartedAt,
                watch: WatchNumbers(
                    speedKmh: snapshot.speedKmh, heartRate: snapshot.heartRate,
                    waterCelsius: snapshot.waterCelsius, lapCount: snapshot.lapCount
                )
            )
        }

        public init(_ session: LiveSession) {
            self.init(setCount: session.setCount, setStartedAt: session.currentSetStart)
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
/// Works on a locked phone and never opens the app: a set tap with wet hands should not need Face ID.
public struct NextSetIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Next set"
    public static let openAppWhenRun = false
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    nonisolated(unsafe) public static var handler: (@MainActor @Sendable () -> Void)?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
#endif
