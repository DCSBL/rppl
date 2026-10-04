import SwiftUI
import RpplCore

struct SyncStatusIndicator: View {
    let state: SyncConnectionState
    var pendingCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rpplIdlePrimary)
                Text(state.detail)
                    .font(.caption2)
                    .foregroundStyle(Color.rpplIdlePrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if pendingCount > 0 {
                    Text("Pending: \(pendingCount)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Sync \(shortTitle)"))
        .accessibilityValue(state.detail)
    }

    private var shortTitle: String {
        switch state {
        case .readyLive: return String(localized: "Phone connected")
        case .readyQueued: return String(localized: "Ready to sync")
        default: return state.title
        }
    }

    private var color: Color {
        switch state {
        case .readyLive: return .green
        case .readyQueued: return .orange
        default: return .red
        }
    }
}
