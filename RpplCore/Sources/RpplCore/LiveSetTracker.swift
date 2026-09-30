import Foundation

/// Live set counters for Watch UI during an active session.
public struct LiveSetTracker: Sendable {
    public private(set) var setCount = 0
    public private(set) var isSetOngoing = false
    public private(set) var currentSetMeters = 0.0
    public private(set) var lastSetMeters = 0.0
    /// Duration of the most recently finished set; `0` until the first set ends.
    public private(set) var lastSetDuration: TimeInterval = 0
    /// Laps of the most recently finished set; `0` until the first set ends.
    public private(set) var lastSetLapCount = 0
    /// True after at least one set has finished (including zero-meter sets).
    public private(set) var didCompleteSet = false
    /// Sum of finished set meters plus current set (set-gated session distance).
    public private(set) var sessionSetMeters = 0.0
    /// Sum of finished set durations (includes a set closed at session stop).
    public private(set) var sessionRidingDuration: TimeInterval = 0
    public private(set) var currentSpeedKmh: Double?
    /// Cable (line) speed estimated from every finished set so far, km/h rounded to 0.5. What the
    /// Watch shows while inactive; the rider's live GPS speed at the dock says nothing about it.
    public private(set) var cableSpeedKmh: Double?
    /// Crossing-based laps for the current set (0 while inactive after finish until next enter).
    public var currentSetLapCount: Int { lapTracker.lapCount }

    private var trackedCode = DetectionCodes.inactive
    private var trackedLastConfident = DetectionCodes.inactive
    private var previousLocation: LocationSample?
    private var finishedSetMeters = 0.0
    private var setStartedAt: Date?
    private var setEnterEventId: String?
    private var unsureStartedAt: Date?
    private var unsureEventId: String?
    private let maxHorizontalAccuracyM: Double
    private var lapTracker: LapSetTracker
    /// Usable riding speeds (km/h) feeding `cableSpeedKmh`.
    private var ridingSpeedsKmh: [Double] = []

    public init(
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM,
        lapThresholds: LapThresholds = .default
    ) {
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var thresholds = lapThresholds
        thresholds.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var laps = LapSetTracker(thresholds: thresholds)
        laps.noteInactive()
        self.lapTracker = laps
    }

    public mutating func reset() {
        setCount = 0
        isSetOngoing = false
        currentSetMeters = 0
        lastSetMeters = 0
        lastSetDuration = 0
        lastSetLapCount = 0
        didCompleteSet = false
        sessionSetMeters = 0
        sessionRidingDuration = 0
        finishedSetMeters = 0
        currentSpeedKmh = nil
        cableSpeedKmh = nil
        ridingSpeedsKmh.removeAll()
        trackedCode = DetectionCodes.inactive
        trackedLastConfident = DetectionCodes.inactive
        previousLocation = nil
        setStartedAt = nil
        setEnterEventId = nil
        unsureStartedAt = nil
        unsureEventId = nil
        lapTracker.reset()
        // Session starts inactive so the first dock→riding may score laps.
        lapTracker.noteInactive()
    }

    /// Call after each detection engine tick (with zero or more events).
    public mutating func update(
        currentCode: String,
        lastConfident: String,
        events: [DetectionEvent]
    ) {
        for event in events {
            let code = DetectionCodes.normalize(event.code)
            if code == DetectionCodes.unsure {
                if unsureStartedAt == nil {
                    unsureStartedAt = event.timestamp
                    unsureEventId = event.id
                }
                trackedCode = DetectionCodes.unsure
                continue
            }
            guard DetectionCodes.isConfident(code) else { continue }
            let wasRiding = Self.attributesAsRiding(
                code: trackedCode,
                lastConfident: trackedLastConfident
            )
            let nowRiding = code == DetectionCodes.riding
            if nowRiding, !wasRiding {
                setCount += 1
                currentSetMeters = 0
                isSetOngoing = true
                setStartedAt = event.timestamp
                setEnterEventId = event.id
            } else if event.supersedesId != nil, event.supersedesId == setEnterEventId {
                // Engine revoked its own enter (failed start): the set never happened.
                revokeCurrentSet()
            } else if !nowRiding, wasRiding {
                finishCurrentSet(at: setEnd(for: event))
            }
            unsureStartedAt = nil
            unsureEventId = nil
            trackedCode = code
            trackedLastConfident = code
        }

        if events.isEmpty || events.allSatisfy({ DetectionCodes.normalize($0.code) == DetectionCodes.unsure }) {
            trackedCode = DetectionCodes.normalize(currentCode)
        }
        trackedLastConfident = DetectionCodes.normalize(lastConfident)
        isSetOngoing = Self.attributesAsRiding(code: currentCode, lastConfident: lastConfident)
        lapTracker.updateRiding(isSetOngoing)
        if trackedCode != DetectionCodes.riding {
            currentSpeedKmh = nil
        }
        refreshSessionMeters()
    }

    /// Replay buffered GPS fixes that fall inside a backdated set-enter window.
    public mutating func replayLocationsForSetEnter(_ samples: [LocationSample], from holdStart: Date) {
        guard isSetOngoing else { return }
        let ordered = samples
            .filter { $0.timestamp >= holdStart }
            .sorted { $0.timestamp < $1.timestamp }
        guard !ordered.isEmpty else { return }
        previousLocation = nil
        for sample in ordered {
            addLocation(sample)
        }
    }

    /// Add distance and speed from a new GPS fix.
    public mutating func addLocation(_ sample: LocationSample) {
        let attributedRiding = Self.attributesAsRiding(
            code: trackedCode,
            lastConfident: trackedLastConfident
        )
        if attributedRiding {
            lapTracker.addLocation(sample)
        }

        // Meters and display speed only while confidently riding — not during unsure gaps.
        let accrue = trackedCode == DetectionCodes.riding
        if accrue, let speed = sample.speed, speed >= 0 {
            currentSpeedKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: speed)
            if sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxHorizontalAccuracyM {
                ridingSpeedsKmh.append(SpeedUnits.kilometersPerHour(fromMetersPerSecond: speed))
            }
        }

        guard accrue else {
            previousLocation = sample
            return
        }

        if let from = previousLocation,
           GeoDistance.acceptsStep(from: from, to: sample, maxHorizontalAccuracyM: maxHorizontalAccuracyM) {
            currentSetMeters += GeoDistance.meters(
                fromLat: from.latitude,
                fromLon: from.longitude,
                toLat: sample.latitude,
                toLon: sample.longitude
            )
            refreshSessionMeters()
        }
        previousLocation = sample
    }

    /// Close an open set at session stop.
    public mutating func closeOpenSet(at date: Date = Date()) {
        if isSetOngoing {
            finishCurrentSet(at: unsureStartedAt ?? date)
        }
    }

    /// `SessionStatsBuilder` drops an `unsure` gap from the set window unless a lookback
    /// superseded that line. Mirror it so the stop screen and the logbook agree.
    private func setEnd(for event: DetectionEvent) -> Date {
        guard let unsureStartedAt, event.supersedesId != unsureEventId else {
            return event.timestamp
        }
        return unsureStartedAt
    }

    /// Undo a set the engine took back. Leaves the previous set's frozen values alone: the Watch
    /// keeps showing the last real set rather than a set that turned out not to exist.
    private mutating func revokeCurrentSet() {
        setCount = max(0, setCount - 1)
        currentSetMeters = 0
        isSetOngoing = false
        currentSpeedKmh = nil
        setStartedAt = nil
        setEnterEventId = nil
        if lapTracker.isSetActive {
            lapTracker.endSet()
        }
        refreshSessionMeters()
    }

    private mutating func finishCurrentSet(at date: Date) {
        setEnterEventId = nil
        lastSetMeters = currentSetMeters
        if let started = setStartedAt {
            lastSetDuration = max(0, date.timeIntervalSince(started))
        } else {
            lastSetDuration = 0
        }
        if lapTracker.isSetActive {
            lapTracker.endSet()
        }
        lastSetLapCount = lapTracker.lapCount
        didCompleteSet = true
        sessionRidingDuration += lastSetDuration
        finishedSetMeters += currentSetMeters
        currentSetMeters = 0
        isSetOngoing = false
        currentSpeedKmh = nil
        setStartedAt = nil
        refreshCableSpeed()
        refreshSessionMeters()
    }

    /// Mode of riding speeds, same estimator as the logbook. Runs once per finished set.
    private mutating func refreshCableSpeed() {
        guard let estimate = CableSpeedEstimator.estimates(speedsKmh: ridingSpeedsKmh).first else { return }
        cableSpeedKmh = CableSpeedEstimator.roundedToHalfKmh(estimate.speedKmh)
    }

    private mutating func refreshSessionMeters() {
        sessionSetMeters = finishedSetMeters + currentSetMeters
    }

    private static func attributesAsRiding(code: String, lastConfident: String) -> Bool {
        let code = DetectionCodes.normalize(code)
        let lastConfident = DetectionCodes.normalize(lastConfident)
        if code == DetectionCodes.riding { return true }
        if code == DetectionCodes.unsure { return lastConfident == DetectionCodes.riding }
        return false
    }
}
