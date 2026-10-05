import SwiftUI
import RpplCore

/// Record badge chip; tap shows what the badge means.
///
/// Borderless so it keeps its own tap inside a `List` row whose `NavigationLink` opens the
/// session: tapping the chip explains, tapping anywhere else still navigates.
struct HighlightChip: View {
    let label: String
    let explanation: String
    let systemImage: String
    let tint: Color

    @State private var showsExplanation = false

    var body: some View {
        Button {
            showsExplanation = true
        } label: {
            ParkChip(
                text: label,
                systemImage: systemImage,
                tint: tint,
                fill: tint.opacity(0.14)
            )
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityHint(Text("Shows what this badge means"))
        .popover(isPresented: $showsExplanation) {
            Text(explanation)
                .font(.footnote)
                .padding()
                .frame(maxWidth: 260)
                .presentationCompactAdaptation(.popover)
        }
    }
}

extension HighlightChip {
    init(_ highlight: SessionHighlight) {
        self.init(
            label: LogbookFormatting.sessionHighlightLabel(highlight),
            explanation: LogbookFormatting.sessionHighlightExplanation(highlight),
            systemImage: highlight.badgeIcon,
            tint: highlight.badgeTint
        )
    }

    init(_ highlight: SetHighlight) {
        self.init(
            label: LogbookFormatting.setHighlightLabel(highlight),
            explanation: LogbookFormatting.setHighlightExplanation(highlight),
            systemImage: highlight.badgeIcon,
            tint: highlight.badgeTint
        )
    }
}
