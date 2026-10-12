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

/// Nothing to show yet: an accent symbol, a title and one hint line.
struct WidgetEmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    let hint: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color("RpplAccent"))
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("RpplText"))
                .minimumScaleFactor(0.7)
            Text(hint)
                .font(.caption)
                .foregroundStyle(Color("RpplMuted"))
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
