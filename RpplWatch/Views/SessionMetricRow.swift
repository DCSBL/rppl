import SwiftUI

struct SessionMetricRow: View {
    let label: LocalizedStringKey
    var metric: WatchMetric?
    let value: String
    var valueColor: Color = .primary
    /// When true, value stays full brightness under Always On (primary hero metric).
    var isPrimaryMetric: Bool = false

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .opacity(primaryValueOpacity)
            WatchMetricCaption(label: label, metric: metric)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .alwaysOnSecondaryChrome(isLuminanceReduced)
        }
    }

    private var primaryValueOpacity: Double {
        guard isLuminanceReduced, !isPrimaryMetric else { return 1 }
        return AlwaysOnLuminance.supportingMetricOpacity
    }
}
