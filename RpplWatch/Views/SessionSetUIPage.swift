import SwiftUI
import RpplCore

/// Product session UI: one-screen set view; fitted inactive overview (extra metrics scroll below a sticky header).
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

    // MARK: - Inactive (fitted; extra metrics scroll in below a sticky header)

    private var inactiveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let calories = session.activeEnergyKilocalories {
                    SessionMetricRow(
                        label: "Calories",
                        metric: .energy,
                        value: SessionFormatters.calories(calories)
                    )
                }
                if let averageSpeed = session.sessionAverageSpeedKmh {
                    SessionMetricRow(
                        label: "Avg speed",
                        metric: .speed,
                        value: SessionFormatters.averageSpeed(averageSpeed)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                statusLine(primary: "Inactive", color: .gray)

                SessionMetricRow(
                    label: "Session",
                    metric: .duration,
                    value: SessionFormatters.elapsed(session.elapsed),
                    valueColor: .yellow,
                    isPrimaryMetric: true
                )
                SessionMetricRow(
                    label: "Inactive for",
                    metric: .inactive,
                    value: SessionFormatters.segmentDuration(session.currentInactiveDuration)
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(session.setCount)"
                )
                if session.waterTemperatureAvailable || session.waterTemperatureDisplay != nil {
                    SessionMetricRow(
                        label: "Water",
                        metric: .water,
                        value: session.waterTemperatureDisplay.map {
                            SessionFormatters.waterTemp($0.celsius, isEstimate: $0.isEstimate)
                        } ?? TemperatureFormat.placeholder
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
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
