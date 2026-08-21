import SwiftUI
import RpplCore

struct SyncStatusIndicator: View {
    let state: SyncConnectionState
    var pendingCount: Int = 0
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if pendingCount > 0 {
                    Text("Pending: \(pendingCount)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Sync \(state.title)"))
        .accessibilityValue(state.detail)
    }

    private var color: Color {
        switch state {
        case .readyLive:
            return .green
        case .readyQueued:
            return .orange
        case .unsupported, .notActivated, .inactive, .notPaired, .watchAppMissing, .companionMissing:
            return .red
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        SyncStatusIndicator(state: .readyLive)
        SyncStatusIndicator(state: .readyQueued, pendingCount: 2)
        SyncStatusIndicator(state: .notPaired)
    }
    .padding()
}
