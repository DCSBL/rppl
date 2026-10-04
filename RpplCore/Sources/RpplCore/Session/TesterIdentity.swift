import Foundation

/// Random install-scoped ID stamped into each session manifest / export.
///
/// Generated on first resolve, persisted in the App Group (or standard defaults).
/// Cleared on uninstall / reinstall — not an account or hardware identifier.
public enum TesterIdentity {
    public static let defaultsKey = "wakeTracker.anonymousTesterId"

    /// Resolve the install ID, creating one if missing.
    /// - Parameter store: Override for tests. Production uses the App Group suite when available.
    public static func resolve(store: UserDefaults? = nil) -> String {
        let defaults = store ?? preferredStore()
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }

        let id = UUID().uuidString
        defaults.set(id, forKey: defaultsKey)
        return id
    }

    public static func preferredStore() -> UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }
}
