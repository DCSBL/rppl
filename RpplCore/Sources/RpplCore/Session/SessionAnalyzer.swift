import Foundation

/// Bump when `SessionStatsBuilder` / lap / speed / map-frame logic changes UI numbers.
/// Stale `derived/view.json` regenerates from raw on ensure.
public enum SessionAnalyzer {
    public static let version = 1
}
