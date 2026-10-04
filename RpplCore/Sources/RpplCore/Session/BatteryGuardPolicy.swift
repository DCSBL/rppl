import Foundation

/// What the Watch does as its battery runs down during a session.
///
/// The Health workout and the phone transfer only happen at Stop. A park day can outlast an older
/// Watch's battery: when it dies mid-session the Fitness workout for the whole day is never
/// finished. So the rider is warned early and the session is stopped (Health save and transfer
/// queue included) while there is still power.
///
/// The thresholds are product defaults, kept in one place.
public enum BatteryGuardPolicy {
    public enum Action: Equatable, Sendable {
        case none
        /// Tell the rider once (haptic) and flush; `code` is an opaque warning code.
        case warn(code: String)
        /// Stop the session now so the Health save and the transfer happen while there is power.
        case autoStop
    }

    /// Opaque warning codes.
    public enum Warning {
        public static let low = "battery_15"
        public static let veryLow = "battery_10"
    }

    /// Warn thresholds as battery fractions, most severe first.
    public static let warnLevels: [(code: String, level: Double)] = [
        (Warning.veryLow, 0.10),
        (Warning.low, 0.15)
    ]
    /// At or below this fraction, unplugged, the session is stopped.
    public static let autoStopLevel = 0.05
    /// `detectorId` of the detection marker written just before an automatic stop.
    public static let autoStopDetectorId = "battery_critical"

    /// - Parameters:
    ///   - level: battery fraction 0…1; negative means unknown and never acts.
    ///   - state: `BatteryStateCodes`. Only `charging` and `full` are safe; `unplugged` and
    ///     `unknown` count as running on battery, so an unknown state cannot hide a dying battery.
    ///   - alreadyWarned: warning codes already shown this session.
    public static func decide(level: Double, state: String, alreadyWarned: Set<String>) -> Action {
        guard level >= 0 else { return .none }
        guard state != BatteryStateCodes.charging, state != BatteryStateCodes.full else { return .none }
        if level <= autoStopLevel { return .autoStop }
        for warning in warnLevels where level <= warning.level && !alreadyWarned.contains(warning.code) {
            return .warn(code: warning.code)
        }
        return .none
    }

    /// Codes that count as shown once `code` has been shown: a jump from 20 % to 8 % warns once
    /// ("very low"), it does not warn "low" a moment later.
    public static func coveredCodes(by code: String) -> Set<String> {
        guard let level = warnLevels.first(where: { $0.code == code })?.level else { return [code] }
        return Set(warnLevels.filter { $0.level >= level }.map(\.code))
    }
}
