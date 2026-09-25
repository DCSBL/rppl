import Foundation

/// Which dates a rule or slot applies to. Every field is optional; missing means "any".
public protocol ParkDateSelector {
    /// 1–12.
    var months: [Int]? { get }
    /// `mon`…`sun`, `weekdays`, `weekend`, `daily`.
    var days: [String]? { get }
    /// Inclusive `yyyy-MM-dd` bounds, e.g. for a seasonal change of hours.
    var from: String? { get }
    var until: String? { get }
    /// Explicit `yyyy-MM-dd` dates (holidays, special days).
    var dates: [String]? { get }
}

public struct ParkOpeningRule: Codable, Equatable, Sendable, ParkDateSelector {
    public var label: String?
    public var months: [Int]?
    public var days: [String]?
    public var from: String?
    public var until: String?
    public var dates: [String]?
    /// `HH:mm`
    public var open: String
    public var close: String
    public var note: String?

    public init(
        label: String? = nil,
        months: [Int]? = nil,
        days: [String]? = nil,
        from: String? = nil,
        until: String? = nil,
        dates: [String]? = nil,
        open: String,
        close: String,
        note: String? = nil
    ) {
        self.label = label
        self.months = months
        self.days = days
        self.from = from
        self.until = until
        self.dates = dates
        self.open = open
        self.close = close
        self.note = note
    }
}

/// Fixed-start block. Parks may run blocks only, drop-in windows only, or both.
public struct ParkSlot: Codable, Equatable, Sendable, ParkDateSelector {
    public var id: String
    public var label: String?
    public var months: [Int]?
    public var days: [String]?
    public var from: String?
    public var until: String?
    public var dates: [String]?
    public var start: String
    public var end: String

    public init(
        id: String,
        label: String? = nil,
        months: [Int]? = nil,
        days: [String]? = nil,
        from: String? = nil,
        until: String? = nil,
        dates: [String]? = nil,
        start: String,
        end: String
    ) {
        self.id = id
        self.label = label
        self.months = months
        self.days = days
        self.from = from
        self.until = until
        self.dates = dates
        self.start = start
        self.end = end
    }
}

public struct ParkOpening: Codable, Equatable, Sendable {
    /// Opaque: `required`, `optional`, `none`.
    public var booking: String?
    public var rules: [ParkOpeningRule]?
    public var slots: [ParkSlot]?
    /// `false` when blocks are plain start times (hourly) rather than numbered ("Block 3"). Default numbered.
    public var numbered: Bool?
    /// Durations a booking can span, in minutes (`[60, 120]` = per 1 or 2 hours).
    public var bookingMinutes: [Int]?
    public var note: String?
    /// `true` when the park doesn't publish which days its blocks/windows apply to (e.g. no weekly
    /// schedule on their site) — `slots`/`rules` may still list block times, but we can't say which
    /// days they're actually open. Overrides any day/week computation with "unknown" for every day.
    public var hoursUnknown: Bool?

    enum CodingKeys: String, CodingKey {
        case booking, rules, slots, numbered, note
        case bookingMinutes = "booking_minutes"
        case hoursUnknown = "hours_unknown"
    }

    public init(
        booking: String? = nil,
        rules: [ParkOpeningRule]? = nil,
        slots: [ParkSlot]? = nil,
        numbered: Bool? = nil,
        bookingMinutes: [Int]? = nil,
        note: String? = nil,
        hoursUnknown: Bool? = nil
    ) {
        self.booking = booking
        self.rules = rules
        self.slots = slots
        self.numbered = numbered
        self.bookingMinutes = bookingMinutes
        self.note = note
        self.hoursUnknown = hoursUnknown
    }
}

public struct ParkTimeWindow: Equatable, Sendable {
    public var label: String?
    public var startMinute: Int
    public var endMinute: Int
    public var note: String?

    public init(label: String?, startMinute: Int, endMinute: Int, note: String?) {
        self.label = label
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.note = note
    }
}

public struct ParkDaySchedule: Equatable, Sendable {
    public var windows: [ParkTimeWindow]
    /// Slots that fit inside an open window (or are fixed for the day when the park has no drop-in rules).
    public var availableSlots: [ParkSlot]
    /// `false` when `opening.hoursUnknown` is set — the park's weekly day pattern isn't published, so
    /// we can't tell which days its blocks/windows actually apply to.
    public var isScheduleKnown: Bool

    public init(windows: [ParkTimeWindow], availableSlots: [ParkSlot], isScheduleKnown: Bool = true) {
        self.windows = windows
        self.availableSlots = availableSlots
        self.isScheduleKnown = isScheduleKnown
    }

    public var isOpen: Bool { isScheduleKnown && (!windows.isEmpty || !availableSlots.isEmpty) }
}

public struct ParkScheduleLine: Equatable, Sendable {
    public var label: String?
    public var days: [String]?
    public var from: String?
    public var until: String?
    public var dates: [String]?
    public var open: String
    public var close: String
    public var note: String?
}

/// One display entry per month; `lines` holds the specialities (weekend hours, beginner hour, …).
/// `month == nil` collects rules without a `months` selector.
public struct ParkMonthSchedule: Equatable, Sendable, Identifiable {
    public var month: Int?
    public var lines: [ParkScheduleLine]

    public var id: Int { month ?? 0 }
}

/// Whether a park is open right now, accounting for the current time — not just whether today
/// has any opening windows at all.
public enum ParkOpenStatus: Equatable, Sendable {
    /// Open now, or opens later today.
    case openToday
    case opensTomorrow
    /// Not open today, and the next opening isn't tomorrow either (or there's no schedule at all).
    case closed
    /// The park only publishes fixed block times with no confirmed weekly day pattern, so open/closed
    /// can't be determined for any given day.
    case unknown
}

public enum ParkSchedule {
    /// Collapses opening rules into one entry per month, ordered January to December.
    public static func months(for opening: ParkOpening?) -> [ParkMonthSchedule] {
        var byMonth: [Int?: [ParkScheduleLine]] = [:]
        for rule in opening?.rules ?? [] {
            let line = ParkScheduleLine(
                label: rule.label,
                days: rule.days,
                from: rule.from,
                until: rule.until,
                dates: rule.dates,
                open: rule.open,
                close: rule.close,
                note: rule.note
            )
            let dateMonths = Set((rule.dates ?? []).compactMap { Int($0.split(separator: "-").dropFirst().first ?? "") })
            let keys: [Int?] = rule.months.map { $0.map { Optional($0) } }
                ?? (dateMonths.isEmpty ? [nil] : dateMonths.sorted().map { Optional($0) })
            for month in keys {
                byMonth[month, default: []].append(line)
            }
        }
        return byMonth
            .map { ParkMonthSchedule(month: $0.key, lines: $0.value) }
            .sorted { ($0.month ?? 13) < ($1.month ?? 13) }
    }

    public static func day(
        for opening: ParkOpening?,
        on date: Date,
        timeZone: TimeZone
    ) -> ParkDaySchedule {
        let closed = ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: true)
        guard let opening else { return closed }
        guard opening.hoursUnknown != true else {
            return ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: false)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = parts.year, let month = parts.month,
              let day = parts.day, let weekday = parts.weekday
        else { return closed }
        let isoDate = String(format: "%04d-%02d-%02d", year, month, day)

        func matches(_ selector: some ParkDateSelector) -> Bool {
            if let months = selector.months, !months.contains(month) { return false }
            if let days = selector.days, !days.contains(where: { dayToken($0, matches: weekday) }) { return false }
            if let from = selector.from, isoDate < from { return false }
            if let until = selector.until, isoDate > until { return false }
            if let dates = selector.dates, !dates.contains(isoDate) { return false }
            return true
        }

        let rules = opening.rules ?? []
        let windows: [ParkTimeWindow] = rules.filter(matches).compactMap { rule in
            guard let start = minutes(rule.open), var end = minutes(rule.close) else { return nil }
            if end <= start { end += 24 * 60 }
            return ParkTimeWindow(label: rule.label, startMinute: start, endMinute: end, note: rule.note)
        }
        .sorted { $0.startMinute < $1.startMinute }

        let slots = (opening.slots ?? []).filter(matches)
        let available: [ParkSlot]
        if rules.isEmpty {
            available = slots
        } else {
            available = slots.filter { slot in
                guard let start = minutes(slot.start), var end = minutes(slot.end) else { return false }
                if end <= start { end += 24 * 60 }
                return windows.contains { start >= $0.startMinute && end <= $0.endMinute }
            }
        }
        return ParkDaySchedule(windows: windows, availableSlots: available)
    }

    /// Today's `isOpen` alone doesn't account for the current time of day — a park that closed
    /// at 18:00 still has windows "today" at 20:00. This checks whether now still falls inside
    /// (or before) one of today's windows before falling back to tomorrow's schedule.
    public static func status(for opening: ParkOpening?, at date: Date, timeZone: TimeZone) -> ParkOpenStatus {
        guard let opening else { return .closed }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        let today = day(for: opening, on: date, timeZone: timeZone)
        guard today.isScheduleKnown else { return .unknown }
        if today.windows.contains(where: { nowMinute < $0.endMinute }) {
            return .openToday
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return .closed }
        let tomorrowDay = day(for: opening, on: tomorrow, timeZone: timeZone)
        guard tomorrowDay.isScheduleKnown else { return .unknown }
        return tomorrowDay.isOpen ? .opensTomorrow : .closed
    }

    public static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    public static func timeText(minutes: Int) -> String {
        let wrapped = minutes % (24 * 60)
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    /// `weekday`: Gregorian, 1 = Sunday.
    private static func dayToken(_ token: String, matches weekday: Int) -> Bool {
        switch token.lowercased() {
        case "daily", "all": return true
        case "weekdays": return (2...6).contains(weekday)
        case "weekend": return weekday == 1 || weekday == 7
        case "sun": return weekday == 1
        case "mon": return weekday == 2
        case "tue": return weekday == 3
        case "wed": return weekday == 4
        case "thu": return weekday == 5
        case "fri": return weekday == 6
        case "sat": return weekday == 7
        default: return false
        }
    }
}
