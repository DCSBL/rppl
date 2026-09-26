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
enum MetricKind: CaseIterable {
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
        case .air, .humidity: Color.rpplMetricAir
        case .energy, .heartRate: Color.rpplMetricEnergy
        }
    }
}
