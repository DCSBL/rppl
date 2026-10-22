import Foundation

/// What the app remembers about its last attempts to update park data. Local only.
public struct ParkDataUpdateState: Codable, Equatable, Sendable {
    /// Last time the rider (or the daily check) asked, real or faked.
    public var lastAttempt: Date?
    /// The last attempt was a faked refresh (a manual refresh right after a real, successful one).
    public var lastAttemptWasFake = false
    /// The last real network attempt succeeded.
    public var lastRealAttemptSucceeded = false
    /// When the last real attempt succeeded.
    public var lastSuccess: Date?
    /// Technical reason of the last failed real attempt, for the debug log.
    public var lastError: String?
    /// Fixed per installation, 0..<1: where in the day the daily check happens.
    public var dailyOffsetFraction: Double?

    public init() {}
}

/// Pure timing rules for park data refreshes, so they can be tested without a clock or a network.
public enum ParkDataRefreshPolicy {
    /// A manual refresh takes at least this long, so the spinner never just blinks.
    public static let minimumRefreshDuration: TimeInterval = 1
    /// A manual refresh within this window after a successful real one is faked.
    public static let manualCooldown: TimeInterval = 60
    public static let fakeDurationRange: ClosedRange<TimeInterval> = 1...3
    public static let dailyInterval: TimeInterval = 24 * 60 * 60
    /// How long a refresh error stays visible at the spinner.
    public static let errorDisplayDuration: TimeInterval = 5

    /// Fake only when the previous real attempt succeeded and was less than a minute ago.
    public static func shouldFakeManualRefresh(state: ParkDataUpdateState, now: Date) -> Bool {
        guard state.lastRealAttemptSucceeded, let last = state.lastSuccess else { return false }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= 0 && elapsed < manualCooldown
    }

    /// The in-app check at most once a day, for riders without a park widget (no background refresh).
    public static func isDailyCheckDue(state: ParkDataUpdateState, now: Date) -> Bool {
        guard let last = state.lastSuccess else { return true }
        return now.timeIntervalSince(last) >= dailyInterval || now < last
    }

    /// Next background check: the installation's fixed moment of the day, at least `minimumGap`
    /// from now, so installations spread out over 24 hours instead of all hitting GitHub at once.
    public static func nextDailyCheck(
        after now: Date,
        offsetFraction: Double,
        calendar: Calendar = .current,
        minimumGap: TimeInterval = 60 * 60
    ) -> Date {
        let clamped = min(max(offsetFraction, 0), 0.999_999)
        let startOfDay = calendar.startOfDay(for: now)
        var candidate = startOfDay.addingTimeInterval(clamped * dailyInterval)
        while candidate < now.addingTimeInterval(minimumGap) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(dailyInterval)
        }
        return candidate
    }
}

/// "21 hours ago" style age, split from the formatting so the buckets are testable.
public enum ParkDataAge: Equatable, Sendable {
    case lessThanMinute
    case minutes(Int)
    case hours(Int)
    case days(Int)

    public init(from date: Date, to now: Date) {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: self = .lessThanMinute
        case ..<3600: self = .minutes(Int(seconds / 60))
        case ..<86_400: self = .hours(Int(seconds / 3600))
        default: self = .days(Int(seconds / 86_400))
        }
    }
}
