import Foundation

/// User preferences in `UserDefaults`. Add keys + properties here as settings grow.
final class AppSettings {
    static let shared = AppSettings()

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// Stable keys for `@AppStorage` and direct `UserDefaults` access.
    enum Key {
        static let mapUsesSatellite = "rppl.mapUsesSatellite"
    }

    /// Session/ride maps use hybrid (satellite) when `true`, standard when `false`.
    var mapUsesSatellite: Bool {
        get { store.bool(forKey: Key.mapUsesSatellite) }
        set { store.set(newValue, forKey: Key.mapUsesSatellite) }
    }
}
