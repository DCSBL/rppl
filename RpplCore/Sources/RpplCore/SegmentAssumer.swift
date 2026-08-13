import Foundation

/// Pure FSM orchestrator: filter → hold clocks → ordered transition rules.
/// Manual Action Button labels never call into this type — tracks stay independent.
public struct SegmentAssumer: Sendable {
    public var thresholds: AssumptionThresholds {
        didSet {
            filter.thresholds = thresholds
        }
    }

    public private(set) var currentCode: String
    public private(set) var lastFilterRejection: String?

    private var filter: AssumerSignalFilter
    private var rules: AssumerRuleSet
    private var holds = AssumerHoldClock()
    private var rideEnteredAt: Date?
    private var previousUsableSpeedMps: Double?

    public init(
        thresholds: AssumptionThresholds = .default,
        rules: AssumerRuleSet = .cableParkV0,
        filter: AssumerSignalFilter? = nil
    ) {
        self.thresholds = thresholds
        self.rules = rules
        self.filter = filter ?? AssumerSignalFilter(thresholds: thresholds)
        self.currentCode = LabelCodes.waiting
    }

    /// Emit session-start `waiting` and reset holds. Call once when recording begins.
    public mutating func makeSessionStartEvent(at timestamp: Date = Date()) -> AssumptionEvent {
        currentCode = LabelCodes.waiting
        rideEnteredAt = nil
        previousUsableSpeedMps = nil
        lastFilterRejection = nil
        holds.clear()
        return AssumptionEvent(
            code: LabelCodes.waiting,
            timestamp: timestamp,
            reason: "session_start"
        )
    }

    /// Process one sensor tick. Returns an event only when assumed `code` changes.
    public mutating func process(_ tick: AssumerTick) -> AssumptionEvent? {
        let outcome = filter.evaluate(tick, previousUsableSpeedMps: previousUsableSpeedMps)
        lastFilterRejection = outcome.rejectionReason
        if let usable = outcome.usableSpeedMps {
            previousUsableSpeedMps = usable
        }

        holds.update(
            timestamp: tick.timestamp,
            usableSpeedMps: outcome.usableSpeedMps,
            thresholds: thresholds
        )

        let rideAge = rideEnteredAt.map { tick.timestamp.timeIntervalSince($0) }
        let ctx = AssumerEvalContext(
            currentCode: currentCode,
            tick: tick,
            usableSpeedMps: outcome.usableSpeedMps,
            rideAge: rideAge,
            holds: holds,
            thresholds: thresholds
        )

        guard let match = rules.firstMatch(from: currentCode, ctx: ctx) else {
            return nil
        }
        return apply(code: match.to, reason: match.reason, tick: tick)
    }

    private mutating func apply(code: String, reason: String, tick: AssumerTick) -> AssumptionEvent {
        let from = currentCode
        currentCode = code
        if code == LabelCodes.riding {
            rideEnteredAt = tick.timestamp
        } else if from == LabelCodes.riding {
            rideEnteredAt = nil
        }
        holds.clear()
        return AssumptionEvent(
            code: code,
            timestamp: tick.timestamp,
            reason: reason,
            speedMps: tick.speedMps,
            waterSubmersionState: tick.waterSubmersionState,
            motionActivity: tick.motionActivity
        )
    }
}
