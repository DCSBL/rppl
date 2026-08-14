import Foundation

public enum DetectionHoldKind: String, CaseIterable, Sendable, Equatable {
    case highSpeed
    case stopped
    case unusable
}

/// Tracks how long each hold predicate has been continuously true.
public struct DetectionHoldClock: Sendable, Equatable {
    private var startedAt: [DetectionHoldKind: Date] = [:]

    public init() {}

    public mutating func clear() {
        startedAt.removeAll()
    }

    public func duration(_ kind: DetectionHoldKind, at timestamp: Date) -> TimeInterval? {
        guard let start = startedAt[kind] else { return nil }
        return timestamp.timeIntervalSince(start)
    }

    public mutating func update(
        timestamp: Date,
        usableSpeedMps: Double?,
        thresholds: DetectionThresholds
    ) {
        set(
            .highSpeed,
            active: usableSpeedMps.map { $0 >= thresholds.rideEnterSpeedMps } ?? false,
            at: timestamp
        )
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
