import SwiftUI
import RpplCore

struct SyncStatusIndicator: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 8
    let state: SyncConnectionState
    var pendingCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if differentiateWithoutColor {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: dotSize, height: dotSize)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .padding(.top, 3)
            }

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

    /// Shape twin of `color` for Differentiate Without Color.
    private var symbol: String {
        switch state {
        case .readyLive: "checkmark"
        case .readyQueued: "clock"
        default: "xmark"
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
