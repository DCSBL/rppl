import Foundation

/// Live ride counters for Watch UI during an active session.
public struct LiveRideTracker: Sendable {
    public private(set) var rideCount = 0
    public private(set) var isRideOngoing = false
    public private(set) var currentRideMeters = 0.0
    public private(set) var lastRideMeters = 0.0
    /// Duration of the most recently finished ride; `0` until the first ride ends.
    public private(set) var lastRideDuration: TimeInterval = 0
    /// Sets of the most recently finished ride; `0` until the first ride ends.
    public private(set) var lastRideSetCount = 0
    /// True after at least one ride has finished (including zero-meter rides).
    public private(set) var didCompleteRide = false
    /// Sum of finished ride meters plus current ride (ride-gated session distance).
    public private(set) var sessionRideMeters = 0.0
    /// Sum of finished ride durations (includes a ride closed at session stop).
    public private(set) var sessionRidingDuration: TimeInterval = 0
    public private(set) var currentSpeedKmh: Double?
    /// Crossing-based sets for the current ride (0 while inactive after finish until next enter).
    public var currentRideSetCount: Int { setTracker.setCount }

    private var trackedCode = DetectionCodes.inactive
    private var trackedLastConfident = DetectionCodes.inactive
    private var previousLocation: LocationSample?
    private var finishedRideMeters = 0.0
    private var rideStartedAt: Date?
    private let maxHorizontalAccuracyM: Double
    private var setTracker: SetRideTracker

    public init(
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM,
        setThresholds: SetThresholds = .default
    ) {
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var thresholds = setThresholds
        thresholds.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var sets = SetRideTracker(thresholds: thresholds)
        sets.noteInactive()
        self.setTracker = sets
    }

    public mutating func reset() {
        rideCount = 0
        isRideOngoing = false
        currentRideMeters = 0
        lastRideMeters = 0
        lastRideDuration = 0
        lastRideSetCount = 0
        didCompleteRide = false
        sessionRideMeters = 0
        sessionRidingDuration = 0
        finishedRideMeters = 0
        currentSpeedKmh = nil
        trackedCode = DetectionCodes.inactive
        trackedLastConfident = DetectionCodes.inactive
        previousLocation = nil
        rideStartedAt = nil
        setTracker.reset()
        // Session starts inactive so the first dock→ride may score sets.
        setTracker.noteInactive()
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
                rideCount += 1
                currentRideMeters = 0
                isRideOngoing = true
                rideStartedAt = event.timestamp
            } else if !nowRiding, wasRiding {
                finishCurrentRide(at: event.timestamp)
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
        isRideOngoing = Self.attributesAsRiding(code: currentCode, lastConfident: lastConfident)
        setTracker.updateRiding(isRideOngoing)
        if trackedCode != DetectionCodes.riding {
            currentSpeedKmh = nil
        }
        refreshSessionMeters()
    }

    /// Replay buffered GPS fixes that fall inside a backdated ride-enter window.
    public mutating func replayLocationsForRideEnter(_ samples: [LocationSample], from holdStart: Date) {
        guard isRideOngoing else { return }
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
            setTracker.addLocation(sample)
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
            currentRideMeters += GeoDistance.meters(
                fromLat: from.latitude,
                fromLon: from.longitude,
                toLat: sample.latitude,
                toLon: sample.longitude
            )
            refreshSessionMeters()
        }
        previousLocation = sample
    }

    /// Close an open ride at session stop.
    public mutating func closeOpenRide(at date: Date = Date()) {
        if isRideOngoing {
            finishCurrentRide(at: date)
        }
    }

    private mutating func finishCurrentRide(at date: Date) {
        lastRideMeters = currentRideMeters
        if let started = rideStartedAt {
            lastRideDuration = max(0, date.timeIntervalSince(started))
        } else {
            lastRideDuration = 0
        }
        if setTracker.isRideActive {
            setTracker.endRide()
        }
        lastRideSetCount = setTracker.setCount
        didCompleteRide = true
        sessionRidingDuration += lastRideDuration
        finishedRideMeters += currentRideMeters
        currentRideMeters = 0
        isRideOngoing = false
        currentSpeedKmh = nil
        rideStartedAt = nil
        refreshSessionMeters()
    }

    private mutating func refreshSessionMeters() {
        sessionRideMeters = finishedRideMeters + currentRideMeters
    }

    private static func attributesAsRiding(code: String, lastConfident: String) -> Bool {
        let code = DetectionCodes.normalize(code)
        let lastConfident = DetectionCodes.normalize(lastConfident)
        if code == DetectionCodes.riding { return true }
        if code == DetectionCodes.unsure { return lastConfident == DetectionCodes.riding }
        return false
    }
}
