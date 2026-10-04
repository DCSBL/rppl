import Foundation

/// Schema version for on-disk session packages (`manifest.schemaVersion`).
///
/// Bump it on a breaking change and add the matching step to `SessionMigrations`; a package with
/// a lower version is migrated when it is opened.
public enum SessionSchema {
    public static let currentVersion = 1
}
