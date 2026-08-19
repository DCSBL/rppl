import Foundation

/// Opaque session activity codes (not a closed taxonomy enum).
/// Persist these strings; never persist localized titles.
public enum ActivityCodes {
    public static let wakeboard = "wakeboard"
    public static let waterski = "waterski"
    public static let monoski = "monoski"
    public static let wakeskate = "wakeskate"
    public static let kneeboard = "kneeboard"
    public static let other = "other"

    public static let pickerCodes: [String] = [
        wakeboard,
        waterski,
        monoski,
        wakeskate,
        kneeboard,
        other,
    ]

    /// Last-started picker card. Unknown / missing → `wakeboard`.
    public static func pickerLandingCode(store: UserDefaults = .standard) -> String {
        if let stored = store.string(forKey: AppConstants.lastActivityCodeDefaultsKey),
           pickerCodes.contains(stored) {
            return stored
        }
        return wakeboard
    }

    /// Action Button / start default. Empty → `wakeboard`; unknown codes pass through.
    public static func resolvedStartCode(store: UserDefaults = .standard) -> String {
        if let stored = store.string(forKey: AppConstants.lastActivityCodeDefaultsKey), !stored.isEmpty {
            return stored
        }
        return wakeboard
    }

    public static func rememberLastUsed(_ code: String, store: UserDefaults = .standard) {
        guard !code.isEmpty else { return }
        store.set(code, forKey: AppConstants.lastActivityCodeDefaultsKey)
    }

    /// Display-only. Missing code → localized "Cable park". Unknown code → raw string.
    public static func localizedTitle(for code: String?) -> String {
        guard let code, !code.isEmpty else {
            return String(localized: "Cable park", bundle: .module)
        }
        switch code {
        case wakeboard:
            return String(localized: "Wakeboard", bundle: .module)
        case waterski:
            return String(localized: "Waterski", bundle: .module)
        case monoski:
            return String(localized: "Monoski", bundle: .module)
        case wakeskate:
            return String(localized: "Wakeskate", bundle: .module)
        case kneeboard:
            return String(localized: "Kneeboard", bundle: .module)
        case other:
            return String(localized: "Other", bundle: .module)
        default:
            return code
        }
    }
}
