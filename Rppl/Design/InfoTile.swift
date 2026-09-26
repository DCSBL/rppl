import SwiftUI

/// Weather-style tile: small tinted symbol + caps header, then free content.
struct InfoTile<Content: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let tint: Color
    private let content: Content
    private var metric: MetricKind?

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color = RpplDesign.headerColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    init(_ title: LocalizedStringKey, metric: MetricKind, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: metric.systemImage, tint: metric.tint, content: content)
        self.metric = metric
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RpplDesign.tileContentSpacing) {
            TileHeader(title: title, systemImage: systemImage, tint: tint, metric: metric)
            content
        }
        // maxHeight lets tiles in one grid row share the tallest height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rpplTileChrome()
    }
}

struct TileHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = RpplDesign.headerColor
    var metric: MetricKind?

    var body: some View {
        HStack(spacing: 6) {
            MetricIcon(metric: metric, systemImage: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RpplDesign.headerColor)
        .accessibilityElement(children: .ignore)
        // Read the sentence-case key; all-caps text can be spelled out letter by letter.
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Two-column tile grid (one column at accessibility sizes); tiles in a row share height.
struct InfoTileGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        Group(subviews: content) { subviews in
            Grid(
                alignment: .topLeading,
                horizontalSpacing: RpplDesign.tileSpacing,
                verticalSpacing: RpplDesign.tileSpacing
            ) {
                ForEach(Array(stride(from: 0, to: subviews.count, by: columns)), id: \.self) { start in
                    GridRow {
                        ForEach(subviews[start..<min(start + columns, subviews.count)]) { subview in
                            subview
                        }
                    }
                }
            }
        }
    }
}

private struct TileChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RpplDesign.tileCornerRadius, style: .continuous)
        content
            .padding(RpplDesign.tilePadding)
            .background {
                if reduceTransparency {
                    shape.fill(Color.rpplCard)
                } else {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color.rpplCard.opacity(RpplDesign.tileTintOpacity))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(Color.rpplText.opacity(0.08), lineWidth: 1)
            }
            .containerShape(shape)
    }
}

extension View {
    /// Tile padding, translucent fill, hairline and a container shape for concentric insets.
    func rpplTileChrome() -> some View {
        modifier(TileChrome())
    }
}
