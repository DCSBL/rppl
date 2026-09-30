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
    /// Last `riding` / `inactive` for Watch primary UI while `currentCode` may be `unsure`.
    public private(set) var lastConfidentCode: String
    public private(set) var lastFilterRejection: String?

    private var filter: GpsSignalFilter
    private var detectors: [any Detector]
    private var holds = DetectionHoldClock()
    private var previousUsableSpeedMps: Double?
    private var previousUsableAt: Date?
    private var pendingJumpSpeedMps: Double?
    private var unsureEnteredAt: Date?
    private var unsureEventId: String?
    private var openSet: DetectionSetContext?
    private var lastEvidenceAt: Date?
    /// Latest tick of any kind, and latest fresh fix — the stale-fix guard compares against both.
    private var lastTickAt: Date?
    private var lastFixAt: Date?
    private let failedStartRule = FailedStartRule()

    public init(
        thresholds: DetectionThresholds = .default,
        detectors: [any Detector]? = nil,
        filter: GpsSignalFilter? = nil
    ) {
        self.thresholds = thresholds
        self.detectors = detectors ?? Self.defaultDetectors
        self.filter = filter ?? GpsSignalFilter(thresholds: thresholds)
        self.currentCode = DetectionCodes.inactive
        self.lastConfidentCode = DetectionCodes.inactive
    }

    public static var defaultDetectors: [any Detector] {
        [
            UnsureTimeoutDetector(),
            GpsGapDetector(),
            RideExitDetector(),
            RideExitOffCableDetector(),
            RideEnterDetector(),
        ]
    }

    /// Emit session-start `inactive` and reset state. Call once when recording begins.
    public mutating func makeSessionStartEvent(at timestamp: Date = Date()) -> DetectionEvent {
        makeForcedInactiveEvent(at: timestamp, reason: "session_start", detectorId: "session_start")
    }

    /// Force `inactive` and reset holds/filter state (product pause/resume, etc.).
    public mutating func makeForcedInactiveEvent(
        at timestamp: Date = Date(),
        reason: String,
        detectorId: String
    ) -> DetectionEvent {
        currentCode = DetectionCodes.inactive
        lastConfidentCode = DetectionCodes.inactive
        previousUsableSpeedMps = nil
        previousUsableAt = nil
        pendingJumpSpeedMps = nil
        lastFilterRejection = nil
        unsureEnteredAt = nil
        unsureEventId = nil
        openSet = nil
        lastEvidenceAt = nil
        lastTickAt = nil
        lastFixAt = nil
        holds.clear()
        return DetectionEvent(
            code: DetectionCodes.inactive,
            timestamp: timestamp,
            reason: reason,
            detectorId: detectorId
        )
    }

    /// Process one sensor tick. Returns zero or more events (transition and/or lookback revision).
    public mutating func process(_ tick: DetectionTick) -> [DetectionEvent] {
        if let rejection = staleFixRejection(tick) {
            lastFilterRejection = rejection
            return []
        }
        if tick.hasFreshFix {
            lastFixAt = tick.timestamp
        }
        lastTickAt = max(lastTickAt ?? tick.timestamp, tick.timestamp)

        let outcome = filter.evaluate(
            tick,
            previousUsableSpeedMps: previousUsableSpeedMps,
            previousUsableAt: previousUsableAt,
            pendingJumpSpeedMps: pendingJumpSpeedMps
        )
        if tick.hasFreshFix {
            lastFilterRejection = outcome.rejectionReason
            pendingJumpSpeedMps = outcome.jumpCandidateSpeedMps
        }
        holds.update(
            timestamp: tick.timestamp,
            usableSpeedMps: outcome.usableSpeedMps,
            previousUsableSpeedMps: previousUsableSpeedMps,
            thresholds: thresholds,
            hasFreshFix: tick.hasFreshFix
        )
        if let usable = outcome.usableSpeedMps {
            accumulateCableEvidence(usableSpeedMps: usable, at: tick.timestamp)
            previousUsableSpeedMps = usable
            previousUsableAt = tick.timestamp
        }

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
    ///
    /// Heartbeats are injected between fixes at `heartbeatInterval` so an offline replay sees the
    /// same clock the Watch does; without them a GPS blackout produces no `gps_gap` /
    /// `unsure_timeout` at all. Pass `nil` for fix-only replay.
    public static func replay(
        locations: [LocationSample],
        thresholds: DetectionThresholds = .default,
        heartbeatInterval: TimeInterval? = 1.0
    ) -> [DetectionEvent] {
        let fixes = locations
            .sorted { $0.timestamp < $1.timestamp }
            .map { sample in
                DetectionTick(
                    timestamp: sample.timestamp,
                    speedMps: sample.speed,
                    horizontalAccuracy: sample.horizontalAccuracy
                )
            }
        return replay(ticks: withHeartbeats(fixes, every: heartbeatInterval), thresholds: thresholds)
    }

    /// Interleave heartbeat ticks so silence between fixes advances the gap / timeout clocks.
    static func withHeartbeats(
        _ fixes: [DetectionTick],
        every interval: TimeInterval?
    ) -> [DetectionTick] {
        guard let interval, interval > 0, let first = fixes.first else { return fixes }
        var out: [DetectionTick] = [first]
        out.reserveCapacity(fixes.count)
        for fix in fixes.dropFirst() {
            var next = out[out.count - 1].timestamp.addingTimeInterval(interval)
            while next < fix.timestamp {
                out.append(.heartbeat(at: next))
                next = next.addingTimeInterval(interval)
            }
            out.append(fix)
        }
        return out
    }

    /// A fix that arrives after the clock has moved past it says nothing about now: replaying it
    /// would rewind the hold clocks and backdate transitions into a window that heartbeats already
    /// judged (a GPS batch delivered late once re-opened a set a minute after it timed out).
    /// Heartbeats are never stale; they are the clock.
    private func staleFixRejection(_ tick: DetectionTick) -> String? {
        guard tick.hasFreshFix else { return nil }
        if let lastFixAt, tick.timestamp < lastFixAt {
            return "fix_out_of_order"
        }
        if let lastTickAt, lastTickAt.timeIntervalSince(tick.timestamp) > thresholds.maxFixLag {
            return "fix_stale>\(fmt(thresholds.maxFixLag))s"
        }
        return nil
    }

    /// Count seconds spent at cable speed inside the open set. Silence is not credited: a gap
    /// longer than `gapUnsureHold` contributes only that much, because we cannot know the rest.
    private mutating func accumulateCableEvidence(usableSpeedMps: Double, at timestamp: Date) {
        defer { lastEvidenceAt = timestamp }
        guard openSet != nil, usableSpeedMps >= thresholds.rideEnterSpeedMps else { return }
        guard let last = lastEvidenceAt else { return }
        let step = timestamp.timeIntervalSince(last)
        guard step > 0 else { return }
        openSet?.cableEvidence += min(step, thresholds.gapUnsureHold)
    }

    private mutating func applyLookback(tick: DetectionTick, usableSpeedMps: Double) -> DetectionEvent? {
        let age = unsureEnteredAt.map { tick.timestamp.timeIntervalSince($0) } ?? 0
        guard age < thresholds.unsureSameRideWindow else {
            // Window expired — timeout detector (or next tick) commits pause; no same-set merge.
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
            // Riding ended when the evidence did, not when GPS came back: backdate to the unsure
            // start so the set window does not swallow the gap it replaces.
            let endedAt = unsureEnteredAt ?? tick.timestamp
            var reason =
                "lookback_inactive age=\(fmt(age))s<\(fmt(thresholds.unsureSameRideWindow))s"
                + " speed=\(SpeedUnits.reasonKilometersPerHour(fromMetersPerSecond: usableSpeedMps))"
            if endedAt != tick.timestamp {
                reason += " backfill_from=\(fmt(endedAt.timeIntervalSince1970))s"
            }
            return revise(
                code: DetectionCodes.inactive,
                reason: reason,
                detectorId: "lookback",
                tick: tick,
                timestamp: endedAt,
                supersedesId: supersedes
            )
        }

        // Mid-band usable speed: stay unsure until enter/exit/timeout clarity.
        return nil
    }

    private mutating func apply(signal: DetectionSignal, tick: DetectionTick) -> DetectionEvent? {
        switch signal.kind {
        case .enterRide:
            let holdStart = holds.highSpeedStartedAt ?? tick.timestamp
            var reason = signal.reason
            if holdStart != tick.timestamp {
                reason += " backfill_from=\(fmt(holdStart.timeIntervalSince1970))s"
            }
            let event = transition(
                to: DetectionCodes.riding,
                reason: reason,
                detectorId: signal.detectorId,
                tick: tick,
                timestamp: holdStart
            )
            openSet = DetectionSetContext(
                enterEventId: event.id,
                startedAt: holdStart,
                // The hold that justified the enter is inside the backdated set window.
                cableEvidence: tick.timestamp.timeIntervalSince(holdStart)
            )
            return event
        case .exitRide:
            return endSet(
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick,
                endedAt: tick.timestamp
            )
        case .exitRideOffCable:
            // Riding ended where the rider dropped below cable speed, not where they stopped.
            let holdStart = holds.duration(.offCable, at: tick.timestamp).map {
                tick.timestamp.addingTimeInterval(-$0)
            } ?? tick.timestamp
            var reason = signal.reason
            if holdStart != tick.timestamp {
                reason += " backfill_from=\(fmt(holdStart.timeIntervalSince1970))s"
            }
            return endSet(
                reason: reason,
                detectorId: signal.detectorId,
                tick: tick,
                endedAt: holdStart
            )
        case .enterUnsure:
            return transition(
                to: DetectionCodes.unsure,
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick
            )
        case .unsureTimeout:
            return endSet(
                reason: signal.reason,
                detectorId: signal.detectorId,
                tick: tick,
                endedAt: tick.timestamp
            )
        }
    }

    /// Close the open set, or revoke it when it never became one. A revocation is an ordinary
    /// `inactive` line that supersedes the `ride_enter` it replaces, so `effectiveEvents` drops
    /// the enter and the set never reaches stats. No new detection code, no schema change.
    private mutating func endSet(
        reason: String,
        detectorId: String,
        tick: DetectionTick,
        endedAt: Date
    ) -> DetectionEvent {
        let set = openSet
        openSet = nil
        guard
            let set,
            let verdict = failedStartRule.evaluate(
                set: set,
                endedAt: endedAt,
                thresholds: thresholds
            )
        else {
            return transition(
                to: DetectionCodes.inactive,
                reason: reason,
                detectorId: detectorId,
                tick: tick,
                timestamp: endedAt
            )
        }
        currentCode = DetectionCodes.inactive
        lastConfidentCode = DetectionCodes.inactive
        unsureEnteredAt = nil
        unsureEventId = nil
        holds.clear()
        return DetectionEvent(
            code: DetectionCodes.inactive,
            timestamp: set.startedAt,
            reason: "\(verdict) via=\(reason)",
            detectorId: FailedStartRule.id,
            speedMps: tick.speedMps,
            horizontalAccuracy: tick.horizontalAccuracy,
            waterSubmersionState: tick.waterSubmersionState,
            motionActivity: tick.motionActivity,
            supersedesId: set.enterEventId
        )
    }

    private mutating func transition(
        to code: String,
        reason: String,
        detectorId: String,
        tick: DetectionTick,
        timestamp: Date? = nil
    ) -> DetectionEvent {
        let eventTimestamp = timestamp ?? tick.timestamp
        currentCode = code
        if DetectionCodes.isConfident(code) {
            lastConfidentCode = code
            unsureEnteredAt = nil
            unsureEventId = nil
        } else if code == DetectionCodes.unsure {
            unsureEnteredAt = eventTimestamp
        }
        holds.clear()
        let event = DetectionEvent(
            code: code,
            timestamp: eventTimestamp,
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
        timestamp: Date? = nil,
        supersedesId: String?
    ) -> DetectionEvent {
        currentCode = code
        if DetectionCodes.isConfident(code) {
            lastConfidentCode = code
        }
        if code == DetectionCodes.inactive {
            openSet = nil
        }
        unsureEnteredAt = nil
        unsureEventId = nil
        holds.clear()
        return DetectionEvent(
            code: code,
            timestamp: timestamp ?? tick.timestamp,
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
