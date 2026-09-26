import SwiftUI

/// Watch mirror of the phone's `MetricKind`: same SF Symbol + tint per metric (Docs/DesignLanguage.md).
enum WatchMetric {
    case distance
    case speed
    case sets
    case laps
    case duration
    case inactive
    case water
    case energy

    var systemImage: String {
        switch self {
        case .distance: "water.waves"
        case .speed: "gauge.with.dots.needle.67percent"
        case .sets: "flag.checkered"
        case .laps: "arrow.triangle.2.circlepath"
        case .duration: "clock"
        case .inactive: "pause.circle"
        case .water: "thermometer.medium"
        case .energy: "flame"
        }
    }

    var tint: Color {
        switch self {
        case .distance: Color.rpplIdleAccent
        case .speed: Color.rpplMetricSpeed
        case .sets: Color.rpplMetricSets
        case .laps: Color.rpplMetricLaps
        case .duration: Color.rpplMetricTime
        case .inactive: Color.secondary
        case .water: Color.rpplMetricWater
        case .energy: Color.rpplMetricEnergy
        }
    }
}

/// Caps caption with the metric symbol in its tint, used under or above Watch values.
struct WatchMetricCaption: View {
    let label: LocalizedStringKey
    var metric: WatchMetric?

    var body: some View {
        HStack(spacing: 3) {
            if let metric {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(metric.tint)
                    .accessibilityHidden(true)
            }
            Text(label)
        }
    }
}
