import SwiftUI
import RpplCore

struct IdleSessionView: View {
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StartCircleButton {
                    WakeLog.debug(.ui, "tap Start session")
                    Task { await session.startSession() }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    SyncStatusIndicator(
                        state: transfer.syncState,
                        pendingCount: transfer.pendingTransferCount,
                        footnote: transfer.lastMessage
                    )

                    if session.statusText != "Idle" {
                        Text(session.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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

                    if let error = session.errorText {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Text("Action Button: Workout › Rppl (start only)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
    }
}
