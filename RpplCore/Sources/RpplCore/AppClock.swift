import Foundation

/// Park opening status reads "now" from here so UI tests and release screenshots can freeze time.
/// Only the DEBUG UI-test seed sets `override`; production always uses the real clock.
public enum AppClock {
    nonisolated(unsafe) public static var override: Date?

    public static var now: Date { override ?? Date() }
}
