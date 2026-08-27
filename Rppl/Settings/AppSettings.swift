import Foundation

/// Stable `UserDefaults` keys for `@AppStorage` and direct access.
enum AppSettingsKey {
    static let mapUsesSatellite = "rppl.mapUsesSatellite"
    /// At least one Watch session package imported on this iPhone.
    static let didImportSessionFromWatch = "rppl.didImportSessionFromWatch"
    /// Post-first-sync Location/Health/Motion asks already attempted (once).
    static let didRequestPostSyncPermissions = "rppl.didRequestPostSyncPermissions"
    /// First-time Export disclosure (raw / non-anonymized share) accepted.
    static let didUnderstandExport = "rppl.didUnderstandExport"
}
