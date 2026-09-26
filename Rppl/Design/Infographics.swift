import SwiftUI
import RpplCore

/// Big number with a smaller, muted unit (`42,2` `km/h`), one line, shrinks before truncating.
struct MetricValue: View {
    enum Size {
        case hero
        case large
        case medium
        case small

        var valueFont: Font {
            switch self {
            case .hero: .largeTitle.bold().monospacedDigit()
            case .large: .title.bold().monospacedDigit()
            case .medium: .title2.bold().monospacedDigit()
            case .small: .title3.bold().monospacedDigit()
            }
        }

        var unitFont: Font {
            switch self {
            case .hero: .title3.weight(.semibold)
            case .large: .headline
            case .medium: .subheadline.weight(.semibold)
            case .small: .footnote.weight(.semibold)
            }
        }
    }

    private let parts: MetricDisplay.Parts
    private let size: Size

    /// `formatted` comes from the Core formatters; the unit is split off when it is a plain suffix.
    init(_ formatted: String, size: Size = .large) {
        self.parts = MetricDisplay.split(formatted)
        self.size = size
    }

    var body: some View {
        Text(attributed)
            .foregroundStyle(Color.rpplText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var attributed: AttributedString {
        var value = AttributedString(parts.value)
        value.font = size.valueFont
        guard let unit = parts.unit else { return value }
        var suffix = AttributedString("\u{00A0}" + unit)
        suffix.font = size.unitFont
        suffix.foregroundColor = RpplDesign.secondaryText
        return value + suffix
    }
}

/// Ring for a share of a whole (riding vs inactive). Use with a native `Gauge`:
/// `Gauge(value: fraction) { Text("Riding") } currentValueLabel: { Text("27%") }.gaugeStyle(.rpplRing(tint:))`
struct RingGaugeStyle: GaugeStyle {
    var tint: Color
    var lineWidth: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: configuration.value)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            configuration.currentValueLabel
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(Color.rpplText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(lineWidth)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Horizontal bar for a value against a max (avg vs max speed, sets vs laps).
struct BarGaugeStyle: GaugeStyle {
    var tint: Color
    var height: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(tint.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if configuration.value > 0 {
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: max(height, proxy.size.width * configuration.value))
                    }
                }
            }
            .frame(height: height)
    }
}

extension GaugeStyle where Self == RingGaugeStyle {
    static func rpplRing(tint: Color, lineWidth: CGFloat = 10) -> RingGaugeStyle {
        RingGaugeStyle(tint: tint, lineWidth: lineWidth)
    }
}

extension GaugeStyle where Self == BarGaugeStyle {
    static func rpplBar(tint: Color, height: CGFloat = 8) -> BarGaugeStyle {
        BarGaugeStyle(tint: tint, height: height)
    }
}

/// Horizontal timeline: one tinted segment per span (fractions of the whole, e.g. sets in a session).
/// Decorative: pair it with the count and times as text.
struct TimelineBar: View {
    let spans: [ClosedRange<Double>]
    var tint: Color
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(0.15))
                ForEach(spans.indices, id: \.self) { index in
                    let span = spans[index]
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(2, proxy.size.width * (span.upperBound - span.lowerBound)))
                        .offset(x: proxy.size.width * span.lowerBound)
                }
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: height / 3, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Compact metric: tinted symbol + value, optional caption underneath.
struct StatChip: View {
    let metric: MetricKind
    let value: String
    var caption: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: metric.systemImage)
                    .imageScale(.small)
                    .foregroundStyle(metric.tint)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rpplText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(RpplDesign.secondaryText)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
