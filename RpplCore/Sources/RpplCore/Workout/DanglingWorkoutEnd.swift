import Foundation

/// When to end a Health workout that a crash left dangling.
///
/// The workout ends where the Rppl data ends, not when the app happened to be reopened: after a
/// late relaunch (crash loop, relaunch suppressed, rider opens the app hours later) ending at
/// "now" would stretch the Fitness workout over a gap with made-up duration and energy.
public enum DanglingWorkoutEnd {
    /// - Parameters:
    ///   - orphanLastSample: latest timestamp of the orphaned Rppl session; nil when none was found.
    ///   - hkStart: start of the dangling HK session, when known.
    ///   - now: the current time.
    public static func date(orphanLastSample: Date?, hkStart: Date?, now: Date) -> Date {
        guard var end = orphanLastSample else { return now }
        if let hkStart, end < hkStart {
            end = hkStart
        }
        return min(end, now)
    }
}
