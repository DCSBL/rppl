import SwiftUI
import WakeTrackerCore

struct SyncStatusIndicator: View {
    let state: SyncConnectionState
    var pendingCount: Int = 0
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortTitle)
                    .font(.caption.weight(.semibold))
                Text(state.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if pendingCount > 0 {
                    Text("Pending: \(pendingCount)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var shortTitle: String {
        switch state {
        case .readyLive: return "Phone connected"
        case .readyQueued: return "Ready to sync"
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
