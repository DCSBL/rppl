import RpplCore
import SwiftUI
import WidgetKit

struct ParkHoursEntry: TimelineEntry {
    let date: Date
    /// `nil` until a park is picked (or when the picked park no longer exists).
    let parkName: String?
    let parkID: String?
    let trace: ParkTrace?
    let state: ParkWidgetState
}

struct ParkHoursProvider: AppIntentTimelineProvider {
    /// Gallery preview: the rider's most visited park with a fixed "Open today until 19:00".
    func placeholder(in context: Context) -> ParkHoursEntry {
        let park = ParkWidgetStore.mostVisited()
        return ParkHoursEntry(
            date: Date(),
            parkName: park?.name ?? "Cable Park",
            parkID: park?.id,
            trace: park.flatMap(ParkTrace.make(for:)),
            state: .openUntil(ParkTimeWindow(label: nil, startMinute: 10 * 60, endMinute: 19 * 60, note: nil))
        )
    }

    func snapshot(for configuration: SelectParkIntent, in context: Context) async -> ParkHoursEntry {
        if context.isPreview { return placeholder(in: context) }
        return entries(for: configuration, from: Date()).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectParkIntent, in context: Context) async -> Timeline<ParkHoursEntry> {
        let entries = entries(for: configuration, from: Date())
        return Timeline(entries: entries, policy: .after(entries.last?.date ?? Date().addingTimeInterval(3600)))
    }

    /// One entry now, one per moment the text changes (opening, closing, midnight).
    private func entries(for configuration: SelectParkIntent, from now: Date) -> [ParkHoursEntry] {
        let picked = configuration.park.flatMap { ParkWidgetStore.park(id: $0.id) }
        guard let park = picked ?? ParkWidgetStore.mostVisited() else {
            return [ParkHoursEntry(date: now, parkName: nil, parkID: nil, trace: nil, state: .unknown)]
        }
        let zone = park.resolvedTimeZone
        let dates = [now] + ParkWidgetTimeline.changeDates(for: park.opening, after: now, timeZone: zone)
        let trace = ParkTrace.make(for: park)
        return dates.map {
            ParkHoursEntry(date: $0, parkName: park.name, parkID: park.id, trace: trace, state: .make(for: park, at: $0))
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

    /// The park name is never cut off: it wraps and shrinks before it clips.
    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.parkName ?? String(localized: "Choose a park"))
                .font(.headline)
                .foregroundStyle(Color("RpplText"))
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if entry.parkName != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(entry.state.tint)
                    Text(entry.state.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("RpplMuted"))
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The cable as a single line in the Rppl accent colour, with a dot on the start.
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
            guard let first = trace.points.first else { return }
            var path = Path()
            path.move(to: point(first))
            for p in trace.points.dropFirst() { path.addLine(to: point(p)) }
            if trace.isLoop { path.closeSubpath() }
            let accent = Color("RpplAccent")
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            let start = point(first)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(accent))
        }
        .accessibilityHidden(true)
    }
}

extension ParkWidgetState {
    var tint: Color {
        switch self {
        case .openUntil, .opensToday: .green
        case .opensTomorrow, .opensInDays: .yellow
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
            let from = ParkSchedule.timeText(minutes: window.startMinute)
            let to = Self.end(window)
            return String(localized: "Open today from \(from) to \(to)")
        case .opensTomorrow: return String(localized: "Open tomorrow")
        case .opensInDays(let days): return String(localized: "Open in \(days) days")
        case .closed: return String(localized: "Closed")
        case .unknown: return String(localized: "Opening hours unknown")
        }
    }

    /// `sunset` stays English in every locale and is not calculated (Docs/Parks.md).
    static func end(_ window: ParkTimeWindow) -> String {
        window.endsAtSunset ? "sunset" : ParkSchedule.timeText(minutes: window.endMinute)
    }
}
