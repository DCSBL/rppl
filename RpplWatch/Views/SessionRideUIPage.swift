import SwiftUI
import RpplCore

/// Product session UI: one-screen ride view; scrollable pause overview.
struct SessionRideUIPage: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        Group {
            if session.lastConfidentCode == DetectionCodes.riding {
                ridingView
            } else {
                pausedView
            }
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
            }

            statusLine(primary: "Riding", color: .blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: - Paused (scrollable overview)

    private var pausedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusLine(primary: "Paused", color: .gray)

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
                    label: "Paused for",
                    value: SessionFormatters.segmentDuration(session.currentPauseDuration)
                )

                if let hr = session.lastHeartRate {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", hr))
                            .font(.system(.title3, design: .rounded).bold())
                            .monospacedDigit()
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
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
    private func statusLine(primary: String, color: Color) -> some View {
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
}
