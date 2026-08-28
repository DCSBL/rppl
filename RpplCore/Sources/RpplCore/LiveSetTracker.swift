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
    /// Crossing-based laps for the current set (0 while inactive after finish until next enter).
    public var currentSetLapCount: Int { lapTracker.lapCount }

    private var trackedCode = DetectionCodes.inactive
    private var trackedLastConfident = DetectionCodes.inactive
    private var previousLocation: LocationSample?
    private var finishedSetMeters = 0.0
    private var setStartedAt: Date?
    private let maxHorizontalAccuracyM: Double
    private var lapTracker: LapSetTracker

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
        trackedCode = DetectionCodes.inactive
        trackedLastConfident = DetectionCodes.inactive
        previousLocation = nil
        setStartedAt = nil
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
        for event in events where DetectionCodes.isConfident(event.code) {
            let wasRiding = Self.attributesAsRiding(
                code: trackedCode,
                lastConfident: trackedLastConfident
            )
            let code = DetectionCodes.normalize(event.code)
            let nowRiding = code == DetectionCodes.riding
            if nowRiding, !wasRiding {
                setCount += 1
                currentSetMeters = 0
                isSetOngoing = true
                setStartedAt = event.timestamp
            } else if !nowRiding, wasRiding {
                finishCurrentSet(at: event.timestamp)
            }
            trackedCode = code
            trackedLastConfident = code
        }

        for event in events where DetectionCodes.normalize(event.code) == DetectionCodes.unsure {
            trackedCode = DetectionCodes.unsure
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
            finishCurrentSet(at: date)
        }
    }

    private mutating func finishCurrentSet(at date: Date) {
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
        refreshSessionMeters()
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
