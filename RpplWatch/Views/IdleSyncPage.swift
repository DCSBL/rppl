import SwiftUI
import RpplCore

struct IdleSyncPage: View {
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    var body: some View {
        ViewThatFits(in: .vertical) {
            syncStack(compact: false)
            ScrollView {
                syncStack(compact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
    }

    private func syncStack(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            SyncStatusIndicator(
                state: transfer.syncState,
                pendingCount: transfer.pendingTransferCount,
                footnote: compact ? nil : transfer.lastMessage
            )

            if session.statusText != String(localized: "Idle") {
                Text(session.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 16) {
                syncCircle(
                    systemImage: "lock.shield",
                    label: String(localized: "Permissions")
                ) {
                    WakeLog.debug(.ui, "tap Request permissions")
                    Task { await session.requestPermissions() }
                }
                syncCircle(
                    systemImage: "arrow.clockwise",
                    label: String(localized: "Retry transfers")
                ) {
                    WakeLog.debug(.ui, "tap Retry transfers")
                    transfer.transferPending()
                }
            }

            if let error = session.errorText {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 4)
    }

    private func syncCircle(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.rpplIdleAccentForeground)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.rpplIdleAccent))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.rpplIdlePrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
