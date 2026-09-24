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
}

public struct ParkOpeningRule: Codable, Equatable, Sendable, ParkDateSelector {
    public var label: String?
    public var months: [Int]?
    public var days: [String]?
    public var from: String?
    public var until: String?
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
        open: String,
        close: String,
        note: String? = nil
    ) {
        self.label = label
        self.months = months
        self.days = days
        self.from = from
        self.until = until
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
    public var start: String
    public var end: String

    public init(
        id: String,
        label: String? = nil,
        months: [Int]? = nil,
        days: [String]? = nil,
        from: String? = nil,
        until: String? = nil,
        start: String,
        end: String
    ) {
        self.id = id
        self.label = label
        self.months = months
        self.days = days
        self.from = from
        self.until = until
        self.start = start
        self.end = end
    }
}

public struct ParkOpening: Codable, Equatable, Sendable {
    /// Opaque: `required`, `optional`, `none`.
    public var booking: String?
    public var rules: [ParkOpeningRule]?
    public var slots: [ParkSlot]?
    public var note: String?

    public init(
        booking: String? = nil,
        rules: [ParkOpeningRule]? = nil,
        slots: [ParkSlot]? = nil,
        note: String? = nil
    ) {
        self.booking = booking
        self.rules = rules
        self.slots = slots
        self.note = note
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

    public var isOpen: Bool { !windows.isEmpty || !availableSlots.isEmpty }
}

public enum ParkSchedule {
    public static func day(
        for opening: ParkOpening?,
        on date: Date,
        timeZone: TimeZone
    ) -> ParkDaySchedule {
        let closed = ParkDaySchedule(windows: [], availableSlots: [])
        guard let opening else { return closed }

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
