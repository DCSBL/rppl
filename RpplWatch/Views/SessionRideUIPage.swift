import SwiftUI
import RpplCore

/// Product session UI: one-screen ride view; scrollable inactive overview.
struct SessionRideUIPage: View {
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
                    value: SessionFormatters.distance(session.totalDistanceM)
                )
                SessionMetricRow(
                    label: "Rides",
                    value: "\(session.rideCount)"
                )

                lastRideSection

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
            Text(SessionFormatters.segmentDuration(session.currentRideDuration))
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
                    Text(SessionFormatters.distance(session.displayRideMeters))
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text("DIST")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(session.currentRideSpeedKmh.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text("KM/H")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(session.currentRideLapCount)")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .alwaysOnSupportingMetric(isLuminanceReduced)
                    Text("LAPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .alwaysOnSecondaryChrome(isLuminanceReduced)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(session.lastHeartRate.map { String(format: "%.0f", $0) } ?? "--")
                    .font(.system(.title3, design: .rounded).bold())
                    .monospacedDigit()
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(heartRateAccessibilityLabel)
            .alwaysOnSupportingMetric(isLuminanceReduced)

            statusLine(primary: "Riding", color: .blue)

            if session.didCompleteRide {
                lastRideCompactLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private var lastRideCompactLine: some View {
        HStack(spacing: 4) {
            Text("Last")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                "\(SessionFormatters.segmentDuration(session.lastRideDuration)) · "
                    + "\(SessionFormatters.distance(session.lastRideMeters)) · "
                    + "\(session.lastRideLapCount)"
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
        .accessibilityLabel(lastRideAccessibilityLabel)
        .alwaysOnSecondaryChrome(isLuminanceReduced)
    }

    private var lastRideAccessibilityLabel: String {
        String(
            localized: "Last ride \(SessionFormatters.segmentDuration(session.lastRideDuration)), \(SessionFormatters.distance(session.lastRideMeters)), \(session.lastRideLapCount) laps"
        )
    }

    // MARK: - Inactive (scrollable overview)

    private var inactiveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusLine(primary: "Inactive", color: .gray)

                Text("Session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                SessionMetricRow(
                    label: "Elapsed",
                    value: SessionFormatters.elapsed(session.elapsed),
                    valueColor: .yellow,
                    isPrimaryMetric: true
                )
                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(session.totalDistanceM)
                )
                SessionMetricRow(
                    label: "Rides",
                    value: "\(session.rideCount)"
                )
                SessionMetricRow(
                    label: "Inactive for",
                    value: SessionFormatters.segmentDuration(session.currentInactiveDuration)
                )
                if session.waterTemperatureAvailable {
                    SessionMetricRow(
                        label: "Water",
                        value: session.averageWaterTemperatureCelsius.map(SessionFormatters.waterTemp)
                            ?? TemperatureFormat.placeholder
                    )
                }

                if let hr = session.lastHeartRate {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", hr))
                            .font(.system(.title3, design: .rounded).bold())
                            .monospacedDigit()
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        String(format: String(localized: "Heart rate %@ beats per minute"), String(format: "%.0f", hr))
                    )
                    .alwaysOnSupportingMetric(isLuminanceReduced)
                }

                Divider()
                    .padding(.vertical, 2)
                    .alwaysOnSecondaryChrome(isLuminanceReduced)

                lastRideSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var lastRideSection: some View {
        Text("Last ride")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .alwaysOnSecondaryChrome(isLuminanceReduced)

        if session.didCompleteRide {
            SessionMetricRow(
                label: "Duration",
                value: SessionFormatters.segmentDuration(session.lastRideDuration)
            )
            SessionMetricRow(
                label: "Distance",
                value: SessionFormatters.distance(session.lastRideMeters)
            )
            SessionMetricRow(
                label: "Laps",
                value: "\(session.lastRideLapCount)"
            )
        } else {
            Text("No rides yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .alwaysOnSecondaryChrome(isLuminanceReduced)
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

    private var heartRateAccessibilityLabel: String {
        if let hr = session.lastHeartRate {
            return String(format: String(localized: "Heart rate %@ beats per minute"), String(format: "%.0f", hr))
        }
        return String(localized: "Heart rate unavailable")
    }
}
