import Foundation

/// Opaque detection codes (not a closed enum — unknown strings must round-trip in JSONL).
public enum DetectionCodes {
    public static let riding = "riding"
    public static let inactive = "inactive"
    public static let unsure = "unsure"

    public static func isConfident(_ code: String) -> Bool {
        code == riding || code == inactive
    }
}
