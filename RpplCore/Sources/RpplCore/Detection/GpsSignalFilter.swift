import Foundation

/// GPS / speed quality gate before hold clocks and detectors see a tick.
public struct GpsSignalFilter: Equatable, Sendable {
    public var thresholds: DetectionThresholds

    public init(thresholds: DetectionThresholds = .default) {
        self.thresholds = thresholds
    }

    public static let `default` = GpsSignalFilter()

    public struct Outcome: Equatable, Sendable {
        public var raw: DetectionTick
        public var usableSpeedMps: Double?
        public var rejectionReason: String?
        /// Speed rejected as a jump. Feed back as `pendingJumpSpeedMps` on the next tick so a
        /// sustained step is accepted on its second sample.
        public var jumpCandidateSpeedMps: Double?

        public var speedUsable: Bool { usableSpeedMps != nil }
    }

    /// - Parameters:
    ///   - previousUsableAt: timestamp of `previousUsableSpeedMps`; when older than
    ///     `maxSpeedJumpWindow` the jump test is skipped.
    ///   - pendingJumpSpeedMps: speed the previous tick rejected as a jump.
    public func evaluate(
        _ tick: DetectionTick,
        previousUsableSpeedMps: Double?,
        previousUsableAt: Date? = nil,
        pendingJumpSpeedMps: Double? = nil
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

        if let previous = previousUsableSpeedMps, !jumpComparisonExpired(tick, previousUsableAt) {
            let previousKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: previous)
            let delta = abs(speedKmh - previousKmh)
            if delta >= thresholds.maxSpeedJumpKmh, !corroborates(speedKmh, pendingJumpSpeedMps) {
                return Outcome(
                    raw: tick,
                    usableSpeedMps: nil,
                    rejectionReason: "speed_jump_\(fmt(delta))km/h",
                    jumpCandidateSpeedMps: speed
                )
            }
        }

        return Outcome(raw: tick, usableSpeedMps: speed, rejectionReason: nil)
    }

    private func jumpComparisonExpired(_ tick: DetectionTick, _ previousUsableAt: Date?) -> Bool {
        guard let previousUsableAt else { return false }
        return tick.timestamp.timeIntervalSince(previousUsableAt) > thresholds.maxSpeedJumpWindow
    }

    private func corroborates(_ speedKmh: Double, _ pendingJumpSpeedMps: Double?) -> Bool {
        guard let pendingJumpSpeedMps else { return false }
        let pendingKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: pendingJumpSpeedMps)
        return abs(speedKmh - pendingKmh) <= thresholds.speedJumpCorroborationKmh
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
