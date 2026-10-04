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

/// Opaque `kind` values for `ParkOpeningException`. Unknown kinds are informational (label and note only).
public enum ParkExceptionKind {
    /// These are the hours on the matching dates; they replace the regular hours.
    public static let hours = "hours"
    /// Closed all day, whatever the regular hours say.
    public static let closed = "closed"
    /// Opens in addition to the regular hours (an extra evening, an early start).
    public static let extra = "extra"
    /// Informational only (competition, party, maintenance); does not change open/closed.
    public static let event = "event"
}

/// A one-off or temporary change on top of the regular `rules`: extra opening hours, a closure
/// for wind or maintenance, an event. Needs at least one of `from`, `until` or `dates`, so a
/// forgotten exception can never apply to every day. Once its dates are past it has no effect.
///
/// Precedence per day: `closed` beats `hours` beats the regular rules; `extra` is added on top of
/// either; `event` and unknown kinds only add a notice.
public struct ParkOpeningException: Codable, Equatable, Sendable, ParkDateSelector {
    /// Opaque, see `ParkExceptionKind`.
    public var kind: String
    public var label: String?
    public var months: [Int]?
    public var days: [String]?
    public var from: String?
    public var until: String?
    public var dates: [String]?
    /// `HH:mm` or `sunset`. Used by `hours` and `extra`.
    public var open: String?
    public var close: String?
    public var note: String?

    public init(
        kind: String,
        label: String? = nil,
        months: [Int]? = nil,
        days: [String]? = nil,
        from: String? = nil,
        until: String? = nil,
        dates: [String]? = nil,
        open: String? = nil,
        close: String? = nil,
        note: String? = nil
    ) {
        self.kind = kind
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

    /// `false` for an exception without any date bound; those are ignored.
    var isDateBound: Bool { from != nil || until != nil || dates != nil }

    var normalizedKind: String { kind.lowercased() }
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
    /// Temporary or one-off changes (extra opening hours, closures, events) on top of `rules`.
    public var exceptions: [ParkOpeningException]?

    /// Whether any `rules` or `slots` are filled in. Without them the park has not told us when it is
    /// open, which reads as unknown, never as closed.
    public var hasSchedule: Bool { !(rules ?? []).isEmpty || !(slots ?? []).isEmpty }

    /// `false` when no rules or slots are filled in: the park has not told us when it is open.
    public var isScheduleKnown: Bool { hasSchedule }

    enum CodingKeys: String, CodingKey {
        case booking, rules, slots, numbered, note, exceptions
        case bookingMinutes = "booking_minutes"
    }

    public init(
        booking: String? = nil,
        rules: [ParkOpeningRule]? = nil,
        slots: [ParkSlot]? = nil,
        numbered: Bool? = nil,
        bookingMinutes: [Int]? = nil,
        note: String? = nil,
        exceptions: [ParkOpeningException]? = nil
    ) {
        self.booking = booking
        self.rules = rules
        self.slots = slots
        self.numbered = numbered
        self.bookingMinutes = bookingMinutes
        self.note = note
        self.exceptions = exceptions
    }
}

public struct ParkTimeWindow: Equatable, Sendable {
    public var label: String?
    public var startMinute: Int
    public var endMinute: Int
    public var note: String?
    /// `true` when the window was written as `close: sunset`. `endMinute` is then 00:00 (1440);
    /// show "sunset" instead of a clock time.
    public var endsAtSunset: Bool

    public init(label: String?, startMinute: Int, endMinute: Int, note: String?, endsAtSunset: Bool = false) {
        self.label = label
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.note = note
        self.endsAtSunset = endsAtSunset
    }
}

/// An exception that applies to one day, for showing next to the hours ("Closed: wind").
public struct ParkDayNotice: Equatable, Sendable {
    public var kind: String
    public var label: String?
    public var note: String?

    public init(kind: String, label: String? = nil, note: String? = nil) {
        self.kind = kind
        self.label = label
        self.note = note
    }
}

public struct ParkDaySchedule: Equatable, Sendable {
    public var windows: [ParkTimeWindow]
    /// Slots that fit inside an open window (or are fixed for the day when the park has no drop-in rules).
    public var availableSlots: [ParkSlot]
    /// `false` when the park has no rules or slots filled in, so we can't tell when it is open.
    public var isScheduleKnown: Bool
    /// Exceptions (closures, changed or extra hours, events) that apply to this day.
    public var notices: [ParkDayNotice]

    public init(
        windows: [ParkTimeWindow],
        availableSlots: [ParkSlot],
        isScheduleKnown: Bool = true,
        notices: [ParkDayNotice] = []
    ) {
        self.windows = windows
        self.availableSlots = availableSlots
        self.isScheduleKnown = isScheduleKnown
        self.notices = notices
    }

    /// Closed all day by a `closed` exception (unplanned closure), not just by the regular hours.
    public var isClosedByException: Bool {
        notices.contains { $0.kind.lowercased() == ParkExceptionKind.closed }
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

/// `status(for:at:timeZone:)` plus the window that status is actually about, so callers can show
/// "open until 20:00" / "opens 15:00–20:00" instead of just a category.
public struct ParkOpenStatusDetail: Equatable, Sendable {
    public var status: ParkOpenStatus
    /// Set only when `status == .openToday`: the window covering now, or (if none has started yet)
    /// the next one opening today.
    public var window: ParkTimeWindow?
    /// Set only alongside `window`: `true` when `window` has already started (now falls inside it),
    /// `false` when it opens later today.
    public var windowHasStarted: Bool?

    public init(status: ParkOpenStatus, window: ParkTimeWindow? = nil, windowHasStarted: Bool? = nil) {
        self.status = status
        self.window = window
        self.windowHasStarted = windowHasStarted
    }
}

/// One exception on one concrete day, for an "upcoming changes" list.
public struct ParkExceptionOccurrence: Equatable, Sendable, Identifiable {
    /// `yyyy-MM-dd` in the park's time zone.
    public var date: String
    public var kind: String
    public var label: String?
    public var note: String?
    /// Resolved windows (`sunset` already turned into minutes); empty for `closed` and `event`.
    public var windows: [ParkTimeWindow]

    public var id: String { "\(date)|\(kind)|\(label ?? "")|\(windows.first?.startMinute ?? -1)" }
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
        // No opening times filled in at all is "unknown", not "closed": nobody told us either way.
        let unknown = ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: false)
        guard let opening else { return unknown }
        guard let context = DayContext(date: date, timeZone: timeZone) else {
            return ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: true)
        }

        let active = activeExceptions(in: opening, on: context)
        let notices = active.map { ParkDayNotice(kind: $0.normalizedKind, label: $0.label, note: $0.note) }

        // An empty weekly pattern stays unknown, unless an exception states what happens that day.
        let noPattern = !opening.hasSchedule
        if noPattern, !active.contains(where: { [ParkExceptionKind.hours, ParkExceptionKind.closed].contains($0.normalizedKind) }) {
            return ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: false, notices: notices)
        }

        if active.contains(where: { $0.normalizedKind == ParkExceptionKind.closed }) {
            return ParkDaySchedule(windows: [], availableSlots: [], isScheduleKnown: true, notices: notices)
        }

        let rules: [ParkOpeningRule] = opening.rules ?? []
        let regular: [ParkTimeWindow] = rules.filter { context.matches($0) }.compactMap { rule in
            makeWindow(open: rule.open, close: rule.close, label: rule.label, note: rule.note)
        }
        let replacing = windows(of: active, kind: ParkExceptionKind.hours)
        let extra = windows(of: active, kind: ParkExceptionKind.extra)
        let windows = ((replacing.isEmpty ? regular : replacing) + extra).sorted { $0.startMinute < $1.startMinute }

        let slots = (opening.slots ?? []).filter { context.matches($0) }
        let available: [ParkSlot]
        if rules.isEmpty, replacing.isEmpty, extra.isEmpty {
            available = slots
        } else {
            available = slots.filter { slot in
                guard let start = minutes(slot.start), var end = minutes(slot.end) else { return false }
                if end <= start { end += 24 * 60 }
                return windows.contains { start >= $0.startMinute && end <= $0.endMinute }
            }
        }
        return ParkDaySchedule(windows: windows, availableSlots: available, notices: notices)
    }

    /// Every exception on each of the next `days` days starting at `date`, oldest first. Past
    /// exceptions never show up, so old entries can stay in the file until someone tidies them.
    public static func upcomingExceptions(
        for opening: ParkOpening?,
        from date: Date,
        days horizon: Int = 90,
        timeZone: TimeZone
    ) -> [ParkExceptionOccurrence] {
        guard let opening, !(opening.exceptions ?? []).isEmpty, horizon > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var result: [ParkExceptionOccurrence] = []
        for offset in 0..<horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let context = DayContext(date: day, timeZone: timeZone)
            else { continue }
            for exception in activeExceptions(in: opening, on: context) {
                let kind = exception.normalizedKind
                let resolved: [ParkTimeWindow]
                if kind == ParkExceptionKind.hours || kind == ParkExceptionKind.extra {
                    resolved = windows(of: [exception], kind: kind)
                } else {
                    resolved = []
                }
                result.append(ParkExceptionOccurrence(
                    date: context.isoDate,
                    kind: kind,
                    label: exception.label,
                    note: exception.note,
                    windows: resolved
                ))
            }
        }
        return result
    }

    /// Today's `isOpen` alone doesn't account for the current time of day — a park that closed
    /// at 18:00 still has windows "today" at 20:00. This checks whether now still falls inside
    /// (or before) one of today's windows before falling back to tomorrow's schedule.
    public static func status(
        for opening: ParkOpening?,
        at date: Date,
        timeZone: TimeZone
    ) -> ParkOpenStatus {
        statusDetail(for: opening, at: date, timeZone: timeZone).status
    }

    /// Same as `status(for:at:timeZone:)`, plus the window that status is about (for `.openToday`).
    public static func statusDetail(
        for opening: ParkOpening?,
        at date: Date,
        timeZone: TimeZone
    ) -> ParkOpenStatusDetail {
        guard let opening else { return ParkOpenStatusDetail(status: .unknown) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        let today = day(for: opening, on: date, timeZone: timeZone)
        guard today.isScheduleKnown else { return ParkOpenStatusDetail(status: .unknown) }
        if let window = today.windows.first(where: { nowMinute < $0.endMinute }) {
            return ParkOpenStatusDetail(status: .openToday, window: window, windowHasStarted: nowMinute >= window.startMinute)
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else {
            return ParkOpenStatusDetail(status: .closed)
        }
        let tomorrowDay = day(for: opening, on: tomorrow, timeZone: timeZone)
        guard tomorrowDay.isScheduleKnown else { return ParkOpenStatusDetail(status: .unknown) }
        return ParkOpenStatusDetail(status: tomorrowDay.isOpen ? .opensTomorrow : .closed)
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

    /// A calendar day in the park's time zone, with the selector matching rules and slots share.
    private struct DayContext {
        let isoDate: String
        let month: Int
        /// Gregorian, 1 = Sunday.
        let weekday: Int

        init?(date: Date, timeZone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            guard let year = parts.year, let month = parts.month,
                  let day = parts.day, let weekday = parts.weekday
            else { return nil }
            self.isoDate = String(format: "%04d-%02d-%02d", year, month, day)
            self.month = month
            self.weekday = weekday
        }

        func matches(_ selector: some ParkDateSelector) -> Bool {
            if let months = selector.months, !months.contains(month) { return false }
            if let days = selector.days, !days.contains(where: { ParkSchedule.dayToken($0, matches: weekday) }) { return false }
            if let from = selector.from, isoDate < from { return false }
            if let until = selector.until, isoDate > until { return false }
            if let dates = selector.dates, !dates.contains(isoDate) { return false }
            return true
        }
    }

    private static func activeExceptions(in opening: ParkOpening, on context: DayContext) -> [ParkOpeningException] {
        (opening.exceptions ?? []).filter { $0.isDateBound && context.matches($0) }
    }

    private static func windows(of exceptions: [ParkOpeningException], kind: String) -> [ParkTimeWindow] {
        exceptions.filter { $0.normalizedKind == kind }.compactMap { exception in
            guard let open = exception.open, let close = exception.close else { return nil }
            return makeWindow(open: open, close: close, label: exception.label, note: exception.note)
        }
    }

    /// `HH:mm` or `sunset`. `sunset` is not calculated: it is a label for "until the end of the day",
    /// so the park counts as closed from 00:00.
    private static func resolveTime(_ text: String) -> (minute: Int, isSolar: Bool)? {
        if text.lowercased() == "sunset" { return (24 * 60, true) }
        return minutes(text).map { ($0, false) }
    }

    /// A window that ends at or before its start wraps past midnight, except when it involves
    /// `sunset` (00:00): that never wraps into the next day.
    private static func makeWindow(open: String, close: String, label: String?, note: String?) -> ParkTimeWindow? {
        guard let start = resolveTime(open), let endTime = resolveTime(close) else { return nil }
        var end = endTime.minute
        if end <= start.minute {
            if start.isSolar || endTime.isSolar { return nil }
            end += 24 * 60
        }
        return ParkTimeWindow(label: label, startMinute: start.minute, endMinute: end, note: note, endsAtSunset: endTime.isSolar)
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
