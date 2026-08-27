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
/// On Linux (CI `swift test`) OSLog is unavailable; messages go to stdout only.
///
/// Do **not** log high-frequency sensor samples (GPS / 25 Hz motion / HR ticks).
public enum WakeLog {
    public static let subsystem = "nl.dcsbl.rppl"

    public enum Category: String {
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

#if canImport(OSLog)
    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
#endif

    public static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
#if canImport(OSLog)
        logger(category).debug("\(text, privacy: .public)")
#endif
#if DEBUG || !canImport(OSLog)
        print("[Wake/\(category.rawValue)] \(text)")
#endif
    }

    public static func error(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
#if canImport(OSLog)
        logger(category).error("\(text, privacy: .public)")
#endif
#if DEBUG || !canImport(OSLog)
        print("[Wake/\(category.rawValue)] ERROR \(text)")
#endif
    }
}
