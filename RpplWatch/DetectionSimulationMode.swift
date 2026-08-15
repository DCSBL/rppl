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
        case .detected: return "Sim: Detected"
        case .pause: return "Sim: Pause"
        case .ride: return "Sim: Ride"
        }
    }
}
