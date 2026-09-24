import Foundation

/// Read-only snapshot for evaluating one detector.
public struct DetectionEvalContext: Sendable {
    public var currentCode: String
    public var tick: DetectionTick
    public var usableSpeedMps: Double?
    public var unsureAge: TimeInterval?
    public var holds: DetectionHoldClock
    public var thresholds: DetectionThresholds

    public var speedUsable: Bool { usableSpeedMps != nil }

    public func held(_ kind: DetectionHoldKind) -> TimeInterval? {
        holds.duration(kind, at: tick.timestamp)
    }

    public func speedKmhText() -> String {
        SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: tick.speedMps)
    }

    public func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// Pure detector plugin. Add new structs + append to `DetectionEngine.defaultDetectors`.
public protocol Detector: Sendable {
    var id: String { get }
    func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal?
}

public struct RideEnterDetector: Detector {
    public let id = "ride_enter"

    public init() {}

    public func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
        guard ctx.currentCode == DetectionCodes.inactive else { return nil }
        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.highSpeed) else { return nil }
        let required = ctx.holds.requiredRideEnterHold(ctx.thresholds)
        guard held >= required else { return nil }
        let from = ctx.holds.highSpeedFromWalk ? "walk" : "inactive"
        let reason =
            "ride_enter speed=\(ctx.speedKmhText())>=\(ctx.fmt(ctx.thresholds.rideEnterSpeedKmh))"
            + " for \(ctx.fmt(held))s from=\(from)"
        return DetectionSignal(kind: .enterRide, detectorId: id, reason: reason)
    }
}

public struct RideExitDetector: Detector {
    public let id = "ride_exit"

    public init() {}

    public func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
        guard ctx.currentCode == DetectionCodes.riding else { return nil }
        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.stopped), held >= ctx.thresholds.rideExitHold else { return nil }
        let reason =
            "ride_exit speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.stoppedSpeedKmh))"
            + " for \(ctx.fmt(held))s from=riding"
        return DetectionSignal(kind: .exitRide, detectorId: id, reason: reason)
    }
}

/// The fast `ride_exit` rule waits for <=4 km/h, but letting go of the cable leaves the rider
/// swimming or coasting in the 4-8 km/h band for tens of seconds while the cable runs ~31 km/h.
/// This ends the set where the rider left the cable, so the decay tail is not counted as riding.
public struct RideExitOffCableDetector: Detector {
    public let id = "ride_exit_offcable"

    public init() {}

    public func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
        guard ctx.currentCode == DetectionCodes.riding else { return nil }
        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.offCable), held >= ctx.thresholds.offCableExitHold else {
            return nil
        }
        let reason =
            "ride_exit_offcable speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.offCableSpeedKmh))"
            + " for \(ctx.fmt(held))s from=riding"
        return DetectionSignal(kind: .exitRideOffCable, detectorId: id, reason: reason)
    }
}

/// What the engine knows about the set that is currently open.
public struct DetectionSetContext: Sendable, Equatable {
    /// Id of the `ride_enter` event that opened the set — what a revocation supersedes.
    public var enterEventId: String
    public var startedAt: Date
    /// Seconds at or above `rideEnterSpeedKmh` inside the set, seeded with the enter hold.
    public var cableEvidence: TimeInterval

    public init(enterEventId: String, startedAt: Date, cableEvidence: TimeInterval) {
        self.enterEventId = enterEventId
        self.startedAt = startedAt
        self.cableEvidence = cableEvidence
    }
}

/// Decides whether a set that just ended was never a set: a dock GPS spike, or a yank that never
/// became riding. Not a `Detector` — it judges a set at the moment it closes rather than
/// proposing a transition, and the engine turns its verdict into a revocation of the enter.
public struct FailedStartRule: Sendable {
    public static let id = "failed_start"

    public init() {}

    /// Returns a reason when the set should be revoked, `nil` when it stands.
    public func evaluate(
        set: DetectionSetContext,
        endedAt: Date,
        thresholds: DetectionThresholds
    ) -> String? {
        let age = endedAt.timeIntervalSince(set.startedAt)
        guard age < thresholds.failedStartMaxAge else { return nil }
        guard set.cableEvidence < thresholds.failedStartCableEvidence else { return nil }
        return "failed_start age=\(fmt(age))s<\(fmt(thresholds.failedStartMaxAge))s"
            + " cable=\(fmt(set.cableEvidence))s<\(fmt(thresholds.failedStartCableEvidence))s"
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

public struct GpsGapDetector: Detector {
    public let id = "gps_gap"

    public init() {}

    public func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
        guard ctx.currentCode == DetectionCodes.riding else { return nil }
        guard let held = ctx.held(.unusable), held >= ctx.thresholds.gapUnsureHold else { return nil }
        let reason = "gps_gap unusable for \(ctx.fmt(held))s from=riding"
        return DetectionSignal(kind: .enterUnsure, detectorId: id, reason: reason)
    }
}

public struct UnsureTimeoutDetector: Detector {
    public let id = "unsure_timeout"

    public init() {}

    public func evaluate(_ ctx: DetectionEvalContext) -> DetectionSignal? {
        guard ctx.currentCode == DetectionCodes.unsure else { return nil }
        guard let age = ctx.unsureAge, age >= ctx.thresholds.unsureSameRideWindow else { return nil }
        let reason =
            "unsure_timeout age=\(ctx.fmt(age))s>=\(ctx.fmt(ctx.thresholds.unsureSameRideWindow))s"
        return DetectionSignal(kind: .unsureTimeout, detectorId: id, reason: reason)
    }
}
