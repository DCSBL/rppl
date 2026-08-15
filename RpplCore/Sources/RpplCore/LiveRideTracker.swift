import Foundation

/// Live ride counters for Watch UI during an active session.
public struct LiveRideTracker: Sendable {
    public private(set) var rideCount = 0
    public private(set) var isRideOngoing = false
    public private(set) var currentRideMeters = 0.0
    public private(set) var lastRideMeters = 0.0
    /// Duration of the most recently finished ride; `0` until the first ride ends.
    public private(set) var lastRideDuration: TimeInterval = 0
    /// Laps of the most recently finished ride; `0` until the first ride ends.
    public private(set) var lastRideLapCount = 0
    /// True after at least one ride has finished (including zero-meter rides).
    public private(set) var didCompleteRide = false
    /// Sum of finished ride meters plus current ride (ride-gated session distance).
    public private(set) var sessionRideMeters = 0.0
    public private(set) var currentSpeedKmh: Double?
    /// Crossing-based laps for the current ride (0 while paused after finish until next enter).
    public var currentRideLapCount: Int { lapTracker.lapCount }

    private var trackedCode = DetectionCodes.paused
    private var trackedLastConfident = DetectionCodes.paused
    private var previousLocation: LocationSample?
    private var finishedRideMeters = 0.0
    private var rideStartedAt: Date?
    private let maxHorizontalAccuracyM: Double
    private var lapTracker: LapRideTracker

    public init(
        maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM,
        lapThresholds: LapThresholds = .default
    ) {
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var thresholds = lapThresholds
        thresholds.maxHorizontalAccuracyM = maxHorizontalAccuracyM
        var laps = LapRideTracker(thresholds: thresholds)
        laps.notePaused()
        self.lapTracker = laps
    }

    public mutating func reset() {
        rideCount = 0
        isRideOngoing = false
        currentRideMeters = 0
        lastRideMeters = 0
        lastRideDuration = 0
        lastRideLapCount = 0
        didCompleteRide = false
        sessionRideMeters = 0
        finishedRideMeters = 0
        currentSpeedKmh = nil
        trackedCode = DetectionCodes.paused
        trackedLastConfident = DetectionCodes.paused
        previousLocation = nil
        rideStartedAt = nil
        lapTracker.reset()
        // Session starts paused so the first dock→ride may score laps.
        lapTracker.notePaused()
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
            let nowRiding = event.code == DetectionCodes.riding
            if nowRiding, !wasRiding {
                rideCount += 1
                currentRideMeters = 0
                isRideOngoing = true
                rideStartedAt = event.timestamp
            } else if !nowRiding, wasRiding {
                finishCurrentRide(at: event.timestamp)
            }
            trackedCode = event.code
            trackedLastConfident = event.code
        }

        for event in events where event.code == DetectionCodes.unsure {
            trackedCode = DetectionCodes.unsure
        }

        if events.isEmpty || events.allSatisfy({ $0.code == DetectionCodes.unsure }) {
            trackedCode = currentCode
        }
        trackedLastConfident = lastConfident
        isRideOngoing = Self.attributesAsRiding(code: currentCode, lastConfident: lastConfident)
        lapTracker.updateRiding(isRideOngoing)
        if trackedCode != DetectionCodes.riding {
            currentSpeedKmh = nil
        }
        refreshSessionMeters()
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
        if lapTracker.isRideActive {
            lapTracker.endRide()
        }
        lastRideLapCount = lapTracker.lapCount
        didCompleteRide = true
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
        if code == DetectionCodes.riding { return true }
        if code == DetectionCodes.unsure { return lastConfident == DetectionCodes.riding }
        return false
    }
}
