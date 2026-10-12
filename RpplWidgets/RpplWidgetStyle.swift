import SwiftUI

/// The calm Rppl gradient with an accent glow (same look as `RpplBackdrop` in the app).
struct RpplWidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color("RpplBackdropTop"), Color("RpplBackdropBottom")],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [Color("RpplAccent").opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 200
            )
        }
    }
}
