import Foundation

/// Display text for a peak g-force, e.g. "6.2 g".
public enum ImpactFormat {
    public static func text(_ peakG: Double) -> String {
        String(format: "%.1f g", locale: Locale.current, peakG)
    }
}
