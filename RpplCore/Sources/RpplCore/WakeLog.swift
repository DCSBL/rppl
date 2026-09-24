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

    public enum Privacy {
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
    }
}
