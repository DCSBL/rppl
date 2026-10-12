import RpplCore
import SwiftUI
import WidgetKit

struct TopParksEntry: TimelineEntry {
    struct Row: Identifiable {
        let id: String
        let name: String
        let state: ParkWidgetState
    }

    let date: Date
    let rows: [Row]
}

/// Starred parks, most visited first, each with a one-line open/closed state.
struct TopParksProvider: TimelineProvider {
    /// Longest timeline we hand out; iOS asks again after the last entry.
    private static let maxEntries = 48

    func placeholder(in context: Context) -> TopParksEntry { entry(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (TopParksEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopParksEntry>) -> Void) {
        let now = Date()
        let parks = topParks(limit: Self.rowLimit(for: context.family))
        let dates = parks
            .flatMap { ParkWidgetTimeline.changeDates(for: $0.opening, after: now, timeZone: $0.resolvedTimeZone) }
        let moments = Array(Set(dates).sorted().prefix(Self.maxEntries - 1))
        let entries = ([now] + moments).map { entry(at: $0, parks: parks) }
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? now.addingTimeInterval(3600))))
    }

    static func rowLimit(for family: WidgetFamily) -> Int { family == .systemMedium ? 6 : 3 }

    private func topParks(limit: Int) -> [Park] {
        ParkWidgetStore.snapshot().topFavorites(in: ParkWidgetStore.parks(), limit: limit)
    }

    private func entry(at date: Date, parks: [Park]? = nil) -> TopParksEntry {
        let parks = parks ?? topParks(limit: 6)
        return TopParksEntry(
            date: date,
            rows: parks.map { .init(id: $0.id, name: $0.compactName, state: .make(for: $0, at: date)) }
        )
    }
}

struct TopParksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.dcsbl.rppl.topParks", provider: TopParksProvider()) { entry in
            TopParksView(entry: entry)
        }
        .configurationDisplayName("Top parks")
        .description("Your starred parks, most visited first, with open or closed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TopParksView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TopParksEntry

    /// Up to 3 parks on the medium widget use the whole width, one per line.
    private var isWide: Bool { family == .systemMedium && entry.rows.count <= 3 }

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                WidgetEmptyState(
                    symbol: "star",
                    title: "No favourites yet",
                    hint: family == .systemMedium
                        ? "Star parks in Rppl and they show here with their opening hours."
                        : "Star parks in Rppl."
                )
            } else if family == .systemMedium && !isWide {
                let left = Array(entry.rows.prefix(3))
                let right = Array(entry.rows.dropFirst(3).prefix(3))
                HStack(alignment: .top, spacing: 12) {
                    column(left)
                    column(right)
                }
            } else {
                column(Array(entry.rows.prefix(3)))
            }
        }
        // A tap opens the Parks tab on nearby parks with the Favourites filter on.
        .widgetURL(ParkDeepLink.favoritesURL)
        .containerBackground(for: .widget) { RpplWidgetBackground() }
    }

    private func column(_ rows: [TopParksEntry.Row]) -> some View {
        VStack(alignment: .leading, spacing: isWide ? 9 : 8) {
            ForEach(rows) { row in rowView(row) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Text shrinks to 70% before it is cut off. On the wide layout it may wrap to two lines first.
    private func rowView(_ row: TopParksEntry.Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.name)
                .font(isWide ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                .foregroundStyle(Color("RpplText"))
                .lineLimit(isWide ? 2 : 1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Circle().fill(row.state.tint).frame(width: isWide ? 7 : 6, height: isWide ? 7 : 6)
                Text(row.state.shortText)
                    .font(isWide ? .caption : .caption2)
                    .foregroundStyle(Color("RpplMuted"))
                    .lineLimit(isWide ? 2 : 1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ParkWidgetState {
    /// One short line for the list: "Open until 19:00", "Open from 12:00 to 21:00", "Closed".
    var shortText: String {
        switch self {
        case .openUntil(let window):
            let to = Self.end(window)
            return String(localized: "Open until \(to)")
        case .opensToday(let window):
            let from = ParkSchedule.timeText(minutes: window.startMinute)
            let to = Self.end(window)
            return String(localized: "Open from \(from) to \(to)")
        case .opensTomorrow: return String(localized: "Open tomorrow")
        case .opensInDays(let days): return String(localized: "Open in \(days) days")
        case .closed: return String(localized: "Closed")
        case .unknown: return String(localized: "Hours unknown")
        }
    }
}
