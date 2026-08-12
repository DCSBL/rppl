import SwiftUI
import WatchKit
import WakeTrackerCore

struct ContentView: View {
    @State private var session = WatchSessionController.shared
    @State private var transfer = WatchTransferService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SyncStatusIndicator(
                    state: transfer.syncState,
                    pendingCount: transfer.pendingTransferCount,
                    footnote: transfer.lastMessage
                )

                Text(session.statusText)
                    .font(.headline)

                if session.isRunning {
                    Text(session.currentLabel.uppercased())
                        .font(.title2.bold())
                    Text("assume \(session.assumedLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeString(session.elapsed))
                        .monospacedDigit()
                    Text("Mode: \(session.recordingMode)")
                        .font(.caption2)
                    Text("GPS \(session.locationCount)  MOT \(session.motionCount)  LBL \(session.labelCount)  ASM \(session.assumptionCount)")
                        .font(.caption2)
                    Text("Stored \(ByteSizeFormat.string(session.storedByteSize))")
                        .font(.caption2)
                        .monospacedDigit()
                    if !session.motionRecordingEnabled {
                        Text("Motion skipped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let lat = session.lastLatitude, let lon = session.lastLongitude {
                        Text(String(format: "%.5f, %.5f", lat, lon))
                            .font(.caption2)
                            .monospaced()
                    }
                    if let hr = session.lastHeartRate {
                        Text(String(format: "HR %.0f", hr))
                            .font(.caption2)
                    }

                    Button("Cycle label") {
                        WakeLog.debug(.ui, "tap Cycle label")
                        session.cycleLabelFromActionButton()
                    }

                    Button("Stop session", role: .destructive) {
                        WakeLog.debug(.ui, "tap Stop session")
                        Task { await session.stopSession() }
                    }
                } else {
                    Button("Start session") {
                        WakeLog.debug(.ui, "tap Start session")
                        Task { await session.startSession() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Request permissions") {
                        WakeLog.debug(.ui, "tap Request permissions")
                        Task { await session.requestPermissions() }
                    }

                    Button("Retry transfers") {
                        WakeLog.debug(.ui, "tap Retry transfers")
                        transfer.transferPending()
                    }

                    Group {
                        Text(session.healthAuthStatus)
                        Text("Location: \(session.locationAuthStatus)")
                        Text("Motion: \(session.motionAvailability)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if let error = session.errorText {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Text("Action Button: Workout › Wake Tracker (or Shortcut › Cycle Label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            WakeLog.debug(.lifecycle, "Watch ContentView onAppear")
            transfer.activate()
            transfer.refreshSyncState()
            session.refreshPermissionStatus()
            Task { await session.requestPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            WakeLog.debug(.lifecycle, "WKApplication.didBecomeActive")
            transfer.refreshSyncState()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

#Preview {
    ContentView()
}
