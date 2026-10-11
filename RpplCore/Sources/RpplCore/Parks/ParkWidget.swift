import Foundation

/// What the parks widget says about one park at one moment.
public enum ParkWidgetState: Equatable, Sendable {
    /// Open now, until the window closes.
    case openUntil(ParkTimeWindow)
    /// Opens later today.
    case opensToday(ParkTimeWindow)
    case opensTomorrow
    /// Closed, next opening in `days` (2 or more) days.
    case opensInDays(Int)
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
        case .closed:
            guard let next = ParkSchedule.nextOpening(for: opening, after: date, timeZone: timeZone) else { return .closed }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: next.start)
            ).day ?? 0
            if days <= 0 { return .closed }
            return days == 1 ? .opensTomorrow : .opensInDays(days)
        case .unknown: return .unknown
        }
    }
}

/// A cable trace as a unit-square drawing (north up), for the widget art.
public struct ParkTrace: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
    }

    /// In travel order; the first point is the start.
    public var points: [Point]
    /// A full-size cable goes round, so the line closes back to the start.
    public var isLoop: Bool

    /// The first cable with at least two points. Aspect ratio is kept; the shape is centred in 0...1.
    public static func make(for park: Park) -> ParkTrace? {
        guard let cable = (park.cables ?? []).first(where: { ($0.points ?? []).count >= 2 }),
              let coordinates = cable.points?.map(\.coordinate)
        else { return nil }
        let meanLat = coordinates.map(\.lat).reduce(0, +) / Double(coordinates.count)
        let lonScale = cos(meanLat * .pi / 180)
        let xs = coordinates.map { $0.lon * lonScale }
        let ys = coordinates.map { -$0.lat }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return nil }
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        let points = zip(xs, ys).map { Point(x: ($0 - minX + offsetX) / span, y: ($1 - minY + offsetY) / span) }
        let isLoop = cable.direction == .clockwise || cable.direction == .counterClockwise
        return ParkTrace(points: points, isLoop: isLoop)
    }
}

/// Link from the widget to a park in the app (`rppl://park/<id>`).
public enum ParkDeepLink {
    public static let scheme = "rppl"
    private static let host = "park"

    public static func url(forParkID id: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + id
        return components.url
    }

    public static func parkID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let id = url.path.split(separator: "/").first.map(String.init)
        return (id?.isEmpty ?? true) ? nil : id
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
