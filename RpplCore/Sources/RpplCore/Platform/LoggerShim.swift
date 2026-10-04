#if !canImport(OSLog)
import Foundation

// Linux (CI) has no OSLog. This is just enough of `Logger` for `WakeLog`; messages are dropped.
// Apple builds use the real OSLog and never compile this file.

struct OSLogPrivacy: Sendable {
    static let `private` = OSLogPrivacy()
    static let sensitive = OSLogPrivacy()
    static let `public` = OSLogPrivacy()
}

struct OSLogMessage: ExpressibleByStringInterpolation {
    struct StringInterpolation: StringInterpolationProtocol {
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) {}
        mutating func appendInterpolation(_ value: String, privacy: OSLogPrivacy = .private) {}
    }

    init(stringLiteral value: String) {}
    init(stringInterpolation: StringInterpolation) {}
}

struct Logger: Sendable {
    init(subsystem: String, category: String) {}
    func debug(_ message: OSLogMessage) {}
    func warning(_ message: OSLogMessage) {}
    func error(_ message: OSLogMessage) {}
}
#endif
