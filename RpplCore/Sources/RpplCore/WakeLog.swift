import Foundation
import OSLog

/// Shared action/debug logging for Watch + iPhone.
///
/// Uses `Logger.debug` / `Logger.error` so Console.app can filter by subsystem
/// `nl.dcsbl.rppl`. In DEBUG builds also `print`s so Xcode’s debug console
/// always shows lines without enabling “Include Debug Messages”.
///
/// Do **not** log high-frequency sensor samples (GPS / 25 Hz motion / HR ticks).
public enum WakeLog {
    public static let subsystem = "nl.dcsbl.rppl"

    public enum Category: String, Sendable {
        case session
        case detection
        case intent
        case sync
        case transfer
        case ack
        case permissions
        case ui
        case lifecycle
        case store
        case workout
        case water
    }

    public enum Privacy: Sendable {
        case `private`
        case sensitive
        case `public`
    }

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static func debug(
        _ category: Category,
        _ message: @autoclosure () -> String,
        privacy: Privacy = .private
    ) {
        let text = message()
        switch privacy {
        case .private:
            logger(category).debug("\(text, privacy: .private)")
        case .sensitive:
            logger(category).debug("\(text, privacy: .sensitive)")
        case .public:
            logger(category).debug("\(text, privacy: .public)")
        }
        #if DEBUG
        print("[Wake/\(category.rawValue)] \(text)")
        #endif
    }

    /// Non-fatal but noteworthy: fell back to a default, skipped a step, got an unexpected but
    /// survivable response. Shows up in the debug log screen alongside `error`.
    public static func warning(
        _ category: Category,
        _ message: @autoclosure () -> String,
        privacy: Privacy = .private
    ) {
        let text = message()
        switch privacy {
        case .private:
            logger(category).warning("\(text, privacy: .private)")
        case .sensitive:
            logger(category).warning("\(text, privacy: .sensitive)")
        case .public:
            logger(category).warning("\(text, privacy: .public)")
        }
        #if DEBUG
        print("[Wake/\(category.rawValue)] WARN \(text)")
        #endif
        History.shared.record(level: .warning, category: category, message: text)
    }

    public static func error(
        _ category: Category,
        _ message: @autoclosure () -> String,
        privacy: Privacy = .private
    ) {
        let text = message()
        switch privacy {
        case .private:
            logger(category).error("\(text, privacy: .private)")
        case .sensitive:
            logger(category).error("\(text, privacy: .sensitive)")
        case .public:
            logger(category).error("\(text, privacy: .public)")
        }
        #if DEBUG
        print("[Wake/\(category.rawValue)] ERROR \(text)")
        #endif
        History.shared.record(level: .error, category: category, message: text)
    }

    /// One entry in the in-memory warning/failure history behind the debug log screen. Deliberately
    /// self-contained (timestamp + category + level baked into `formatted`) since it's read far from
    /// the call site that produced it.
    public struct Entry: Identifiable, Sendable {
        public enum Level: String, Sendable {
            case warning = "WARN"
            case error = "FAIL"
        }

        public let id = UUID()
        public let date: Date
        public let level: Level
        public let category: Category
        public let message: String

        public var formatted: String {
            "\(Self.timeFormatter.string(from: date)) · \(category.rawValue) · \(level.rawValue) · \(message)"
        }

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }

    /// Last `capacity` warning/error entries, in `RpplCore` so both apps (and a shared debug view)
    /// can read it without duplicating a ring buffer. Deliberately excludes `debug` — this is for
    /// "what went wrong", not full tracing.
    private final class History: @unchecked Sendable {
        static let shared = History()
        private let capacity = 200
        private let lock = NSLock()
        private var entries: [Entry] = []

        func record(level: Entry.Level, category: Category, message: String) {
            let entry = Entry(date: Date(), level: level, category: category, message: message)
            lock.lock()
            entries.append(entry)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
            lock.unlock()
        }

        func snapshot() -> [Entry] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        func clear() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    /// Newest first. Debug screen only.
    public static func recentEntries() -> [Entry] {
        Array(History.shared.snapshot().reversed())
    }

    /// Debug screen only.
    public static func clearHistory() {
        History.shared.clear()
    }
}
