import Foundation

/// Beaufort wind-force scale (0–12) from a km/h speed, for showing next to the raw speed.
public enum BeaufortScale {
    public static func number(forKmh kmh: Double) -> Int {
        switch kmh {
        case ..<1: 0
        case ..<6: 1
        case ..<12: 2
        case ..<20: 3
        case ..<29: 4
        case ..<39: 5
        case ..<50: 6
        case ..<62: 7
        case ..<75: 8
        case ..<89: 9
        case ..<103: 10
        case ..<118: 11
        default: 12
        }
    }

    /// Short "Bft 3" label; the abbreviation itself doesn't change per locale.
    public static func label(forKmh kmh: Double) -> String {
        String(localized: "Bft \(number(forKmh: kmh))", bundle: .module)
    }
}
