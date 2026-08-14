import Foundation

/// Live ride counters for Watch UI during an active session.
public struct LiveRideTracker: Sendable {
    public private(set) var rideCount = 0
    public private(set) var isRideOngoing = false
    public private(set) var currentRideMeters = 0.0
    public private(set) var lastRideMeters = 0.0
    public private(set) var currentSpeedKmh: Double?

    private var trackedCode = DetectionCodes.paused
    private var trackedLastConfident = DetectionCodes.paused
    private var previousLocation: LocationSample?
    private let maxHorizontalAccuracyM: Double

    public init(maxHorizontalAccuracyM: Double = DetectionThresholds.default.maxHorizontalAccuracyM) {
        self.maxHorizontalAccuracyM = maxHorizontalAccuracyM
    }

    public mutating func reset() {
        rideCount = 0
        isRideOngoing = false
        currentRideMeters = 0
        lastRideMeters = 0
        currentSpeedKmh = nil
        trackedCode = DetectionCodes.paused
        trackedLastConfident = DetectionCodes.paused
        previousLocation = nil
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
            } else if !nowRiding, wasRiding {
                finishCurrentRide()
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
        if !isRideOngoing {
            currentSpeedKmh = nil
        }
    }

    /// Add distance and speed from a new GPS fix.
    public mutating func addLocation(_ sample: LocationSample) {
        if isRideOngoing, let speed = sample.speed, speed >= 0 {
            currentSpeedKmh = SpeedUnits.kilometersPerHour(fromMetersPerSecond: speed)
        }

        guard isRideOngoing else {
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
        }
        previousLocation = sample
    }

    /// Close an open ride at session stop.
    public mutating func closeOpenRide() {
        if isRideOngoing {
            finishCurrentRide()
        }
    }

    private mutating func finishCurrentRide() {
        lastRideMeters = currentRideMeters
        currentRideMeters = 0
        isRideOngoing = false
        currentSpeedKmh = nil
    }

    private static func attributesAsRiding(code: String, lastConfident: String) -> Bool {
        if code == DetectionCodes.riding { return true }
        if code == DetectionCodes.unsure { return lastConfident == DetectionCodes.riding }
        return false
    }
}
