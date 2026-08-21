import SwiftUI
import RpplCore

/// Product session UI: one-screen ride view; scrollable inactive overview.
struct SessionRideUIPage: View {
    @Bindable var session: WatchSessionController

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

                Text(SessionFormatters.elapsed(session.elapsed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("Session clock frozen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(session.totalDistanceM)
                )
                SessionMetricRow(
                    label: "Rides",
                    value: "\(session.rideCount)"
                )

                Text("Swipe for Resume")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("RIDE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(spacing: 2) {
                    Text(SessionFormatters.distance(session.displayRideMeters))
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("DIST")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text(session.currentRideSpeedKmh.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("KM/H")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(session.currentRideLapCount)")
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("LAPS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
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

            statusLine(primary: "Riding", color: .blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: - Inactive (scrollable overview)

    private var inactiveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusLine(primary: "Inactive", color: .gray)

                Text("Session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SessionMetricRow(
                    label: "Elapsed",
                    value: SessionFormatters.elapsed(session.elapsed),
                    valueColor: .yellow
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
                        String(localized: "Heart rate \(String(format: "%.0f", hr)) beats per minute")
                    )
                }

                Divider()
                    .padding(.vertical, 2)

                Text("Last ride")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

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
    }

    private var heartRateAccessibilityLabel: String {
        if let hr = session.lastHeartRate {
            return String(localized: "Heart rate \(String(format: "%.0f", hr)) beats per minute")
        }
        return String(localized: "Heart rate unavailable")
    }
}
