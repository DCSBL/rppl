import Foundation

/// Version of the analysis behind `derived/view.json`. Bump it when `SessionStatsBuilder`, lap,
/// speed, map-track or map-frame logic changes the numbers the UI shows: a stale sidecar is
/// rebuilt from the raw streams the next time it is ensured.
public enum SessionAnalyzer {
    public static let version = 2
}
