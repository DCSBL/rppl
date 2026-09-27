import Foundation

/// Schema version for on-disk session packages. Bump when breaking changes land.
public enum SessionSchema {
    /// v3: detections.jsonl (ride/inactive/unsure); labels/assumptions removed from writers.
    /// v4: detection code `paused` → `inactive`.
    /// v5: optional `derived/view.json` (stats + map frame); raw streams unchanged.
    /// v6: optional manifest `wristLocation` + `crownOrientation` (Watch wear settings at start).
    /// v7: optional manifest `imported` (phone file-import timestamp; nil for Watch/WC sessions).
    /// v8: optional manifest `weather` (WeatherKit temperature + humidity at start).
    /// v9: optional manifest `weather` wind speed/direction + precipitation.
    public static let currentVersion = 9
}
