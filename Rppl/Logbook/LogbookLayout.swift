import SwiftUI

enum LogbookLayout {
    static let horizontalInset: CGFloat = 16

    /// Outer session / totals / detail cards (Liquid Glass nest base).
    static let cardCornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 12

    /// Fallback when a nested shape sits far from the card corners (e.g. grid tiles).
    static let nestedMinimumCornerRadius: CGFloat = 8

    static func rowInsets(top: CGFloat = 8, bottom: CGFloat = 8) -> EdgeInsets {
        EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }
}

extension View {
    /// Card padding + fill + `containerShape` so nested concentric radii resolve.
    func logbookCardChrome() -> some View {
        padding(LogbookLayout.cardPadding)
            .background(Color.rpplCard, in: .rect(cornerRadius: LogbookLayout.cardCornerRadius))
            .containerShape(.rect(cornerRadius: LogbookLayout.cardCornerRadius))
    }

    /// Nested fill (icon well, stat tiles, placeholders) concentric to the card.
    func logbookNestedBackground(_ color: some ShapeStyle) -> some View {
        background(
            color,
            in: .rect(
                corners: .concentric(minimum: LogbookLayout.nestedMinimumCornerRadius),
                isUniform: true
            )
        )
    }

    /// Nested clip (ride / session maps inside a card) concentric to the card.
    func logbookNestedClip() -> some View {
        clipShape(
            .rect(
                corners: .concentric(minimum: LogbookLayout.nestedMinimumCornerRadius),
                isUniform: true
            )
        )
    }
}
