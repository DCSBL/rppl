import RpplCore
import SwiftUI
import WidgetKit

struct LastSessionEntry: TimelineEntry {
    let date: Date
    /// `nil` until the logbook has a session.
    let session: LastSessionWidgetSnapshot?
}

/// The newest logbook session. The app writes it to the App Group and reloads the timeline.
struct LastSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastSessionEntry {
        let now = Date()
        return LastSessionEntry(date: now, session: LastSessionWidgetSnapshot(
            sessionId: "", place: "Cable Park", startedAt: now.addingTimeInterval(-9000), endedAt: now,
            duration: 9000, ridingRatio: 0.42, ridingDuration: 3300, inactiveDuration: 4500,
            setCount: 5, lapCount: 12,
            setSpans: [0.04...0.14, 0.24...0.38, 0.48...0.58, 0.7...0.82, 0.9...0.97]
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (LastSessionEntry) -> Void) {
        let stored = LastSessionWidgetStore.load()
        completion(context.isPreview && stored == nil ? placeholder(in: context) : LastSessionEntry(date: Date(), session: stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastSessionEntry>) -> Void) {
        completion(Timeline(entries: [LastSessionEntry(date: Date(), session: LastSessionWidgetStore.load())], policy: .never))
    }
}

struct LastSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.dcsbl.rppl.lastSession", provider: LastSessionProvider()) { entry in
            LastSessionView(entry: entry)
        }
        .configurationDisplayName("Last session")
        .description("Place, sets, laps, riding and inactive time of your latest session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LastSessionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastSessionEntry

    var body: some View {
        Group {
            if let session = entry.session {
                if family == .systemMedium { medium(session) } else { small(session) }
            } else {
                WidgetEmptyState(
                    symbol: "flag.checkered",
                    title: "No sessions yet",
                    hint: family == .systemMedium
                        ? "Record a session on your Watch and your latest one shows here."
                        : "Record a session on your Watch."
                )
            }
        }
        .widgetURL(entry.session.flatMap { SessionDeepLink.url(forSessionID: $0.sessionId) })
        .dynamicTypeSize(...DynamicTypeSize.widgetMaximum)
        .containerBackground(for: .widget) { RpplWidgetBackground() }
    }

    // MARK: Layouts

    /// At larger text sizes the times and the bar go first, then the counts: the place always stays.
    private func small(_ session: LastSessionWidgetSnapshot) -> some View {
        ViewThatFits(in: .vertical) {
            small(session, showsCounts: true, showsTimes: true)
            small(session, showsCounts: true, showsTimes: false)
            small(session, showsCounts: false, showsTimes: false)
        }
    }

    private func small(_ session: LastSessionWidgetSnapshot, showsCounts: Bool, showsTimes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(session)
            Spacer(minLength: 0)
            if showsCounts {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    count(session.setCount, symbol: "flag.checkered", tint: "RpplMetricSets", caption: "Sets")
                    count(session.lapCount, symbol: "arrow.triangle.2.circlepath", tint: "RpplMetricLaps", caption: "Laps")
                }
            }
            if !showsTimes {
                EmptyView()
            } else if let ratio = session.ridingRatio {
                VStack(alignment: .leading, spacing: 3) {
                    if let riding = session.ridingDuration, let inactive = session.inactiveDuration {
                        timesGrid(riding: riding, inactive: inactive)
                    } else {
                        durationText(session).font(.caption.weight(.semibold).monospacedDigit())
                    }
                    WidgetBar(fraction: ratio, tint: "RpplMetricRiding")
                }
            } else {
                durationText(session).font(.caption.weight(.semibold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The timeline bar, then the ring with its times, go first at larger text sizes.
    private func medium(_ session: LastSessionWidgetSnapshot) -> some View {
        ViewThatFits(in: .vertical) {
            medium(session, showsRing: true, showsTimeline: true)
            medium(session, showsRing: true, showsTimeline: false)
            medium(session, showsRing: false, showsTimeline: false)
        }
    }

    private func medium(_ session: LastSessionWidgetSnapshot, showsRing: Bool, showsTimeline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    header(session)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        count(session.setCount, symbol: "flag.checkered", tint: "RpplMetricSets", caption: "Sets", large: true)
                        count(session.lapCount, symbol: "arrow.triangle.2.circlepath", tint: "RpplMetricLaps", caption: "Laps", large: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !showsRing {
                    EmptyView()
                } else if let ratio = session.ridingRatio {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetRing(fraction: ratio, tint: "RpplMetricRiding")
                            .frame(width: 44, height: 44)
                            .frame(maxWidth: .infinity)
                        if let riding = session.ridingDuration, let inactive = session.inactiveDuration {
                            timesGrid(riding: riding, inactive: inactive)
                        } else {
                            durationText(session).font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else if session.duration != nil {
                    durationText(session).font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
            if showsTimeline, !session.setSpans.isEmpty {
                VStack(spacing: 2) {
                    WidgetTimelineBar(spans: session.setSpans, tint: "RpplMetricSets")
                    HStack {
                        Text(session.startedAt, format: .dateTime.hour().minute())
                        Spacer()
                        Text(session.endedAt, format: .dateTime.hour().minute())
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color("RpplMuted"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Pieces

    /// Place (wraps and shrinks before it clips) with the start date under it.
    private func header(_ session: LastSessionWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.place ?? String(localized: "Session"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("RpplText"))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(session.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.caption2)
                .foregroundStyle(Color("RpplMuted"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Coloured symbol + count; an unknown count (manual session) reads "-" like the app.
    private func count(
        _ value: Int?, symbol: String, tint: String, caption: LocalizedStringKey, large: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(Color(tint))
                Text(value.map(String.init) ?? "-")
                    .font((large ? Font.title2 : .title3).bold().monospacedDigit())
                    .foregroundStyle(Color("RpplText"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(caption).font(.caption2).foregroundStyle(Color("RpplMuted"))
        }
    }

    /// Riding and Inactive stacked: icons left, numbers right-aligned so h / m / s line up.
    /// The hours column is dropped when neither time has hours.
    private func timesGrid(riding: TimeInterval, inactive: TimeInterval) -> some View {
        let showHours = DurationFormat.parts(riding).hours > 0 || DurationFormat.parts(inactive).hours > 0
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 3, verticalSpacing: 2) {
            timeRow(riding, symbol: "figure.surfing", tint: "RpplMetricRiding", label: "Riding", showHours: showHours)
            timeRow(inactive, symbol: "pause.circle", tint: "RpplMuted", label: "Inactive", showHours: showHours)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(Color("RpplText"))
        .lineLimit(1)
    }

    private func timeRow(
        _ interval: TimeInterval, symbol: String, tint: String, label: LocalizedStringKey, showHours: Bool
    ) -> some View {
        let parts = DurationFormat.parts(interval)
        return GridRow {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(Color(tint))
                .gridColumnAlignment(.leading)
                .accessibilityLabel(label)
                .accessibilityValue(DurationFormat.units(interval.rounded(), width: .narrow))
            if showHours { unitCells(parts.hours > 0 ? "\(parts.hours)" : "", "h") }
            unitCells("\(parts.minutes)", "m")
            unitCells(String(format: "%02d", parts.seconds), "s")
        }
    }

    /// Number (right-aligned) and unit (left-aligned); an empty number leaves both cells blank.
    @ViewBuilder
    private func unitCells(_ number: String, _ unit: String) -> some View {
        Text(number).gridColumnAlignment(.trailing).accessibilityHidden(true)
        Text(number.isEmpty ? "" : unit)
            .accessibilityHidden(true)
            .font(.caption2)
            .foregroundStyle(Color("RpplMuted"))
            .gridColumnAlignment(.leading)
    }

    @ViewBuilder
    private func durationText(_ session: LastSessionWidgetSnapshot) -> some View {
        if let duration = session.duration {
            Text(DurationFormat.units(max(0, duration.rounded()), width: .narrow)).foregroundStyle(Color("RpplText"))
        }
    }
}

// MARK: Drawing (same look as the app's BarGaugeStyle, RingGaugeStyle and TimelineBar)

private struct WidgetBar: View {
    let fraction: Double
    let tint: String

    var body: some View {
        Capsule()
            .fill(Color(tint).opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if fraction > 0 {
                        Capsule().fill(Color(tint)).frame(width: max(8, proxy.size.width * min(fraction, 1)))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
    }
}

private struct WidgetRing: View {
    let fraction: Double
    let tint: String

    var body: some View {
        ZStack {
            Circle().stroke(Color(tint).opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Color(tint), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.footnote.bold().monospacedDigit())
                .foregroundStyle(Color("RpplText"))
                .minimumScaleFactor(0.6)
                .padding(7)
        }
    }
}

/// One tinted segment per set at its real start and length (fractions of the session).
private struct WidgetTimelineBar: View {
    let spans: [ClosedRange<Double>]
    let tint: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(tint).opacity(0.15))
                ForEach(spans.indices, id: \.self) { index in
                    Rectangle()
                        .fill(Color(tint))
                        .frame(width: max(2, proxy.size.width * (spans[index].upperBound - spans[index].lowerBound)))
                        .offset(x: proxy.size.width * spans[index].lowerBound)
                }
            }
        }
        .frame(height: 10)
        .clipShape(.rect(cornerRadius: 10 / 3, style: .continuous))
        .accessibilityHidden(true)
    }
}
