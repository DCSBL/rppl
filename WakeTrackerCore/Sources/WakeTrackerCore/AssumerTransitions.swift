import Foundation

/// Read-only snapshot for evaluating one transition rule.
public struct AssumerEvalContext: Sendable {
    public var currentCode: String
    public var tick: AssumerTick
    public var usableSpeedMps: Double?
    public var rideAge: TimeInterval?
    public var holds: AssumerHoldClock
    public var thresholds: AssumptionThresholds

    public var speedUsable: Bool { usableSpeedMps != nil }

    public func held(_ kind: AssumerHoldKind) -> TimeInterval? {
        holds.duration(kind, at: tick.timestamp)
    }

    public var isSubmerged: Bool {
        tick.waterSubmersionState == "submerged"
    }

    public var isNotSubmerged: Bool {
        tick.waterSubmersionState == "notSubmerged"
    }

    public func speedKmhText() -> String {
        SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: tick.speedMps)
    }

    public func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// One directed edge in the segment FSM. Add a new struct + append to `AssumerRuleSet` to extend.
public protocol AssumerTransitionRule: Sendable {
    var id: String { get }
    var from: String { get }
    var to: String { get }
    /// Non-nil reason means this rule fires (first match wins for a given `from`).
    func reasonIfMatches(_ ctx: AssumerEvalContext) -> String?
}

/// Result of the first matching transition rule.
public struct AssumerRuleMatch: Equatable, Sendable {
    public var id: String
    public var to: String
    public var reason: String

    public init(id: String, to: String, reason: String) {
        self.id = id
        self.to = to
        self.reason = reason
    }
}

/// Ordered rule list. Priority = array order within the same `from` state.
public struct AssumerRuleSet: Sendable {
    public var rules: [any AssumerTransitionRule]

    public init(rules: [any AssumerTransitionRule]) {
        self.rules = rules
    }

    public func firstMatch(from code: String, ctx: AssumerEvalContext) -> AssumerRuleMatch? {
        for rule in rules where rule.from == code {
            if let reason = rule.reasonIfMatches(ctx) {
                return AssumerRuleMatch(id: rule.id, to: rule.to, reason: reason)
            }
        }
        return nil
    }

    /// Cable-park v0 transitions (corpus Assumer).
    public static let cableParkV0 = AssumerRuleSet(rules: [
        RideStartRule(reasonPrefix: "ride_start"),
        WalkFromWaitingRule(),
        FallSwimRule(),
        FailedStartRule(),
        LongStopRule(),
        WaterStartRule(),
        WalkFromSwimmingRule(),
        WaitSettleRule(),
    ])
}

// MARK: - Cable-park rules

public struct RideStartRule: AssumerTransitionRule {
    public let id = "ride_start"
    public let from: String
    public let to = LabelCodes.riding
    public var reasonPrefix: String

    public init(from: String = LabelCodes.waiting, reasonPrefix: String = "ride_start") {
        self.from = from
        self.reasonPrefix = reasonPrefix
    }

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.highSpeed), held >= ctx.thresholds.rideEnterHold else { return nil }
        return "\(reasonPrefix) speed=\(ctx.speedKmhText())>=\(ctx.fmt(ctx.thresholds.rideEnterSpeedKmh)) for \(ctx.fmt(held))s from=\(ctx.currentCode)"
    }
}

public struct WaterStartRule: AssumerTransitionRule {
    public let id = "water_start"
    public let from = LabelCodes.swimming
    public let to = LabelCodes.riding

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.highSpeed), held >= ctx.thresholds.rideEnterHold else { return nil }
        return "water_start speed=\(ctx.speedKmhText())>=\(ctx.fmt(ctx.thresholds.rideEnterSpeedKmh)) for \(ctx.fmt(held))s from=swimming"
    }
}

public struct FallSwimRule: AssumerTransitionRule {
    public let id = "fall_swim"
    public let from = LabelCodes.riding
    public let to = LabelCodes.swimming

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.isSubmerged else { return nil }
        if let speed = ctx.tick.speedMps, speed > ctx.thresholds.swimMaxSpeedMps {
            return nil
        }
        return "fall_swim submerged speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.swimMaxSpeedKmh)) from=riding"
    }
}

public struct FailedStartRule: AssumerTransitionRule {
    public let id = "failed_start"
    public let from = LabelCodes.riding
    public let to = LabelCodes.waiting

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.speedUsable, let speed = ctx.usableSpeedMps else { return nil }
        guard !ctx.isSubmerged else { return nil }
        guard speed <= ctx.thresholds.stoppedSpeedMps else { return nil }
        guard let rideAge = ctx.rideAge, rideAge < ctx.thresholds.failedStartMaxRide else { return nil }
        return "failed_start rideAge=\(ctx.fmt(rideAge))s<\(ctx.fmt(ctx.thresholds.failedStartMaxRide)) speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.stoppedSpeedKmh)) from=riding"
    }
}

public struct LongStopRule: AssumerTransitionRule {
    public let id = "long_stop"
    public let from = LabelCodes.riding
    public let to = LabelCodes.waiting

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.speedUsable else { return nil }
        guard !ctx.isSubmerged else { return nil }
        guard let rideAge = ctx.rideAge, rideAge >= ctx.thresholds.failedStartMaxRide else { return nil }
        guard let held = ctx.held(.stopped), held >= ctx.thresholds.longStopHold else { return nil }
        return "long_stop rideAge=\(ctx.fmt(rideAge))s speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.stoppedSpeedKmh)) for \(ctx.fmt(held))s from=riding"
    }
}

public struct WalkFromWaitingRule: AssumerTransitionRule {
    public let id = "walk_from_waiting"
    public let from = LabelCodes.waiting
    public let to = LabelCodes.walking

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        WalkSignal.reason(ctx, requireNotSubmerged: false)
    }
}

public struct WalkFromSwimmingRule: AssumerTransitionRule {
    public let id = "walk_from_swimming"
    public let from = LabelCodes.swimming
    public let to = LabelCodes.walking

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        WalkSignal.reason(ctx, requireNotSubmerged: true)
    }
}

public struct WaitSettleRule: AssumerTransitionRule {
    public let id = "wait_settle"
    public let from = LabelCodes.walking
    public let to = LabelCodes.waiting

    public init() {}

    public func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
        guard ctx.speedUsable else { return nil }
        guard ctx.tick.motionActivity != "walking" else { return nil }
        guard let held = ctx.held(.waitSettle), held >= ctx.thresholds.waitHold else { return nil }
        return "wait_settle speed=\(ctx.speedKmhText())<=\(ctx.fmt(ctx.thresholds.waitSpeedKmh)) for \(ctx.fmt(held))s from=walking"
    }
}

enum WalkSignal {
    static func reason(_ ctx: AssumerEvalContext, requireNotSubmerged: Bool) -> String? {
        if requireNotSubmerged {
            guard ctx.isNotSubmerged else { return nil }
        } else if ctx.isSubmerged {
            return nil
        }

        if ctx.tick.motionActivity == "walking" {
            return "walk activity=walking from=\(ctx.currentCode)"
        }

        guard ctx.speedUsable else { return nil }
        guard let held = ctx.held(.walkBand) else { return nil }
        guard held >= ctx.thresholds.walkHold else { return nil }
        return "walk speed=\(ctx.speedKmhText()) in \(ctx.fmt(ctx.thresholds.walkSpeedMinKmh))…\(ctx.fmt(ctx.thresholds.walkSpeedMaxKmh)) for \(ctx.fmt(held))s from=\(ctx.currentCode)"
    }
}
