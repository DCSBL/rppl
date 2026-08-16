import Foundation

/// Debug-page ride simulation cycle on Watch.
enum DetectionSimulationMode: String, Sendable {
    /// Live `DetectionEngine` output.
    case detected
    /// Force confident `paused`.
    case pause
    /// Force confident `riding`.
    case ride

    var buttonTitle: String {
        switch self {
        case .detected: return String(localized: "Sim: Detected")
        case .pause: return String(localized: "Sim: Pause")
        case .ride: return String(localized: "Sim: Ride")
        }
    }
}
