import SwiftUI

/// Calm full-screen gradient behind tile screens (light + dark via asset colors).
struct RpplBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.rpplBackdropTop, Color.rpplBackdropBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [Color.rpplAccent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func rpplBackdrop() -> some View {
        background { RpplBackdrop() }
    }
}
