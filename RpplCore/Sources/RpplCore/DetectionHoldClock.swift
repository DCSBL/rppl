import Foundation

public enum DetectionHoldKind: String, CaseIterable, Sendable, Equatable {
    case highSpeed
    case stopped
    case unusable
}

/// Tracks how long each hold predicate has been continuously true.
public struct DetectionHoldClock: Sendable, Equatable {
    private var startedAt: [DetectionHoldKind: Date] = [:]
    /// True while `.highSpeed` is active and it started from walk-band (or nil) previous speed.
    public private(set) var highSpeedFromWalk = false

    public init() {}

    public mutating func clear() {
        startedAt.removeAll()
        highSpeedFromWalk = false
    }

    public func duration(_ kind: DetectionHoldKind, at timestamp: Date) -> TimeInterval? {
        guard let start = startedAt[kind] else { return nil }
        return timestamp.timeIntervalSince(start)
    }

    /// Enter hold: walk-band starts need the longer `rideEnterHoldFromWalk`.
    public func requiredRideEnterHold(_ thresholds: DetectionThresholds) -> TimeInterval {
        highSpeedFromWalk ? thresholds.rideEnterHoldFromWalk : thresholds.rideEnterHold
    }

    public mutating func update(
        timestamp: Date,
        usableSpeedMps: Double?,
        previousUsableSpeedMps: Double?,
        thresholds: DetectionThresholds
    ) {
        let high = usableSpeedMps.map { $0 >= thresholds.rideEnterSpeedMps } ?? false
        if high {
            if startedAt[.highSpeed] == nil {
                startedAt[.highSpeed] = timestamp
                if let previous = previousUsableSpeedMps {
                    highSpeedFromWalk = previous <= thresholds.walkBandSpeedMps
                } else {
                    highSpeedFromWalk = false
                }
            }
        } else {
            startedAt[.highSpeed] = nil
            highSpeedFromWalk = false
        }
        set(
            .stopped,
            active: usableSpeedMps.map { $0 <= thresholds.stoppedSpeedMps } ?? false,
            at: timestamp
        )
        set(.unusable, active: usableSpeedMps == nil, at: timestamp)
    }

    private mutating func set(_ kind: DetectionHoldKind, active: Bool, at timestamp: Date) {
        if active {
            if startedAt[kind] == nil {
                startedAt[kind] = timestamp
            }
        } else {
            startedAt[kind] = nil
        }
    }
}
