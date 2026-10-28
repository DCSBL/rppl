import SwiftUI

/// An `HStack` that becomes a `VStack` at accessibility text sizes, where two texts side by side no longer fit.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Alignment of the row (the `HStack`).
    var rowAlignment: VerticalAlignment = .center
    /// Alignment of the column (the `VStack`).
    var columnAlignment: HorizontalAlignment = .leading
    var spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: columnAlignment, spacing: spacing, content: content)
        } else {
            HStack(alignment: rowAlignment, spacing: spacing, content: content)
        }
    }
}
