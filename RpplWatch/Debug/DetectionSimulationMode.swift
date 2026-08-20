import Foundation

/// Debug-page ride simulation cycle on Watch.
enum DetectionSimulationMode: String, Sendable {
    /// Live `DetectionEngine` output.
    case detected
    /// Force confident `inactive`.
    case inactive
    /// Force confident `riding`.
    case ride

    var buttonTitle: String {
        switch self {
        case .detected: return String(localized: "Sim: Detected")
        case .inactive: return String(localized: "Sim: Inactive")
        case .ride: return String(localized: "Sim: Ride")
        }
    }
}
