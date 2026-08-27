import Foundation

/// Bump when `SessionStatsBuilder` / lap / speed / map-frame logic changes UI numbers.
/// Stale `derived/view.json` regenerates from raw on ensure.
/// v2: brief slang mis-rename wrote `setCount` (circuit crossings).
/// v3: canonical key is `lapCount` again; decode accepts `setCount` then rewrite.
/// v4: distilled `mapTracks` for session averaged / heatmap maps (phone + Watch).
/// v5: medoid most-common-path selection replaces mean-coordinate averaging.
public enum SessionAnalyzer {
    public static let version = 5
}
