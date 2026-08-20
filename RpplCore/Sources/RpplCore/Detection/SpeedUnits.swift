import Foundation

/// Speed conversions for detection thresholds (authored in km/h) vs Core Location (m/s).
/// Later: knots / mph for display only — keep GPS compare on m/s.
public enum SpeedUnits {
    public static func metersPerSecond(fromKilometersPerHour kmh: Double) -> Double {
        kmh / 3.6
    }

    public static func kilometersPerHour(fromMetersPerSecond mps: Double) -> Double {
        mps * 3.6
    }

    /// Human-readable speed for detection `reason` strings.
    public static func reasonKilometersPerHour(fromMetersPerSecond mps: Double?) -> String {
        guard let mps else { return "nil" }
        return String(format: "%.1fkm/h", kilometersPerHour(fromMetersPerSecond: mps))
    }
}
