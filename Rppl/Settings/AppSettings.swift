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
    /// User dismissed the inline "Show water temperature?" prompt on a park screen — stop offering it.
    static let didDeclineParkWaterTemperaturePrompt = "rppl.didDeclineParkWaterTemperaturePrompt"
}
