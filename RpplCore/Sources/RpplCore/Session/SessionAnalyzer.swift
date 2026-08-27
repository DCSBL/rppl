import Foundation

/// Bump when `SessionStatsBuilder` / set / speed / map-frame logic changes UI numbers.
/// Stale `derived/view.json` regenerates from raw on ensure.
/// v2: cable-park crossing field renamed `lapCount` → `setCount` (decode still accepts `lapCount`).
public enum SessionAnalyzer {
    public static let version = 2
}
