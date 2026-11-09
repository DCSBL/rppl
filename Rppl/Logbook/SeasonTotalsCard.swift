import RpplCore
import SwiftUI

/// The "Total" tile: sessions, distance and speed over the whole logbook. Shown in the Logbook and on the
/// Statistics tab. A tap on a figure cycles what it shows (quiet easter egg, no visual affordance); the
/// choice is stored, so both tabs show the same.
struct SeasonTotalsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppSettingsKey.speedTotal) private var speedTotal = SpeedTotal.max
    @AppStorage(AppSettingsKey.countTotal) private var countTotal = CountTotal.sessions
    @AppStorage(AppSettingsKey.distanceTotal) private var distanceTotal = DistanceTotal.distance

    let season: SeasonStats
    let isLoading: Bool

    private var useAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        let loading = isLoading
        let countLabel: LocalizedStringKey
        let countValue: Int
        switch countTotal {
        case .sessions:
            countLabel = "Sessions"
            countValue = season.sessionCount
        case .sets:
            countLabel = "Sets"
            countValue = season.totalSets
        case .laps:
            countLabel = "Laps"
            countValue = season.totalLaps
        }
        let sessionsValue = loading ? "-" : "\(countValue)"

        let distanceLabel: LocalizedStringKey
        let distanceValue: String
        switch distanceTotal {
        case .distance:
            distanceLabel = "Distance"
            distanceValue = DistanceFormat.kilometers(season.totalDistanceMeters, fixedFraction: 1)
        case .duration:
            distanceLabel = "Total time"
            distanceValue = DurationFormat.total(season.totalDuration, fractionDigits: 1)
        case .riding:
            distanceLabel = "Total riding time"
            distanceValue = DurationFormat.total(season.totalRidingDuration, fractionDigits: 1)
        }

        let speedLabel: LocalizedStringKey = speedTotal == .max ? "Maximum speed" : "Average speed"
        let speedShortLabel: LocalizedStringKey = speedTotal == .max ? "Max speed" : "Avg speed"
        let speed = speedTotal == .max ? season.topSpeedKmh : season.typicalSpeedKmh
        let speedValue = if let speed, speed > 0 { DistanceFormat.kilometersPerHour(speed) } else { "-" }

        return InfoTile("Total", metric: .riding) {
            AdaptiveStack(spacing: useAccessibilityLayout ? 12 : 0) {
                totalMetric(value: sessionsValue, label: countLabel, id: "logbook-total-sessions") {
                    countTotal = countTotal.cycled()
                }
                totalDivider(horizontal: useAccessibilityLayout)
                totalMetric(value: loading ? "-" : distanceValue, label: distanceLabel, id: "logbook-total-distance") {
                    distanceTotal = distanceTotal.cycled()
                }
                totalDivider(horizontal: useAccessibilityLayout)
                totalMetric(value: loading ? "-" : speedValue, label: speedLabel, shortLabel: speedShortLabel, id: "logbook-total-speed") {
                    speedTotal = speedTotal.cycled()
                }
            }
            .sensoryFeedback(.selection, trigger: countTotal)
            .sensoryFeedback(.selection, trigger: speedTotal)
            .sensoryFeedback(.selection, trigger: distanceTotal)
        }
    }

    private func totalDivider(horizontal: Bool) -> some View {
        Rectangle()
            .fill(Color.rpplFill)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : 44)
            .frame(maxWidth: horizontal ? .infinity : nil)
    }

    /// A tap on `action` cycles what the total shows.
    @ViewBuilder
    private func totalMetric(
        value: String,
        label: LocalizedStringKey,
        shortLabel: LocalizedStringKey? = nil,
        id: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        // Full label when it fits on one line, else the abbreviation. Never scaled, so the text size
        // stays the same when a tap swaps the metric.
        let content = VStack(spacing: 4) {
            MetricValue(value, size: .total)
            ViewThatFits(in: .horizontal) {
                if shortLabel != nil { Text(label).lineLimit(1) }
                Text(shortLabel ?? label).lineLimit(2)
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(RpplDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "")

        if let action {
            Button(action: action) { content.contentShape(.rect) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
