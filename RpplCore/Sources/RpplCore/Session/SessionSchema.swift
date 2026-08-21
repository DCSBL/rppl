import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    /// v3: detections.jsonl (ride/inactive/unsure); labels/assumptions removed from writers.
    /// v4: detection code `paused` → `inactive`.
    /// v5: optional `derived/view.json` (stats + map frame); raw streams unchanged.
    public static let currentVersion = 5
}
