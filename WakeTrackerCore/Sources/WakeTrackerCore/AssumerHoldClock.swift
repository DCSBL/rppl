import Foundation

/// Named sustained predicates. Add a case + predicate in `AssumerHoldClock.update` to track new holds.
public enum AssumerHoldKind: String, CaseIterable, Sendable, Equatable {
    case highSpeed
    case stopped
    case walkBand
    case waitSettle
}

/// Tracks how long each hold predicate has been continuously true.
public struct AssumerHoldClock: Sendable, Equatable {
    private var startedAt: [AssumerHoldKind: Date] = [:]

    public init() {}

    public mutating func clear() {
        startedAt.removeAll()
    }

    public func duration(_ kind: AssumerHoldKind, at timestamp: Date) -> TimeInterval? {
        guard let start = startedAt[kind] else { return nil }
        return timestamp.timeIntervalSince(start)
    }

    public mutating func update(
        timestamp: Date,
        usableSpeedMps: Double?,
        thresholds: AssumptionThresholds
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
        set(
            .walkBand,
            active: usableSpeedMps.map {
                $0 >= thresholds.walkSpeedMinMps && $0 <= thresholds.walkSpeedMaxMps
            } ?? false,
            at: timestamp
        )
        set(
            .waitSettle,
            active: usableSpeedMps.map { $0 <= thresholds.waitSpeedMps } ?? false,
            at: timestamp
        )
    }

    private mutating func set(_ kind: AssumerHoldKind, active: Bool, at timestamp: Date) {
        if active {
            if startedAt[kind] == nil {
                startedAt[kind] = timestamp
            }
        } else {
            startedAt[kind] = nil
        }
    }
}
