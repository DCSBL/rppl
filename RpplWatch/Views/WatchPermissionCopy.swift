import Foundation
import RpplCore

/// Watch copy for each recording permission: shown by the "Can't start yet" sheet.
extension WatchPermissionKind {
    var title: String {
        switch self {
        case .location: return String(localized: "Location")
        case .health: return String(localized: "Health")
        case .motion: return String(localized: "Motion")
        }
    }

    var whyNeeded: String {
        switch self {
        case .location:
            return String(localized: "Required to record GPS during your park session so Rppl can track sets and distance.")
        case .health:
            return String(localized: "Required to save the workout to Fitness and record heart rate while you set.")
        case .motion:
            return String(localized: "Helps tell when you are riding versus resting at the dock.")
        }
    }

    var howToFix: String {
        switch self {
        case .location:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Location Services > Rppl, allow While Using the App and turn on Precise Location."
            )
        case .health:
            return String(
                localized: "On iPhone, open the Health app > Sharing > Apps > Rppl and turn on workout access. Or: Settings > Health > Data Access & Devices > Rppl."
            )
        case .motion:
            return String(
                localized: "On iPhone, open Settings > Privacy & Security > Motion & Fitness and enable Rppl."
            )
        }
    }
}
