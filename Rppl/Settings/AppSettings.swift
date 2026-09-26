import Foundation

/// Stable `UserDefaults` keys for `@AppStorage` and direct access.
enum AppSettingsKey {
    /// Park editor (+ / Edit / share). Flip the default to hide the editor from users.
    static let parkEditorEnabled = "rppl.parkEditorEnabled"
    static let mapUsesSatellite = "rppl.mapUsesSatellite"
    /// At least one Watch session package imported on this iPhone.
    static let didImportSessionFromWatch = "rppl.didImportSessionFromWatch"
    /// Post-first-sync Location/Health/Motion asks already attempted (once).
    static let didRequestPostSyncPermissions = "rppl.didRequestPostSyncPermissions"
    /// First-time Export disclosure (raw / non-anonymized share) accepted.
    static let didUnderstandExport = "rppl.didUnderstandExport"
    /// Local iCloud Drive logbook sync preference (default on).
    static let iCloudDriveSyncEnabled = "rppl.iCloudDriveSyncEnabled"
    /// Session ids accepted into this phone’s logbook (Ask-before-import; local only).
    static let iCloudAcceptedSessionIDs = "rppl.iCloudAcceptedSessionIds"
    /// Session ids removed from this phone’s logbook but left in iCloud Drive.
    static let iCloudHiddenSessionIDs = "rppl.iCloudHiddenSessionIds"
    /// Session ids the user declined to import or deleted (skip import picker across launches).
    static let iCloudDismissedImportSessionIDs = "rppl.iCloudDismissedImportSessionIds"
    /// Park arrival geofence notifications (opt-in; default off).
    static let parkArrivalNotificationsEnabled = "rppl.parkArrivalNotificationsEnabled"
    /// `[String: Double]` park id → last-notified `timeIntervalSince1970`, for the 12h cooldown.
    static let parkArrivalLastNotified = "rppl.parkArrivalLastNotified"
    /// First-time "here's why you got this / how it works" explainer, shown once on first tap.
    static let didShowParkArrivalExplainer = "rppl.didShowParkArrivalExplainer"
}
