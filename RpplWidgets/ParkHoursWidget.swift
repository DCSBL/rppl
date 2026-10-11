import RpplCore
import SwiftUI
import WidgetKit

struct ParkHoursEntry: TimelineEntry {
    let date: Date
    /// `nil` until a park is picked (or when the picked park no longer exists).
    let parkName: String?
    let address: String?
    let state: ParkWidgetState
}

struct ParkHoursProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ParkHoursEntry {
        ParkHoursEntry(
            date: Date(),
            parkName: "Cable Park",
            address: nil,
            state: .openUntil(ParkTimeWindow(label: nil, startMinute: 10 * 60, endMinute: 20 * 60, note: nil))
        )
    }

    func snapshot(for configuration: SelectParkIntent, in context: Context) async -> ParkHoursEntry {
        entries(for: configuration, from: Date()).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectParkIntent, in context: Context) async -> Timeline<ParkHoursEntry> {
        let entries = entries(for: configuration, from: Date())
        return Timeline(entries: entries, policy: .after(entries.last?.date ?? Date().addingTimeInterval(3600)))
    }

    /// One entry now, one per moment the text changes (opening, closing, midnight).
    private func entries(for configuration: SelectParkIntent, from now: Date) -> [ParkHoursEntry] {
        guard let id = configuration.park?.id, let park = ParkWidgetStore.park(id: id) else {
            return [ParkHoursEntry(date: now, parkName: nil, address: nil, state: .unknown)]
        }
        let zone = park.resolvedTimeZone
        let dates = [now] + ParkWidgetTimeline.changeDates(for: park.opening, after: now, timeZone: zone)
        return dates.map {
            ParkHoursEntry(date: $0, parkName: park.name, address: park.address, state: .make(for: park, at: $0))
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
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        parkName
                        if let address = entry.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    status
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    parkName
                    Spacer(minLength: 0)
                    status
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var parkName: some View {
        Text(entry.parkName ?? String(localized: "Choose a park"))
            .font(.headline)
            .lineLimit(2)
    }

    private var status: some View {
        VStack(alignment: family == .systemMedium ? .trailing : .leading, spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(entry.state.tint)
            Text(entry.parkName == nil ? "" : entry.state.text)
                .font(family == .systemMedium ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .minimumScaleFactor(0.8)
        }
    }
}

extension ParkWidgetState {
    var tint: Color {
        switch self {
        case .openUntil, .opensToday: .green
        case .opensTomorrow: .yellow
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
        case .closed: return String(localized: "Closed")
        case .unknown: return String(localized: "Opening hours unknown")
        }
    }

    /// `sunset` stays English in every locale and is not calculated (Docs/Parks.md).
    private static func end(_ window: ParkTimeWindow) -> String {
        window.endsAtSunset ? "sunset" : ParkSchedule.timeText(minutes: window.endMinute)
    }
}
