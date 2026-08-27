import Foundation

/// Crossing-based set counter for one ride (incremental; offline batch = same API).
///
/// Leave start beyond `exitRadiusM`, travel ≥ `minPathBeforeCrossingM`, re-enter
/// `startSafeRadiusM` → +1. Bad GPS ignored. Scoring only after a prior pause
/// (mid-ride session start skipped until pause→riding).
public struct SetRideTracker: Sendable {
    public private(set) var setCount = 0
    public private(set) var isRideActive = false

    private enum ZoneState: Equatable {
        case idle
        case awaitingAnchor
        case atStart
        case outside
    }

    private var thresholds: SetThresholds
    private var zoneState: ZoneState = .idle
    private var hasSeenInactive = false
    private var scoringThisRide = false
    private var startLatitude: Double?
    private var startLongitude: Double?
    private var pathSinceLeaveM = 0.0
    private var previousLocation: LocationSample?

    public init(thresholds: SetThresholds = .default) {
        self.thresholds = thresholds
    }

    public mutating func reset() {
        setCount = 0
        isRideActive = false
        zoneState = .idle
        hasSeenInactive = false
        scoringThisRide = false
        startLatitude = nil
        startLongitude = nil
        pathSinceLeaveM = 0
        previousLocation = nil
    }

    /// Mark dock/pause so the next ride may score sets.
    public mutating func noteInactive() {
        if isRideActive {
            endRide()
        }
        hasSeenInactive = true
    }

    /// Open a ride. Sets score only if `noteInactive()` was seen earlier.
    public mutating func beginRide() {
        if isRideActive {
            endRide()
        }
        setCount = 0
        isRideActive = true
        scoringThisRide = hasSeenInactive
        zoneState = scoringThisRide ? .awaitingAnchor : .idle
        startLatitude = nil
        startLongitude = nil
        pathSinceLeaveM = 0
        previousLocation = nil
    }

    /// Freeze set state for this ride (fall / pause / session end).
    public mutating func endRide() {
        isRideActive = false
        scoringThisRide = false
        zoneState = .idle
        previousLocation = nil
        // Completing a ride implies pause at/after exit — unlock scoring for later rides.
        hasSeenInactive = true
    }

    /// Drive enter/exit from attributed riding (incl. unsure→riding on live).
    public mutating func updateRiding(_ riding: Bool) {
        if riding, !isRideActive {
            beginRide()
        } else if !riding, isRideActive {
            endRide()
        }
    }

    /// Feed a GPS sample. Unusable / rejected steps do not move zone or path.
    public mutating func addLocation(_ sample: LocationSample) {
        guard isRideActive, scoringThisRide else { return }

        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= thresholds.maxHorizontalAccuracyM
        else {
            return
        }

        if zoneState == .awaitingAnchor {
            startLatitude = sample.latitude
            startLongitude = sample.longitude
            zoneState = .atStart
            previousLocation = sample
            return
        }

        guard let startLat = startLatitude, let startLon = startLongitude else { return }

        let distanceFromStart = GeoDistance.meters(
            fromLat: startLat,
            fromLon: startLon,
            toLat: sample.latitude,
            toLon: sample.longitude
        )

        if let from = previousLocation,
           GeoDistance.acceptsStep(
            from: from,
            to: sample,
            maxHorizontalAccuracyM: thresholds.maxHorizontalAccuracyM
           ) {
            let step = GeoDistance.meters(
                fromLat: from.latitude,
                fromLon: from.longitude,
                toLat: sample.latitude,
                toLon: sample.longitude
            )
            if zoneState == .outside {
                pathSinceLeaveM += step
            }
            previousLocation = sample
        } else if previousLocation == nil {
            previousLocation = sample
        } else {
            // Rejected step: no zone teleport, no path credit, keep previous.
            return
        }

        switch zoneState {
        case .atStart:
            if distanceFromStart > thresholds.exitRadiusM {
                zoneState = .outside
                pathSinceLeaveM = 0
            }
        case .outside:
            if distanceFromStart <= thresholds.startSafeRadiusM,
               pathSinceLeaveM >= thresholds.minPathBeforeCrossingM {
                setCount += 1
                zoneState = .atStart
                pathSinceLeaveM = 0
            }
        case .idle, .awaitingAnchor:
            break
        }
    }
}
