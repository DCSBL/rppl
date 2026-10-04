import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Shared action/debug logging for Watch + iPhone.
///
/// Uses `Logger.debug` / `Logger.error` so Console.app can filter by subsystem
/// `nl.dcsbl.rppl`. In DEBUG builds also `print`s so Xcode’s debug console
/// always shows lines without enabling “Include Debug Messages”.
///
/// Do **not** log high-frequency sensor samples (GPS / 25 Hz motion / HR ticks).
public enum WakeLog {
    public static let subsystem = "nl.dcsbl.rppl"

    public enum Category: String, Sendable, Codable {
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
    public struct Entry: Identifiable, Sendable, Codable {
        public enum Level: String, Sendable, Codable {
            case warning = "WARN"
            case error = "FAIL"
        }

        private enum CodingKeys: String, CodingKey { case date, level, category, message }

        public let id = UUID()
        public let date: Date
        public let level: Level
        public let category: Category
        public let message: String

        public var formatted: String {
            "\(Self.timeFormatter.string(from: date)) · \(category.rawValue) · \(level.rawValue) · \(message)"
        }

        /// Full timestamp for the exported log; history now spans app restarts, so time alone is ambiguous.
        public var formattedWithDate: String {
            "\(date.formatted(.iso8601)) · \(category.rawValue) · \(level.rawValue) · \(message)"
        }

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }

    /// Entries kept (and persisted, when enabled) across app restarts.
    public static let historyCapacity = 100

    /// Last `historyCapacity` warning/error entries, in `RpplCore` so both apps (and a shared debug
    /// view) can read it without duplicating a ring buffer. Deliberately excludes `debug` — this is
    /// for "what went wrong", not full tracing. Persisted to a JSON file once `enablePersistence`
    /// is called; without it the history stays in memory only (tests, Watch).
    private final class History: @unchecked Sendable {
        static let shared = History()
        private let capacity = WakeLog.historyCapacity
        private let lock = NSLock()
        private var entries: [Entry] = []
        private var fileURL: URL?

        func enablePersistence(at url: URL) {
            lock.lock()
            defer { lock.unlock() }
            fileURL = url
            if let data = try? Data(contentsOf: url),
               let stored = try? JSONDecoder().decode([Entry].self, from: data) {
                // Anything logged before persistence was enabled is newer than the stored entries.
                entries = Array((stored + entries).suffix(capacity))
            }
        }

        func disablePersistence() {
            lock.lock()
            fileURL = nil
            lock.unlock()
        }

        func record(level: Entry.Level, category: Category, message: String) {
            let entry = Entry(date: Date(), level: level, category: category, message: message)
            lock.lock()
            entries.append(entry)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
            save()
            lock.unlock()
        }

        /// Caller holds `lock`. Failure is ignored: logging must never throw or recurse into `WakeLog`.
        private func save() {
            guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }

        func snapshot() -> [Entry] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        func clear() {
            lock.lock()
            entries.removeAll()
            save()
            lock.unlock()
        }
    }

    /// Loads the persisted history from `url` and keeps writing it there. Call once at app launch.
    public static func enablePersistence(at url: URL) {
        History.shared.enablePersistence(at: url)
    }

    static func disablePersistenceForTesting() {
        History.shared.disablePersistence()
    }

    /// Default location for the persisted history: Application Support, next to other app data.
    public static var defaultHistoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("wakelog-history.json")
    }

    /// Plain-text log, oldest first, one entry per line. Raw text on purpose: exported files and mail
    /// bodies are read by humans, so no base64 / structured format.
    public static func exportText() -> String {
        History.shared.snapshot().map(\.formattedWithDate).joined(separator: "\n") + "\n"
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
