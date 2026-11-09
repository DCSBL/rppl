import RpplCore
import SwiftUI

/// Small `(i)` that explains the g-values: they are measured at the wrist, not on the body.
struct ImpactInfoButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color.rpplMuted)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("About the g-force"))
        .popover(isPresented: $isShown) {
            Text("Measured at your wrist. The real impact on your body is probably lower.")
                .font(.subheadline)
                .padding()
                .frame(idealWidth: 260)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Max g around the set end, laid out like `StatChip`. The bare icon says how it ended: a red fall figure
/// or a green check.
struct SetImpactChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let impactG: Double

    private var isFall: Bool { SetImpact.isFall(impactG) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: isFall ? "figure.fall" : "checkmark")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .foregroundStyle(isFall ? Color.rpplMetricEnergy : Color.rpplMetricRiding)
                    .accessibilityHidden(true)
                Text(SetImpact.label(impactG))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rpplText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
            }
            Text("Max G")
                .font(.caption2)
                .foregroundStyle(RpplDesign.secondaryText)
        }
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isFall ? "Fall" : "Clean"))
    }
}
