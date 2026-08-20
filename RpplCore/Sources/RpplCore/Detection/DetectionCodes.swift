import Foundation

/// Opaque detection codes (not a closed enum — unknown strings must round-trip in JSONL).
public enum DetectionCodes {
    public static let riding = "riding"
    public static let inactive = "inactive"
    public static let unsure = "unsure"

    /// Legacy on-disk / transfer alias before schema v4.
    public static let legacyPaused = "paused"

    public static func isConfident(_ code: String) -> Bool {
        let normalized = normalize(code)
        return normalized == riding || normalized == inactive
    }

    /// Map legacy `paused` to `inactive` before compare / attribution.
    public static func normalize(_ code: String) -> String {
        code == legacyPaused ? inactive : code
    }
}
