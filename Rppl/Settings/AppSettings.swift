import Foundation

/// Stable `UserDefaults` keys for `@AppStorage` and direct access.
enum AppSettingsKey {
    /// Park editor (+ / Edit / share). Flip the default to hide the editor from users.
    static let parkEditorEnabled = "rppl.parkEditorEnabled"
    static let mapUsesSatellite = "rppl.mapUsesSatellite"
    /// First-time Export disclosure (raw / non-anonymized share) accepted.
    static let didUnderstandExport = "rppl.didUnderstandExport"
    /// `[String]` custom set-flag labels the rider added (local only).
    static let customSetFlags = "rppl.customSetFlags"
    /// Local iCloud Drive logbook sync preference (default on).
    static let iCloudDriveSyncEnabled = "rppl.iCloudDriveSyncEnabled"
    /// Session ids accepted into this phone’s logbook (Ask-before-import; local only).
    static let iCloudAcceptedSessionIDs = "rppl.iCloudAcceptedSessionIds"
    /// Session ids removed from this phone’s logbook but left in iCloud Drive.
    static let iCloudHiddenSessionIDs = "rppl.iCloudHiddenSessionIds"
    /// Session ids the user declined to import or deleted (skip import picker across launches).
    static let iCloudDismissedImportSessionIDs = "rppl.iCloudDismissedImportSessionIds"
    /// Estimated ambient water temperature per park, from an open government API (opt-in; default off).
    static let parkWaterTemperatureEnabled = "rppl.parkWaterTemperatureEnabled"
    /// Debug: show speed / altitude / g-force charts under each set (default off).
    static let debugSetCharts = "rppl.debugSetCharts"
    /// Debug: show and edit set flags/labels in the logbook (default off; stored flags are kept either way).
    static let debugSetFlags = "rppl.debugSetFlags"
    /// User dismissed the inline "Show water temperature?" prompt on a park screen — stop offering it.
    static let didDeclineParkWaterTemperaturePrompt = "rppl.didDeclineParkWaterTemperaturePrompt"
    /// Download park updates from GitHub (opt-in; default off).
    static let parkDataUpdatesEnabled = "rppl.parkDataUpdatesEnabled"
    /// The first-time "Update park data?" question was answered (either way); don't ask again.
    static let didAskParkDataConsent = "rppl.didAskParkDataConsent"
    /// JSON `ParkDataUpdateState`: last attempts and successes (local only).
    static let parkDataUpdateState = "rppl.parkDataUpdateState"
    /// JSON `ReviewPromptState`: good-session count and pending App Store review prompt (local only).
    static let reviewPromptState = "rppl.reviewPromptState"
    /// Logbook "Max speed" total: `SpeedTotal` raw value (tap cycles max / average).
    static let speedTotal = "rppl.speedTotal"
    /// Logbook "Sessions" total: `CountTotal` raw value (tap cycles sessions / sets / laps).
    static let countTotal = "rppl.countTotal"
    /// Logbook "Distance" total: `DistanceTotal` raw value (tap cycles distance / total time / riding time).
    static let distanceTotal = "rppl.distanceTotal"
}
