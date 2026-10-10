import Foundation

/// The first Stop tap, while the "End session?" confirmation is still open.
///
/// Recording keeps running so that dismissing the confirmation changes nothing. Confirming ends
/// the session at the moment of the first tap, not after however long the dialog stayed open.
public enum PendingStop {
    /// Seconds between attention haptics while the confirmation stays open.
    public static let reminderInterval: TimeInterval = 60

    /// End of the session once the stop is confirmed.
    /// - Parameters:
    ///   - requestedAt: time of the first Stop tap; nil when no stop is pending.
    ///   - sessionStart: start of the session; the end never lands before it.
    ///   - now: the current time; the end never lands after it.
    public static func endDate(requestedAt: Date?, sessionStart: Date?, now: Date) -> Date {
        guard var end = requestedAt else { return now }
        if let sessionStart, end < sessionStart {
            end = sessionStart
        }
        return min(end, now)
    }

    /// Whether another attention haptic is due.
    /// - Parameters:
    ///   - requestedAt: time of the first Stop tap.
    ///   - lastReminderAt: time of the previous reminder, nil when none was given yet.
    ///   - now: the current time.
    public static func reminderDue(requestedAt: Date, lastReminderAt: Date?, now: Date) -> Bool {
        now.timeIntervalSince(lastReminderAt ?? requestedAt) >= reminderInterval
    }
}
