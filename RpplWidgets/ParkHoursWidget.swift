import RpplCore
import SwiftUI
import WidgetKit

struct ParkHoursEntry: TimelineEntry {
    let date: Date
    /// `nil` until a park is picked (or when the picked park no longer exists).
    let parkName: String?
    let parkID: String?
    /// Small line under the name; dropped when there is no room.
    var city: String?
    /// Park time zone name, only when the rider is in another one.
    var timeZoneNote: String?
    let trace: ParkTrace?
    let state: ParkWidgetState
    /// Only for parks with a water station and the opt-in on; shown as the number alone.
    var waterCelsius: Double?
}

struct ParkHoursProvider: AppIntentTimelineProvider {
    /// Gallery preview: the rider's most visited park with a fixed "Open today until 19:00".
    func placeholder(in context: Context) -> ParkHoursEntry {
        let park = ParkWidgetStore.mostVisited()
        return ParkHoursEntry(
            date: Date(),
            parkName: park?.compactName ?? "Cable Park",
            parkID: park?.id,
            city: park?.cityName,
            timeZoneNote: nil,
            trace: park.flatMap(ParkTrace.make(for:)),
            state: .openUntil(ParkTimeWindow(label: nil, startMinute: 10 * 60, endMinute: 19 * 60, note: nil))
        )
    }

    func snapshot(for configuration: SelectParkIntent, in context: Context) async -> ParkHoursEntry {
        if context.isPreview { return placeholder(in: context) }
        return entries(for: configuration, from: Date()).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectParkIntent, in context: Context) async -> Timeline<ParkHoursEntry> {
        let now = Date()
        let water: ParkWidgetWater.Result?
        if let park = park(for: configuration) {
            water = await ParkWidgetWater.result(for: park, now: now)
        } else {
            water = nil
        }
        let entries = entries(for: configuration, from: now, water: water?.reading)
        let end = entries.last?.date ?? now.addingTimeInterval(3600)
        return Timeline(entries: entries, policy: .after(min(end, water?.nextFetch ?? end)))
    }

    private func park(for configuration: SelectParkIntent) -> Park? {
        let picked = configuration.park.flatMap { ParkWidgetStore.park(id: $0.id) }
        return picked ?? ParkWidgetStore.mostVisited()
    }

    /// One entry now, one per moment the text changes (opening, closing, midnight).
    private func entries(for configuration: SelectParkIntent, from now: Date, water: ParkWaterTemperature? = nil) -> [ParkHoursEntry] {
        guard let park = park(for: configuration) else {
            return [ParkHoursEntry(date: now, parkName: nil, parkID: nil, city: nil, timeZoneNote: nil, trace: nil, state: .unknown)]
        }
        let zone = park.resolvedTimeZone
        let dates = [now] + ParkWidgetTimeline.changeDates(for: park.opening, after: now, timeZone: zone)
        let trace = ParkTrace.make(for: park)
        return dates.map {
            ParkHoursEntry(date: $0, parkName: park.compactName, parkID: park.id, city: park.cityName,
                timeZoneNote: ParkTimeZoneNote.label(for: park, deviceZone: .current, at: $0),
                trace: trace, state: .make(for: park, at: $0), waterCelsius: water?.celsius)
        }
    }
}

struct ParkHoursWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "nl.dcsbl.rppl.parkHours", intent: SelectParkIntent.self, provider: ParkHoursProvider()) { entry in
            ParkHoursView(entry: entry)
        }
        .configurationDisplayName("Park hours")
        .description("Opening hours of a cable park.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ParkHoursView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ParkHoursEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(alignment: .center, spacing: 8) {
                    text
                    if let trace = entry.trace {
                        ParkTraceArt(trace: trace)
                            .frame(width: 130, height: 130)
                    }
                }
            } else {
                text
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.parkID.flatMap(ParkDeepLink.url(forParkID:)))
        .containerBackground(for: .widget) { RpplWidgetBackground() }
    }

    /// The park name is never cut off: it wraps and shrinks before it clips. The city only shows when it fits.
    private var text: some View {
        ViewThatFits(in: .vertical) {
            textStack(showCity: true)
            textStack(showCity: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func textStack(showCity: Bool) -> some View {
        if entry.parkName == nil {
            WidgetEmptyState(
                symbol: "mappin.and.ellipse",
                title: "Choose a park",
                hint: family == .systemMedium
                    ? "Touch and hold the widget, then choose Edit Widget. Once you log sessions, your most visited park shows here."
                    : "Touch and hold the widget, then choose Edit Widget."
            )
        } else {
            filledStack(showCity: showCity)
        }
    }

    private func filledStack(showCity: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.parkName ?? "")
                    .font(.headline)
                    .foregroundStyle(Color("RpplText"))
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if showCity, let city = entry.city {
                    Text(city)
                        .font(.caption)
                        .foregroundStyle(Color("RpplMuted"))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.parkName != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ParkStatusDot(state: entry.state, size: 9)
                    ParkStateLine(long: entry.state.text, fallback: entry.state.tomorrowFallback)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("RpplMuted"))
                        .minimumScaleFactor(0.8)
                    if let celsius = entry.waterCelsius {
                        Label(TemperatureFormat.celsius(celsius), systemImage: "water.waves")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color("RpplMuted"))
                    }
                    if let note = entry.timeZoneNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(Color("RpplMuted").opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Open now is a filled dot; everything else is an open circle, so colour is not the only cue.
struct ParkStatusDot: View {
    let state: ParkWidgetState
    let size: CGFloat

    var body: some View {
        Group {
            if state.isOpenNow {
                Circle().fill(state.tint)
            } else {
                Circle().strokeBorder(state.tint, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One status line. With a `fallback` it shows the long text only when it fits on one line.
struct ParkStateLine: View {
    let long: String
    let fallback: String?

    var body: some View {
        if let fallback {
            ViewThatFits(in: .horizontal) {
                Text(long).lineLimit(1).minimumScaleFactor(1)
                Text(fallback)
            }
        } else {
            Text(long)
        }
    }
}

/// Every cable as one line in the Rppl accent, with a dot on each start. All widgets use the same line width.
struct ParkTraceArt: View {
    let trace: ParkTrace

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let inset = side * 0.08
            let drawSide = side - inset * 2
            func point(_ p: ParkTrace.Point) -> CGPoint {
                CGPoint(x: origin.x + inset + p.x * drawSide, y: origin.y + inset + p.y * drawSide)
            }
            let accent = Color("RpplAccent")
            for line in trace.lines {
                guard let first = line.points.first else { continue }
                var path = Path()
                path.move(to: point(first))
                for p in line.points.dropFirst() { path.addLine(to: point(p)) }
                if line.isLoop { path.closeSubpath() }
                context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                let start = point(first)
                context.fill(Path(ellipseIn: CGRect(x: start.x - 4.5, y: start.y - 4.5, width: 9, height: 9)), with: .color(accent))
            }
        }
        .accessibilityHidden(true)
    }
}

extension ParkWidgetState {
    var isOpenNow: Bool {
        if case .openUntil = self { true } else { false }
    }

    var tint: Color {
        switch self {
        case .openUntil: .green
        case .opensToday, .opensTomorrow, .opensInDays: .yellow
        case .closed: .red
        case .unknown: .gray
        }
    }

    var text: String {
        switch self {
        case .openUntil(let window):
            let to = Self.end(window)
            return String(localized: "Open today until \(to)")
        case .opensToday(let window):
            let from = ParkSchedule.displayTime(minutes: window.startMinute)
            let to = Self.end(window)
            return String(localized: "Open today from \(from) to \(to)")
        case .opensTomorrow(let startMinute):
            let from = ParkSchedule.displayTime(minutes: startMinute)
            return String(localized: "Open tomorrow from \(from)")
        case .opensInDays(let days): return String(localized: "Open in \(days) days")
        case .closed: return String(localized: "Closed")
        case .unknown: return String(localized: "Opening hours unknown")
        }
    }

    /// Shorter line for when `text` / `shortText` does not fit. Only tomorrow has one.
    var tomorrowFallback: String? {
        if case .opensTomorrow = self { String(localized: "Open tomorrow") } else { nil }
    }

    /// `sunset` stays English in every locale and is not calculated (Docs/Parks.md).
    static func end(_ window: ParkTimeWindow) -> String {
        window.endsAtSunset ? "sunset" : ParkSchedule.displayTime(minutes: window.endMinute)
    }
}
