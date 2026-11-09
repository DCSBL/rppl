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

/// Max g around the set end, in the row of set figures. The icon says how it ended: red for a fall,
/// a green check for a clean exit. A fall also gets the `(i)`.
struct SetImpactChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let impactG: Double

    private var isFall: Bool { SetImpact.isFall(impactG) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    SessionFallSymbol(kind: isFall ? .fall : .cleanExit, size: 18)
                        .accessibilityHidden(true)
                    Text(SetImpact.label(impactG))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rpplText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Text(isFall ? "Max G, fall" : "Max G, clean")
                    .font(.caption2)
                    .foregroundStyle(RpplDesign.secondaryText)
            }
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            .accessibilityElement(children: .combine)
            if isFall { ImpactInfoButton() }
        }
    }
}
