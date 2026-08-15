import SwiftUI
import RpplCore

struct SessionDebugPage: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Debug")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button(session.detectionSimulationMode.buttonTitle) {
                    WakeLog.debug(.ui, "tap sim \(session.detectionSimulationMode.rawValue)")
                    session.cycleDetectionSimulation()
                }
                .buttonStyle(.bordered)
                .tint(simulationTint)

                Text(statusLabel)
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)

                if session.isUnsure {
                    Text("Unsure (raw: \(session.detectionCode))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

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

                Text("Confident: \(session.lastConfidentCode)")
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var simulationTint: Color {
        switch session.detectionSimulationMode {
        case .detected: return .secondary
        case .pause: return .gray
        case .ride: return .blue
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
