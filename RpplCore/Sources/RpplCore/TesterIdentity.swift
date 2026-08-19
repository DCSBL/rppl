import Foundation

public enum TesterIdentity {
    public static let defaultsKey = "wakeTracker.anonymousTesterId"

    public static func resolve(store: UserDefaults = .standard) -> String {
        if let existing = store.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        store.set(id, forKey: defaultsKey)
        return id
    }
}
