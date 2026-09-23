import Foundation

/// Opaque Watch battery-state strings for `BatterySample.state`.
/// Persist these; never persist localized titles.
public enum BatteryStateCodes {
    public static let unplugged = "unplugged"
    public static let charging = "charging"
    public static let full = "full"
    public static let unknown = "unknown"
}
