import SwiftUI
import RpplCore

/// Colors for session track layers.
///
/// Every stroke is drawn twice: a dark casing first, then the bright core. That is what
/// keeps overlapping laps readable on both the standard basemap and satellite, where a
/// single flat line disappears into the water.
enum SessionTrackPalette {
    /// Outline under every colored stroke.
    static let casing = Color.black.opacity(0.45)
    /// Sets that are not the focus of the current appearance.
    static let ghost = Color(white: 0.55).opacity(0.7)
    /// Replay head and comet trail.
    static let head = Color.white

    static let coreLineWidth: CGFloat = 3.5
    static let casingLineWidth: CGFloat = 6.5
    static let ghostLineWidth: CGFloat = 2
    static let flyoverLineWidth: CGFloat = 5

    /// Cool → warm ramp across the park day: cyan for the first set, magenta for the last.
    static func setColor(position: Int, of count: Int) -> Color {
        let fraction = count <= 1 ? 0 : Double(position) / Double(count - 1)
        let hue = 0.46 + min(max(fraction, 0), 1) * 0.46
        return Color(hue: hue, saturation: 0.85, brightness: 0.98)
    }

    /// Blue → cyan → green → yellow → red across a speed scale position (0…1).
    static func speedColor(fraction: Double) -> Color {
        let clamped = min(max(fraction, 0), 1)
        return Color(hue: 0.62 * (1 - clamped), saturation: 0.95, brightness: 0.98)
    }

    static func speedGradient(bandCount: Int) -> LinearGradient {
        let steps = max(bandCount, 2)
        let stops = (0..<steps).map { speedColor(fraction: Double($0) / Double(steps - 1)) }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    static func setGradient(count: Int) -> LinearGradient {
        let steps = max(min(count, 12), 2)
        let stops = (0..<steps).map { setColor(position: $0, of: steps) }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    static func strokeStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}
