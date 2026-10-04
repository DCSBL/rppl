import Foundation

/// Turns the weekday and month choices of the editor (a set you switch on and off) into the compact
/// selectors a rule or block stores, and back. "Every day" and "all year" are stored as no selector.
public enum ParkDaySelection {
    /// Monday to Sunday, in the order the editor lists them.
    public static let weekdayTokens = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private static let workWeek: Set<String> = ["mon", "tue", "wed", "thu", "fri"]
    private static let weekend: Set<String> = ["sat", "sun"]

    /// The individual days a stored `days` selector stands for. nil (no selector) is every day.
    public static func days(from tokens: [String]?) -> Set<String> {
        guard let tokens, !tokens.isEmpty else { return Set(weekdayTokens) }
        var days = Set<String>()
        for token in tokens.map({ $0.lowercased() }) {
            switch token {
            case "daily", "all": days.formUnion(weekdayTokens)
            case "weekdays": days.formUnion(workWeek)
            case "weekend": days.formUnion(weekend)
            default: if weekdayTokens.contains(token) { days.insert(token) }
            }
        }
        return days
    }

    /// The shortest selector for the chosen days: nil for all seven, `weekdays` and `weekend` when
    /// they fit, individual days otherwise. An empty choice is stored as every day too, because a
    /// rule that never applies helps nobody.
    public static func tokens(from days: Set<String>) -> [String]? {
        let valid = days.intersection(weekdayTokens)
        if valid.isEmpty || valid.count == weekdayTokens.count { return nil }
        var rest = valid
        var tokens: [String] = []
        if workWeek.isSubset(of: rest) {
            tokens.append("weekdays")
            rest.subtract(workWeek)
        }
        if weekend.isSubset(of: rest) {
            tokens.append("weekend")
            rest.subtract(weekend)
        }
        tokens += weekdayTokens.filter { rest.contains($0) }
        return tokens
    }

    /// Months 1...12 as stored: nil for none or all twelve (every month), otherwise sorted.
    public static func months(from selection: Set<Int>) -> [Int]? {
        let valid = selection.filter { (1...12).contains($0) }
        if valid.isEmpty || valid.count == 12 { return nil }
        return valid.sorted()
    }

    public static func monthSet(from months: [Int]?) -> Set<Int> {
        guard let months, !months.isEmpty else { return Set(1...12) }
        return Set(months.filter { (1...12).contains($0) })
    }
}

/// Clock times stored as `HH:mm`, 24 hour, whatever the device shows.
public enum ParkClock {
    /// `sunset` is not a clock time: it stands for the end of the day (see `ParkSchedule`).
    public static let sunset = "sunset"

    public static func minutes(_ time: String) -> Int? {
        time.lowercased() == sunset ? 24 * 60 : ParkSchedule.minutes(time)
    }

    /// `HH:mm` for a minute of the day, wrapped to 0...1439.
    public static func text(minutes: Int) -> String {
        ParkSchedule.timeText(minutes: ((minutes % 1440) + 1440) % 1440)
    }

    /// Whether a window from `open` to `close` runs past midnight (closing at or before opening).
    /// A window that ends at `sunset` never does.
    public static func wrapsPastMidnight(open: String, close: String) -> Bool {
        guard close.lowercased() != sunset, let start = ParkSchedule.minutes(open), let end = ParkSchedule.minutes(close)
        else { return false }
        return end <= start
    }
}

/// Calendar dates stored as `yyyy-MM-dd`. A date here is a day, not a moment: it is read and written
/// in UTC so the day never shifts with the device's or the park's time zone.
public enum ParkDateText {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Noon UTC on that day; nil for text that is not a real date.
    public static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, iso.count == 10 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        // "2026-02-31" rolls over to March: not a date.
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2] ? date : nil
    }

    public static func iso(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    public static func isValid(_ iso: String) -> Bool { date(from: iso) != nil }
}

extension ParkCable {
    /// Whether the traced points go round clockwise, seen from above with north up. nil without three
    /// points or when they are on one line. Points are listed in travel order, so this is the direction
    /// riders go.
    public var tracedWindingIsClockwise: Bool? {
        guard let points, points.count >= 3 else { return nil }
        let latitude = (points.map(\.lat).reduce(0, +)) / Double(points.count)
        let scale = cos(latitude * .pi / 180)
        // Shoelace formula on local x (east) / y (north); positive area is counter-clockwise.
        var area = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += (current.lon * scale) * next.lat - (next.lon * scale) * current.lat
        }
        guard abs(area) > 1e-12 else { return nil }
        return area < 0
    }
}
