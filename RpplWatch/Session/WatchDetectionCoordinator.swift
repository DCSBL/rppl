import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore

// MARK: - Detection
extension WatchSessionController {
    func cycleDetectionSimulation() {
        guard isRunning, !isProductPaused else { return }
        let next: DetectionSimulationMode
        switch detectionSimulationMode {
        case .detected: next = .inactive
        case .inactive: next = .ride
        case .ride: next = .detected
        }
        applyDetectionSimulation(next)
    }

    func applyDetectionSimulation(_ mode: DetectionSimulationMode) {
        detectionSimulationMode = mode
        switch mode {
        case .detected:
            WakeLog.debug(.ui, "sim detection=detected (live engine)")
            WKInterfaceDevice.current().play(.click)
            processDetectionTick()
        case .inactive:
            forceSimulatedDetection(code: DetectionCodes.inactive)
            playRideHaptic(for: DetectionCodes.inactive)
        case .ride:
            forceSimulatedDetection(code: DetectionCodes.riding)
            playRideHaptic(for: DetectionCodes.riding)
        }
    }

    func playRideHaptic(for code: String) {
        switch code {
        case DetectionCodes.riding:
            WKInterfaceDevice.current().play(.success)
        case DetectionCodes.inactive:
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
    }

    func forceSimulatedDetection(code: String) {
        let event = DetectionEvent(
            code: code,
            timestamp: Date(),
            reason: "debug_sim",
            detectorId: "debug_sim"
        )
        detectionCode = code
        lastConfidentCode = code
        filterRejectionReason = nil
        liveRideTracker.update(
            currentCode: code,
            lastConfident: code,
            events: [event]
        )
        persistDetection(event)
        WakeLog.debug(.ui, "sim detection=\(code)")
    }

    /// Start-workout Action Button entry: start session, or no-op if already recording.
    func handleStartWorkoutIntent() async {
        if isRunning || isStopping || isStarting {
            WakeLog.debug(
                .intent,
                "StartCableParkSessionIntent: busy running=\(isRunning) stopping=\(isStopping) starting=\(isStarting) — no-op"
            )
            return
        }
        let code = ActivityCodes.resolvedStartCode()
        WakeLog.debug(.intent, "StartCableParkSessionIntent: starting session activity=\(code)")
        await startSession(activityCode: code)
    }

    func logSessionStartDetection() {
        let event = detectionEngine.makeSessionStartEvent(at: Date())
        detectionCode = event.code
        lastConfidentCode = detectionEngine.lastConfidentCode
        persistDetection(event)
    }

    func processDetectionTick(timestamp: Date = Date()) {
        guard isRunning, !isProductPaused else { return }
        guard detectionSimulationMode == .detected else { return }
        let speed: Double?
        if let loc = latestLocation, loc.speed >= 0 {
            speed = loc.speed
        } else {
            speed = nil
        }
        let tick = DetectionTick(
            timestamp: timestamp,
            speedMps: speed,
            horizontalAccuracy: latestLocation?.horizontalAccuracy,
            waterSubmersionState: latestWaterState,
            motionActivity: latestActivity
        )
        let events = detectionEngine.process(tick)
        filterRejectionReason = detectionEngine.lastFilterRejection
        detectionCode = detectionEngine.currentCode
        lastConfidentCode = detectionEngine.lastConfidentCode
        liveRideTracker.update(
            currentCode: detectionCode,
            lastConfident: lastConfidentCode,
            events: events
        )
        for event in events where event.code == DetectionCodes.riding && event.detectorId == "ride_enter" {
            replayLocationRingForRideEnter(holdStart: event.timestamp)
        }
        guard !events.isEmpty else { return }
        for event in events {
            persistDetection(event)
        }
    }

    func processLocationSample(_ sample: LocationSample) {
        liveRideTracker.addLocation(sample)
        accumulateRideDistanceForHealthKit()
        trackRidePeakSpeed(sample)
    }

    func trackRidePeakSpeed(_ sample: LocationSample) {
        guard liveRideTracker.isRideOngoing else { return }
        let tick = DetectionTick(
            timestamp: sample.timestamp,
            speedMps: sample.speed,
            horizontalAccuracy: sample.horizontalAccuracy
        )
        let outcome = hkGpsFilter.evaluate(tick, previousUsableSpeedMps: hkPreviousUsableSpeedMps)
        guard let usable = outcome.usableSpeedMps else { return }
        hkPreviousUsableSpeedMps = usable
        hkPeakSpeedMps = max(hkPeakSpeedMps, usable)
    }

    func accumulateRideDistanceForHealthKit() {
        guard liveRideTracker.isRideOngoing else { return }
        let current = liveRideTracker.currentRideMeters
        if current > hkRideDistanceAnchorMeters {
            hkRideDistanceMeters += current - hkRideDistanceAnchorMeters
            hkRideDistanceAnchorMeters = current
        }
    }

    func persistDetection(_ event: DetectionEvent) {
        guard let store, let manifest else {
            WakeLog.error(.detection, "appendDetection skipped — no store/manifest")
            return
        }
        do {
            try store.appendDetection(event, sessionId: manifest.sessionId)
            detectionCount += 1
            refreshStoredByteSize()
            WakeLog.debug(
                .detection,
                "appended code=\(event.code) reason=\(event.reason) count=\(detectionCount)"
            )
            handleDetectionTransition(event)
        } catch {
            errorText = String(localized: "Detection: \(error.localizedDescription)")
            WakeLog.error(.detection, "appendDetection: \(error.localizedDescription)")
        }
    }

    func handleDetectionTransition(_ event: DetectionEvent) {
        guard DetectionCodes.isConfident(event.code) else { return }
        if event.code != lastPersistedConfidentCode {
            if lastPersistedConfidentCode == DetectionCodes.riding {
                accumulateRideDistanceForHealthKit()
                recordFinishedHkRide(endedAt: event.timestamp)
                hkRideDistanceAnchorMeters = 0
            }
            if event.code == DetectionCodes.riding {
                hkRideStartedAt = event.timestamp
                hkPreviousUsableSpeedMps = nil
            }
            currentSegmentStartedAt = event.timestamp
            lastPersistedConfidentCode = event.code
            syncWorkoutForDetection(code: event.code, at: event.timestamp)
            refreshSegmentDurations()
            // Debug sim plays haptics in `applyDetectionSimulation` so every mode ticks.
            if event.detectorId != "debug_sim" {
                playRideHaptic(for: event.code)
            }
        }
    }

    /// Keep HK session running. Fitness intervals = ride then dock-wait activities (no rest labels).
}
