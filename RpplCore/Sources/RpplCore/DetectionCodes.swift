import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    /// v3: detections.jsonl (ride/pause/unsure); labels/assumptions removed from writers.
    public static let currentVersion = 3
}

/// Opaque detection codes (not a closed enum — unknown strings must round-trip in JSONL).
public enum DetectionCodes {
    public static let riding = "riding"
    public static let paused = "paused"
    public static let unsure = "unsure"

    public static func isConfident(_ code: String) -> Bool {
        code == riding || code == paused
    }
}
