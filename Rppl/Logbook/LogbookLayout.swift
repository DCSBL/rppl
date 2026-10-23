import SwiftUI

enum LogbookLayout {
    static let horizontalInset: CGFloat = 16

    /// Side margin in a wide window, where the cards should use more of the width.
    static let wideInset: CGFloat = 8

    /// Widest a detail column of cards gets before it is centered; wider lines of tiles and text read worse.
    static let readableMaxWidth: CGFloat = 720

    /// Outer session / totals / detail cards (Liquid Glass nest base).
    static let cardCornerRadius: CGFloat = 24

    /// Fallback when a nested shape sits far from the card corners (e.g. grid tiles).
    static let nestedMinimumCornerRadius: CGFloat = 8

    static func rowInsets(top: CGFloat = 8, bottom: CGFloat = 8) -> EdgeInsets {
        EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }
}

/// Side margins of a scrolling detail. The bar buttons of iPhone Duo stand in a trailing safe area the leading
/// side does not have; the bar already keeps the cards clear of that edge, so that side gets the small inset.
private struct DetailMargins: ViewModifier {
    let inset: CGFloat
    @State private var hasTrailingBar = false

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, inset, for: .scrollContent)
            .contentMargins(.trailing, hasTrailingBar ? min(inset, LogbookLayout.wideInset) : inset, for: .scrollContent)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.safeAreaInsets.trailing > proxy.safeAreaInsets.leading + 20
            } action: { hasTrailingBar = $0 }
    }
}

extension View {
    /// Leading and trailing margins of a detail `ScrollView`, see `DetailMargins`.
    func detailMargins(_ inset: CGFloat) -> some View {
        modifier(DetailMargins(inset: inset))
    }

    /// Caps the content at `LogbookLayout.readableMaxWidth` and centers it in a wide window.
    func readableWidth() -> some View {
        frame(maxWidth: LogbookLayout.readableMaxWidth).frame(maxWidth: .infinity)
    }

    /// Card padding + fill + `containerShape` so nested concentric radii resolve.
    func logbookCardChrome() -> some View {
        rpplTileChrome()
    }

    /// Nested fill (icon well, stat tiles, placeholders) concentric to the card.
    func logbookNestedBackground(_ color: some ShapeStyle) -> some View {
        background(
            color,
            in: .rect(
                corners: .concentric(minimum: .fixed(LogbookLayout.nestedMinimumCornerRadius)),
                isUniform: true
            )
        )
    }

    /// Nested clip (ride / session maps inside a card) concentric to the card.
    func logbookNestedClip() -> some View {
        clipShape(
            .rect(
                corners: .concentric(minimum: .fixed(LogbookLayout.nestedMinimumCornerRadius)),
                isUniform: true
            )
        )
    }
}
