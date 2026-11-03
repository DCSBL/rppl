import SwiftUI
import RpplCore

/// One bar per wait between sets, in session order, so a long queue stands out at a glance.
/// Waits above the typical one are solid, the rest are muted.
struct DockWaitBars: View {
    let gaps: [TimeInterval]
    let median: TimeInterval
    var tint: Color = RpplDesign.headerColor

    private let maxHeight: CGFloat = 36
    private let minHeight: CGFloat = 4

    var body: some View {
        let longest = max(gaps.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(gap > median ? 1 : 0.4))
                        .frame(height: max(minHeight, maxHeight * gap / longest))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
            Text("Each bar is the wait before a set")
                .font(.caption2)
                .foregroundStyle(RpplDesign.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Waits between sets"))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        guard let shortest = gaps.min(), let longest = gaps.max() else { return "" }
        return "\(LogbookFormatting.dockWait(shortest)) – \(LogbookFormatting.dockWait(longest))"
    }
}
