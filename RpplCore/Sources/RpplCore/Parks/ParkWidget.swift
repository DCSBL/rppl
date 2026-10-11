import Foundation

/// What the parks widget says about one park at one moment.
public enum ParkWidgetState: Equatable, Sendable {
    /// Open now, until the window closes.
    case openUntil(ParkTimeWindow)
    /// Opens later today.
    case opensToday(ParkTimeWindow)
    case opensTomorrow
    case closed
    /// No opening times filled in.
    case unknown

    public static func make(for park: Park, at date: Date) -> ParkWidgetState {
        make(for: park.opening, at: date, timeZone: park.resolvedTimeZone)
    }

    public static func make(for opening: ParkOpening?, at date: Date, timeZone: TimeZone) -> ParkWidgetState {
        let detail = ParkSchedule.statusDetail(for: opening, at: date, timeZone: timeZone)
        switch detail.status {
        case .openToday:
            guard let window = detail.window else { return .unknown }
            return detail.windowHasStarted == true ? .openUntil(window) : .opensToday(window)
        case .opensTomorrow: return .opensTomorrow
        case .closed: return .closed
        case .unknown: return .unknown
        }
    }
}

/// When the widget text can change by itself, so the timeline has an entry for each moment.
public enum ParkWidgetTimeline {
    /// Window starts and ends plus midnights over today and the next `days - 1` days, after `date`, sorted.
    public static func changeDates(
        for opening: ParkOpening?,
        after date: Date,
        timeZone: TimeZone,
        days: Int = 2
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dates = Set<Date>()
        for offset in 0...max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let midnight = calendar.startOfDay(for: day)
            if offset > 0 { dates.insert(midnight) }
            guard offset < days else { continue }
            for window in ParkSchedule.day(for: opening, on: day, timeZone: timeZone).windows {
                for minute in [window.startMinute, window.endMinute] {
                    if let moment = calendar.date(byAdding: .minute, value: minute, to: midnight) {
                        dates.insert(moment)
                    }
                }
            }
        }
        return dates.filter { $0 > date }.sorted()
    }
}
