import Foundation

/// GPS / speed quality gate before hold clocks and transition rules see a tick.
/// Swap or tighten independently of FSM transitions.
public struct AssumerSignalFilter: Equatable, Sendable {
    public var thresholds: AssumptionThresholds

    public init(thresholds: AssumptionThresholds = .default) {
        self.thresholds = thresholds
    }

    public static let `default` = AssumerSignalFilter()

    /// Result of filtering one tick. Water / activity always pass through on `raw`.
    public struct Outcome: Equatable, Sendable {
        public var raw: AssumerTick
        /// Speed trusted for speed-based holds and rules.
        public var usableSpeedMps: Double?
        public var rejectionReason: String?

        public var speedUsable: Bool { usableSpeedMps != nil }
    }

    /// Filter speed; keep water/activity on `raw` for non-speed rules (e.g. Ultra swim).
    public func evaluate(
        _ tick: AssumerTick,
        previousUsableSpeedMps: Double?
    ) -> Outcome {
        guard let speed = tick.speedMps else {
            return Outcome(raw: tick, usableSpeedMps: nil, rejectionReason: "nil_speed")
        }

        if let accuracy = tick.horizontalAccuracy {
            if accuracy < 0 {
                return Outcome(raw: tick, usableSpeedMps: nil, rejectionReason: "accuracy_negative")
            }
            if accuracy > thresholds.maxHorizontalAccuracyM {
                return Outcome(
                    raw: tick,
                    usableSpeedMps: nil,
                    rejectionReason: "accuracy>\(Int(thresholds.maxHorizontalAccuracyM))m"
                )
            }
        }

        let speedKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: speed)
        if speedKmh > thresholds.maxPlausibleSpeedKmh {
            return Outcome(
                raw: tick,
                usableSpeedMps: nil,
                rejectionReason: "speed>\(fmt(thresholds.maxPlausibleSpeedKmh))km/h_implausible"
            )
        }

        if let previous = previousUsableSpeedMps {
            let previousKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: previous)
            let delta = abs(speedKmh - previousKmh)
            if delta >= thresholds.maxSpeedJumpKmh {
                return Outcome(
                    raw: tick,
                    usableSpeedMps: nil,
                    rejectionReason: "speed_jump_\(fmt(delta))km/h"
                )
            }
        }

        return Outcome(raw: tick, usableSpeedMps: speed, rejectionReason: nil)
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
