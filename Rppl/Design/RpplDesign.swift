import SwiftUI

/// Shared layout + color tokens for the tile-based UI. See Docs/DesignLanguage.md.
enum RpplDesign {
    static let tileCornerRadius: CGFloat = 24
    static let tilePadding: CGFloat = 16
    /// Gap between tiles in a grid or stack.
    static let tileSpacing: CGFloat = 12
    /// Gap between header, value and graphic inside one tile.
    static let tileContentSpacing: CGFloat = 10
    /// Card tint over the material; Reduce Transparency draws the card solid instead.
    static let tileTintOpacity: Double = 0.6

    static var headerColor: Color { Color.rpplMuted.opacity(0.85) }
    static var secondaryText: Color { Color.rpplMuted }
}

/// One SF Symbol + tint per metric, shared by tiles, chips, charts (and mirrored on Watch).
enum MetricKind: CaseIterable, Equatable {
    case distance
    case speed
    case sets
    case laps
    case duration
    case riding
    case inactive
    case water
    case air
    case humidity
    case wind
    case precipitation
    case energy
    case heartRate
    case park

    var systemImage: String {
        switch self {
        case .distance: "water.waves"
        case .speed: "gauge.with.dots.needle.67percent"
        case .sets: "flag.checkered"
        case .laps: "arrow.triangle.2.circlepath"
        case .duration: "clock"
        case .riding: "figure.surfing"
        case .inactive: "pause.circle"
        case .water: "thermometer.medium"
        case .air: "cloud.sun"
        case .humidity: "humidity"
        case .wind: "wind"
        case .precipitation: "cloud.rain"
        case .energy: "flame"
        case .heartRate: "heart.fill"
        case .park: "mappin.and.ellipse"
        }
    }

    var tint: Color {
        switch self {
        case .distance, .park: Color.rpplAccent
        case .speed: Color.rpplMetricSpeed
        case .sets: Color.rpplMetricSets
        case .laps: Color.rpplMetricLaps
        case .duration: Color.rpplMetricTime
        case .riding: Color.rpplMetricRiding
        case .inactive: Color.rpplMuted
        case .water: Color.rpplMetricWater
        case .air, .humidity, .wind, .precipitation: Color.rpplMetricAir
        case .energy, .heartRate: Color.rpplMetricEnergy
        }
    }
}

/// Renders a metric's icon: the wakeboard glyph for `.riding`, an SF Symbol otherwise.
/// `systemImage` lets call sites that already resolved `MetricKind.systemImage` skip re-deriving it.
struct MetricIcon: View {
    var metric: MetricKind?
    var systemImage: String

    init(metric: MetricKind) {
        self.metric = metric
        self.systemImage = metric.systemImage
    }

    init(metric: MetricKind?, systemImage: String) {
        self.metric = metric
        self.systemImage = systemImage
    }

    var body: some View {
        if metric == .riding {
            WakeboardIcon()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: systemImage)
        }
    }
}

/// The wakeboarder glyph as a template vector asset. The `activity-*` set is adapted from Material Design Icons
/// `ski-water` (see LEGAL.md).
struct WakeboardIcon: View {
    var body: some View {
        Image("activity-wakeboard")
            .resizable()
            .scaledToFit()
            .accessibilityLabel(Text("Wakeboarding"))
    }
}

/// See `rpplPopoverContent(width:maxWidth:)`.
private struct PopoverContent: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let width: CGFloat?
    let maxWidth: CGFloat?

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.rpplBackground)
        } else {
            content
                .frame(width: width)
                .frame(maxWidth: maxWidth)
                .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    /// The content of a `popover`: a popover of the given width on a phone, as the system would do on iPad. At
    /// accessibility text sizes the same content is a sheet that scrolls instead: a paragraph at those sizes
    /// is taller than the screen, and a popover never scrolls.
    func rpplPopoverContent(width: CGFloat? = nil, maxWidth: CGFloat? = nil) -> some View {
        modifier(PopoverContent(width: width, maxWidth: maxWidth))
    }
}
