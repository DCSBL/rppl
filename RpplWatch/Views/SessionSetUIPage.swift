import SwiftUI
import RpplCore

/// Product session UI: Riding and Inactive share one fixed status block (`statusBlock`) — only
/// color/icon/label and a couple of source values differ. Riding shows it alone, not scrollable.
/// Inactive pins it as a sticky header above a scroll-snap session summary.
struct SessionSetUIPage: View {
    @Bindable var session: WatchSessionController
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if session.isProductPaused {
                pausedView
            } else if session.lastConfidentCode == DetectionCodes.riding {
                ridingView
            } else {
                inactiveView
            }
        }
    }

    // MARK: - Product paused

    private var pausedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paused")
                    .font(.headline.bold())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                Text(SessionFormatters.elapsed(session.elapsed))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("Timers paused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                SessionMetricRow(
                    label: "Distance",
                    metric: .distance,
                    value: SessionFormatters.distance(session.totalDistanceM)
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(session.setCount)"
                )

                WatchLastSetSection(
                    duration: session.lastSetDuration,
                    distanceMeters: session.lastSetMeters,
                    lapCount: session.lastSetLapCount,
                    didCompleteSet: session.didCompleteSet
                )
                .alwaysOnSecondaryChrome(isLuminanceReduced)

                Button("Resume") {
                    WakeLog.debug(.ui, "tap Resume from paused metrics")
                    session.resumeSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(session.isStopping)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Riding (no scroll — fitted for AWU) / Inactive (sticky header + scroll-snap summary)

    private var ridingView: some View {
        statusBlock(isRiding: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inactiveView: some View {
        ScrollView {
            // Only this block registers as a scroll-snap target (`.scrollTargetLayout()`).
            // First use of view-aligned scroll-snap in RpplWatch — verify feel on-device and
            // retune if the snap threshold feels off.
            LazyVStack {
                sessionSummarySnapBlock
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaInset(edge: .top) {
            statusBlock(isRiding: false)
                // Opaque backing — without it, content scrolling up behind this pinned header
                // shows through instead of being hidden by it.
                .background(.black)
        }
    }

    /// Shared Riding/Inactive block: wall clock, status line, hero segment/total time, then
    /// distance/speed/laps, water temp, heart rate and total calories. Identical layout for both
    /// states — only color/icon/label and the segment-time/speed source differ.
    private func statusBlock(isRiding: Bool) -> some View {
        let speedKmh = isRiding ? session.currentSetSpeedKmh : session.lastSpeedMps.map { $0 * 3.6 }
        let lapCount = session.isSetOngoing ? session.currentSetLapCount : session.lastSetLapCount

        return VStack(alignment: .leading, spacing: 8) {
            Text(Date(), style: .time)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            statusLine(
                primary: isRiding ? "Riding" : "Inactive",
                color: isRiding ? .blue : .gray,
                icon: isRiding ? "play.fill" : "pause.circle.fill"
            )

            heroTimeRow(isRiding: isRiding)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                metricTile(
                    value: SessionFormatters.distance(session.displaySetMeters),
                    label: "DIST",
                    metric: .distance
                )
                metricTile(
                    value: speedKmh.map { DistanceFormat.speedValue($0) } ?? "--",
                    label: DistanceFormat.speedUnitSymbol(),
                    metric: .speed
                )
                metricTile(
                    value: "\(lapCount)",
                    label: "LAPS",
                    metric: .laps
                )
            }

            if session.waterTemperatureAvailable {
                metricTile(
                    value: session.averageWaterTemperatureCelsius.map { SessionFormatters.waterTemp($0) }
                        ?? TemperatureFormat.placeholder,
                    label: "WATER",
                    metric: .water
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if !isRiding {
                Text("Last session")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heartRateRow
                    .frame(maxWidth: .infinity)
                metricTile(
                    value: session.totalEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                    label: "CAL",
                    metric: .energy
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, isRiding ? 4 : 8)
    }

    private func heroTimeRow(isRiding: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(spacing: 4) {
                Text(
                    SessionFormatters.segmentDuration(
                        isRiding ? session.currentSetDuration : session.currentInactiveDuration
                    )
                )
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(isRiding ? .blue : .gray)

                if isRiding {
                    // `.variableColor` no-ops if "water.waves" doesn't declare that capability —
                    // verify on-device it actually animates; drop the modifier if it doesn't.
                    Image(systemName: "water.waves")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .accessibilityHidden(true)
                }
            }

            Text("/")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(SessionFormatters.elapsed(session.elapsed))
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .alwaysOnSupportingMetric(isLuminanceReduced)
    }

    private func metricTile(value: String, label: String, metric: WatchMetric) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .alwaysOnSupportingMetric(isLuminanceReduced)
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(metric.tint)
                .alwaysOnSecondaryChrome(isLuminanceReduced)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session summary (Inactive only; scroll-snaps in below the sticky status block)

    private var totalRidingDuration: TimeInterval {
        session.cumulativeRidingDuration + (session.lastConfidentCode == DetectionCodes.riding ? session.currentSetDuration : 0)
    }

    private var totalInactiveDuration: TimeInterval {
        session.cumulativeInactiveDuration
            + (session.lastConfidentCode == DetectionCodes.inactive ? session.currentInactiveDuration : 0)
    }

    private var sessionSummarySnapBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            WatchMetricCaption(label: "Session summary", metric: .sets)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .alwaysOnSecondaryChrome(isLuminanceReduced)

            SessionMetricRow(label: "Sets", metric: .sets, value: "\(session.setCount)", isLarge: true)
            SessionMetricRow(
                label: "Distance",
                metric: .distance,
                value: SessionFormatters.distance(session.totalDistanceM),
                isLarge: true
            )
            SessionMetricRow(
                label: "Duration",
                metric: .duration,
                value: SessionFormatters.elapsed(session.elapsed),
                isLarge: true
            )
            SessionMetricRow(
                label: "Riding time",
                metric: .duration,
                value: SessionFormatters.segmentDuration(totalRidingDuration),
                isLarge: true
            )
            SessionMetricRow(
                label: "Inactive time",
                metric: .inactive,
                value: SessionFormatters.segmentDuration(totalInactiveDuration),
                isLarge: true
            )
            SessionMetricRow(
                label: "Calories",
                metric: .energy,
                value: session.totalEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                isLarge: true
            )
            SessionMetricRow(
                label: "Active calories",
                metric: .energy,
                value: session.activeEnergyKilocalories.map { SessionFormatters.calories($0) } ?? "--",
                isLarge: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .containerRelativeFrame(.vertical)
    }

    @ViewBuilder
    private func statusLine(primary: LocalizedStringKey, color: Color, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(primary)
                    .font(.headline.bold())
                    .foregroundStyle(color)
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            if session.isUnsure {
                Text("Unsure")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .alwaysOnSecondaryChrome(isLuminanceReduced)
    }

    private var heartRateRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let hr = session.lastHeartRate {
                Text(String(format: "%.0f", hr))
                    .font(.system(.title3, design: .rounded).bold())
                    .monospacedDigit()
            } else {
                Text("- BPM")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heartRateAccessibilityLabel)
        .alwaysOnSupportingMetric(isLuminanceReduced)
    }

    private var heartRateAccessibilityLabel: String {
        if let hr = session.lastHeartRate {
            return String(format: String(localized: "Heart rate %@ beats per minute"), String(format: "%.0f", hr))
        }
        return String(localized: "Heart rate unavailable")
    }
}
