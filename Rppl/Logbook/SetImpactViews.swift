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

/// How a set ended, on its card: fall or clean, with the hardest hit around the end.
struct SetEndBadge: View {
    let impactG: Double

    private var isFall: Bool { SetImpact.isFall(impactG) }

    var body: some View {
        HStack(spacing: 6) {
            SessionFallSymbol(kind: isFall ? .fall : .cleanExit, size: 20)
                .accessibilityHidden(true)
            Text(isFall ? LocalizedStringKey("Fall") : LocalizedStringKey("Clean"))
                .font(.subheadline.weight(.semibold))
            Text(SetImpact.label(impactG))
                .font(.subheadline)
                .foregroundStyle(Color.rpplMuted)
            Spacer(minLength: 0)
            if isFall { ImpactInfoButton() }
        }
    }
}
