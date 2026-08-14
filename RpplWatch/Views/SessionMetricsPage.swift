import SwiftUI
import RpplCore

struct SessionMetricsPage: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(SessionFormatters.elapsed(session.elapsed))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .foregroundStyle(.yellow)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(session.lastHeartRate.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(.title, design: .rounded).bold())
                        .monospacedDigit()
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(session.totalDistanceM)
                )

                SessionMetricRow(
                    label: "Km/h",
                    value: SessionFormatters.speedKmh(session.lastSpeedMps)
                )

                statusSection

                SessionMetricRow(
                    label: "Rides",
                    value: "\(session.rideCount)"
                )

                if session.lastConfidentCode == DetectionCodes.riding {
                    SessionMetricRow(
                        label: "This ride",
                        value: SessionFormatters.segmentDuration(session.currentRideDuration)
                    )
                }

                if session.lastConfidentCode == DetectionCodes.paused {
                    SessionMetricRow(
                        label: "Paused for",
                        value: SessionFormatters.segmentDuration(session.currentPauseDuration)
                    )
                }

                Divider()
                    .padding(.vertical, 4)

                debugSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusLabel)
                .font(.title3.bold())
                .foregroundStyle(statusColor)
            Text("Status")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if session.detectionCode != session.lastConfidentCode {
                Text("debug: \(session.detectionCode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let lat = session.lastLatitude, let lon = session.lastLongitude {
                Text(String(format: "%.5f, %.5f", lat, lon))
                    .font(.caption2.monospaced())
            }

            if let accuracy = session.lastHorizontalAccuracy, accuracy >= 0 {
                Text(String(format: "GPS accuracy: %.0f m", accuracy))
                    .font(.caption2)
            }

            Text("GPS \(session.locationCount)  MOT \(session.motionCount)  DET \(session.detectionCount)")
                .font(.caption2)
                .monospacedDigit()

            Text("Stored \(ByteSizeFormat.string(session.storedByteSize))")
                .font(.caption2)
                .monospacedDigit()

            Text("Mode: \(session.recordingMode)")
                .font(.caption2)

            if !session.motionRecordingEnabled {
                Text("Motion skipped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Raw code: \(session.detectionCode)")
                .font(.caption2)

            if let rejection = session.filterRejectionReason {
                Text("Filter: \(rejection)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(session.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = session.errorText {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var statusLabel: String {
        switch session.lastConfidentCode {
        case DetectionCodes.riding: return "Riding"
        case DetectionCodes.paused: return "Paused"
        default: return session.lastConfidentCode.capitalized
        }
    }

    private var statusColor: Color {
        switch session.lastConfidentCode {
        case DetectionCodes.riding: return .blue
        case DetectionCodes.paused: return .gray
        default: return .secondary
        }
    }
}
