import SwiftUI
import RpplCore

/// Product session UI: one-screen set view; Inactive overview has a sticky current-block header,
/// flowing metrics below it, then a last-set block that scroll-snaps fully into view.
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

    // MARK: - Riding (no scroll — fitted for AWU)

    private var ridingView: some View {
        VStack(spacing: 4) {
            Text(SessionFormatters.segmentDuration(session.currentSetDuration))
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("RIDE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .alwaysOnSecondaryChrome(isLuminanceReduced)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(spacing: 2) {
                    Text(SessionFormatters.distance(session.displaySetMeters))
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text("DIST")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchMetric.distance.tint)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(session.currentSetSpeedKmh.map { DistanceFormat.speedValue($0) } ?? "--")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text(DistanceFormat.speedUnitSymbol().uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchMetric.speed.tint)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(session.currentSetLapCount)")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text("LAPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchMetric.laps.tint)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)
            }

            heartRateRow

            statusLine(primary: "Riding", color: .blue)

            if session.didCompleteSet {
                lastSetCompactLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private var lastSetCompactLine: some View {
        HStack(spacing: 4) {
            Text("Last")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                "\(SessionFormatters.segmentDuration(session.lastSetDuration)) · "
                    + "\(SessionFormatters.distance(session.lastSetMeters)) · "
                    + "\(session.lastSetLapCount)"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lastSetAccessibilityLabel)
        .alwaysOnSecondaryChrome(isLuminanceReduced)
    }

    private var lastSetAccessibilityLabel: String {
        String(
            localized: "Last set \(SessionFormatters.segmentDuration(session.lastSetDuration)), \(SessionFormatters.distance(session.lastSetMeters)), \(session.lastSetLapCount) laps"
        )
    }

    // MARK: - Inactive (sticky current block on top; flowing metrics below; last-set block snaps in)

    /// Live GPS speed regardless of detection state — distinct from `sessionAverageSpeedKmh`.
    private var currentSpeedKmh: Double? {
        session.lastSpeedMps.map { $0 * 3.6 }
    }

    private var inactiveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let calories = session.activeEnergyKilocalories {
                    SessionMetricRow(
                        label: "Calories",
                        metric: .energy,
                        value: SessionFormatters.calories(calories),
                        isLarge: true
                    )
                }
                if let averageSpeed = session.sessionAverageSpeedKmh {
                    SessionMetricRow(
                        label: "Avg speed",
                        metric: .speed,
                        value: SessionFormatters.averageSpeed(averageSpeed),
                        isLarge: true
                    )
                }

                // Only this block registers as a scroll-snap target (`.scrollTargetLayout()`),
                // so calories/avg speed above scroll freely; this snaps fully into view once
                // reached. First use of view-aligned scroll-snap in RpplWatch — verify feel
                // on-device and retune if the snap threshold feels off.
                LazyVStack {
                    lastSetSnapBlock
                }
                .scrollTargetLayout()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 10)
        }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaInset(edge: .top) {
            inactiveStickyHeader
        }
    }

    private var inactiveStickyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine(primary: "Inactive", color: .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionFormatters.elapsed(session.elapsed))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.yellow)
                WatchMetricCaption(label: "Session", metric: .duration)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                SessionMetricRow(
                    label: "Inactive for",
                    metric: .inactive,
                    value: SessionFormatters.segmentDuration(session.currentInactiveDuration),
                    isLarge: true
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(session.setCount)",
                    isLarge: true
                )
                if let currentSpeedKmh {
                    SessionMetricRow(
                        label: "Speed",
                        metric: .speed,
                        value: SessionFormatters.averageSpeed(currentSpeedKmh),
                        isLarge: true
                    )
                }
                if session.waterTemperatureAvailable {
                    SessionMetricRow(
                        label: "Water",
                        metric: .water,
                        value: session.averageWaterTemperatureCelsius.map { SessionFormatters.waterTemp($0) }
                            ?? TemperatureFormat.placeholder,
                        isLarge: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        // Opaque backing — without it, content scrolling up behind this pinned header shows
        // through instead of being hidden by it.
        .background(.black)
    }

    private var lastSetSnapBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            WatchMetricCaption(label: "Last set", metric: .sets)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .alwaysOnSecondaryChrome(isLuminanceReduced)

            if session.didCompleteSet {
                SessionMetricRow(
                    label: "Duration",
                    metric: .duration,
                    value: SessionFormatters.segmentDuration(session.lastSetDuration),
                    isLarge: true
                )
                SessionMetricRow(
                    label: "Distance",
                    metric: .distance,
                    value: SessionFormatters.distance(session.lastSetMeters),
                    isLarge: true
                )
                SessionMetricRow(
                    label: "Laps",
                    metric: .laps,
                    value: "\(session.lastSetLapCount)",
                    isLarge: true
                )
            } else {
                Text("No sets yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .containerRelativeFrame(.vertical)
    }

    @ViewBuilder
    private func statusLine(primary: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(primary)
                .font(.headline.bold())
                .foregroundStyle(color)
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
