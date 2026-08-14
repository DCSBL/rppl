import Foundation
import OSLog

/// Shared action/debug logging for Watch + iPhone.
///
/// Uses `Logger.debug` / `Logger.error` so Console.app can filter by subsystem
/// `nl.dcsbl.dev.rppl`. In DEBUG builds also `print`s so Xcode’s debug console
/// always shows lines without enabling “Include Debug Messages”.
///
/// Do **not** log high-frequency sensor samples (GPS / 25 Hz motion / HR ticks).
public enum WakeLog {
    public static let subsystem = "nl.dcsbl.dev.rppl"

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

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        logger(category).debug("\(text, privacy: .public)")
        #if DEBUG
        print("[Wake/\(category.rawValue)] \(text)")
        #endif
    }

    public static func error(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        logger(category).error("\(text, privacy: .public)")
        #if DEBUG
        print("[Wake/\(category.rawValue)] ERROR \(text)")
        #endif
    }
}
