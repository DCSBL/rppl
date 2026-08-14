import Foundation

/// Pure orchestrator: filter → holds → lookback / detectors → detection events.
/// Manual labels are not part of this pipeline.
public struct DetectionEngine: Sendable {
    public var thresholds: DetectionThresholds {
        didSet {
            filter.thresholds = thresholds
        }
    }

    public private(set) var currentCode: String
    /// Last `riding` / `paused` for Watch primary UI while `currentCode` may be `unsure`.
    public private(set) var lastConfidentCode: String
    public private(set) var lastFilterRejection: String?

    private var filter: GpsSignalFilter
    private var detectors: [any Detector]
    private var holds = DetectionHoldClock()
    private var previousUsableSpeedMps: Double?
    private var unsureEnteredAt: Date?
    private var unsureEventId: String?

    public init(
        thresholds: DetectionThresholds = .default,
        detectors: [any Detector]? = nil,
        filter: GpsSignalFilter? = nil
    ) {
        self.thresholds = thresholds
        self.detectors = detectors ?? Self.defaultDetectors
        self.filter = filter ?? GpsSignalFilter(thresholds: thresholds)
        self.currentCode = DetectionCodes.paused
        self.lastConfidentCode = DetectionCodes.paused
    }

    public static var defaultDetectors: [any Detector] {
        [
            UnsureTimeoutDetector(),
            GpsGapDetector(),
            RideExitDetector(),
            RideEnterDetector(),
        ]
    }

    /// Emit session-start `paused` and reset state. Call once when recording begins.
    public mutating func makeSessionStartEvent(at timestamp: Date = Date()) -> DetectionEvent {
        currentCode = DetectionCodes.paused
        lastConfidentCode = DetectionCodes.paused
        previousUsableSpeedMps = nil
        lastFilterRejection = nil
        unsureEnteredAt = nil
        unsureEventId = nil
        holds.clear()
        return DetectionEvent(
            code: DetectionCodes.paused,
            timestamp: timestamp,
            reason: "session_start",
            detectorId: "session_start"
        )
    }

    /// Process one sensor tick. Returns zero or more events (transition and/or lookback revision).
    public mutating func process(_ tick: DetectionTick) -> [DetectionEvent] {
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

        var events: [DetectionEvent] = []

        if currentCode == DetectionCodes.unsure, let usable = outcome.usableSpeedMps {
            if let lookback = applyLookback(tick: tick, usableSpeedMps: usable) {
                events.append(lookback)
                return events
            }
        }

        let unsureAge = unsureEnteredAt.map { tick.timestamp.timeIntervalSince($0) }
        let ctx = DetectionEvalContext(
            currentCode: currentCode,
            tick: tick,
            usableSpeedMps: outcome.usableSpeedMps,
            unsureAge: unsureAge,
            holds: holds,
            thresholds: thresholds
        )

        for detector in detectors {
            guard let signal = detector.evaluate(ctx) else { continue }
            if let event = apply(signal: signal, tick: tick) {
                events.append(event)
            }
            break
        }

        return events
    }

    /// Offline replay using the same live pipeline.
    public static func replay(
        ticks: [DetectionTick],
        thresholds: DetectionThresholds = .default,
        detectors: [any Detector]? = nil
    ) -> [DetectionEvent] {
        var engine = DetectionEngine(thresholds: thresholds, detectors: detectors)
        var events: [DetectionEvent] = []
        if let first = ticks.first {
            events.append(engine.makeSessionStartEvent(at: first.timestamp))
        } else {
            events.append(engine.makeSessionStartEvent())
        }
        for tick in ticks {
            events.append(contentsOf: engine.process(tick))
        }
        return events
    }

    /// Map location samples into ticks (speed/accuracy only) and replay.
    public static func replay(
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default
    ) -> [DetectionEvent] {
        let ticks = locations.map { sample in
            DetectionTick(
                timestamp: sample.timestamp,
                speedMps: sample.speed,
                horizontalAccuracy: sample.horizontalAccuracy
            )
        }
        return replay(ticks: ticks, thresholds: thresholds)
    }

    private mutating func applyLookback(tick: DetectionTick, usableSpeedMps: Double) -> DetectionEvent? {
        let age = unsureEnteredAt.map { tick.timestamp.timeIntervalSince($0) } ?? 0
        guard age < thresholds.unsureSameRideWindow else {
            // Window expired — timeout detector (or next tick) commits pause; no same-ride merge.
            return nil
        }

        let supersedes = unsureEventId
        if usableSpeedMps >= thresholds.rideEnterSpeedMps {
            let reason =
                "lookback_same_ride age=\(fmt(age))s<\(fmt(thresholds.unsureSameRideWindow))s"
                + " speed=\(SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: usableSpeedMps))"
            return revise(
                code: DetectionCodes.riding,
                reason: reason,
                detectorId: "lookback",
                tick: tick,
                supersedesId: supersedes
            )
        }

        if usableSpeedMps <= thresholds.stoppedSpeedMps {
            let reason =
                "lookback_pause age=\(fmt(age))s<\(fmt(thresholds.unsureSameRideWindow))s"
                + " speed=\(SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: usableSpeedMps))"
            return revise(
                code: DetectionCodes.paused,
                reason: reason,
                detectorId: "lookback",
                tick: tick,
                supersedesId: supersedes
            )
        }

        // Mid-band usable speed: stay unsure until enter/exit/timeout clarity.
        return nil
    }

    private mutating func apply(signal: DetectionSignal, tick: DetectionTick) -> DetectionEvent? {
        switch signal.kind {
        case .enterRide:
            return transition(
                to: DetectionCodes.riding,
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick
            )
        case .exitRide:
            return transition(
                to: DetectionCodes.paused,
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick
            )
        case .enterUnsure:
            return transition(
                to: DetectionCodes.unsure,
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick
            )
        case .unsureTimeout:
            return transition(
                to: DetectionCodes.paused,
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick
            )
        }
    }

    private mutating func transition(
        to code: String,
        reason: String,
        detectorId: String,
        tick: DetectionTick
    ) -> DetectionEvent {
        currentCode = code
        if DetectionCodes.isConfident(code) {
            lastConfidentCode = code
            unsureEnteredAt = nil
            unsureEventId = nil
        } else if code == DetectionCodes.unsure {
            unsureEnteredAt = tick.timestamp
        }
        holds.clear()
        let event = DetectionEvent(
            code: code,
            timestamp: tick.timestamp,
            reason: reason,
            detectorId: detectorId,
            speedMps: tick.speedMps,
            horizontalAccuracy: tick.horizontalAccuracy,
            waterSubmersionState: tick.waterSubmersionState,
            motionActivity: tick.motionActivity
        )
        if code == DetectionCodes.unsure {
            unsureEventId = event.id
        }
        return event
    }

    private mutating func revise(
        code: String,
        reason: String,
        detectorId: String,
        tick: DetectionTick,
        supersedesId: String?
    ) -> DetectionEvent {
        currentCode = code
        if DetectionCodes.isConfident(code) {
            lastConfidentCode = code
        }
        unsureEnteredAt = nil
        unsureEventId = nil
        holds.clear()
        return DetectionEvent(
            code: code,
            timestamp: tick.timestamp,
            reason: reason,
            detectorId: detectorId,
            speedMps: tick.speedMps,
            horizontalAccuracy: tick.horizontalAccuracy,
            waterSubmersionState: tick.waterSubmersionState,
            motionActivity: tick.motionActivity,
            supersedesId: supersedesId
        )
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
