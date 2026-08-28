import Foundation

/// Crossing-based lap counter for one set (incremental; offline batch = same API).
///
/// Leave start beyond `exitRadiusM`, travel ≥ `minPathBeforeCrossingM`, re-enter
/// `startSafeRadiusM` → +1. Bad GPS ignored. Scoring only after a prior pause
/// (mid-set session start skipped until pause→riding).
public struct LapSetTracker: Sendable {
    public private(set) var lapCount = 0
    public private(set) var isSetActive = false

    private enum ZoneState: Equatable {
        case idle
        case awaitingAnchor
        case atStart
        case outside
    }

    private var thresholds: LapThresholds
    private var zoneState: ZoneState = .idle
    private var hasSeenInactive = false
    private var scoringThisSet = false
    private var startLatitude: Double?
    private var startLongitude: Double?
    private var pathSinceLeaveM = 0.0
    private var previousLocation: LocationSample?

    public init(thresholds: LapThresholds = .default) {
        self.thresholds = thresholds
    }

    public mutating func reset() {
        lapCount = 0
        isSetActive = false
        zoneState = .idle
        hasSeenInactive = false
        scoringThisSet = false
        startLatitude = nil
        startLongitude = nil
        pathSinceLeaveM = 0
        previousLocation = nil
    }

    /// Mark dock/pause so the next set may score laps.
    public mutating func noteInactive() {
        if isSetActive {
            endSet()
        }
        hasSeenInactive = true
    }

    /// Open a set. Laps score only if `noteInactive()` was seen earlier.
    public mutating func beginSet() {
        if isSetActive {
            endSet()
        }
        lapCount = 0
        isSetActive = true
        scoringThisSet = hasSeenInactive
        zoneState = scoringThisSet ? .awaitingAnchor : .idle
        startLatitude = nil
        startLongitude = nil
        pathSinceLeaveM = 0
        previousLocation = nil
    }

    /// Freeze lap state for this set (fall / pause / session end).
    public mutating func endSet() {
        isSetActive = false
        scoringThisSet = false
        zoneState = .idle
        previousLocation = nil
        // Completing a set implies pause at/after exit — unlock scoring for later sets.
        hasSeenInactive = true
    }

    /// Drive enter/exit from attributed riding (incl. unsure→riding on live).
    public mutating func updateRiding(_ riding: Bool) {
        if riding, !isSetActive {
            beginSet()
        } else if !riding, isSetActive {
            endSet()
        }
    }

    /// Feed a GPS sample. Unusable / rejected steps do not move zone or path.
    public mutating func addLocation(_ sample: LocationSample) {
        guard isSetActive, scoringThisSet else { return }

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
                lapCount += 1
                zoneState = .atStart
                pathSinceLeaveM = 0
            }
        case .idle, .awaitingAnchor:
            break
        }
    }
}
