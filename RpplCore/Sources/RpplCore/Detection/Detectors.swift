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
