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
            processDetectionHeartbeat()
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
        liveSetTracker.update(
            currentCode: code,
            lastConfident: code,
            events: [event]
        )
        applySensorSamplingMode(dense: SensorSamplingMode.isDense(currentCode: code))
        persistDetection(event)
        WakeLog.debug(.ui, "sim detection=\(code)")
    }

    /// Start-workout Action Button entry. Busy (recording, starting, or still saving the last
    /// session) → ignored. Otherwise a fresh session starts, also from the end summary.
    func handleStartWorkoutIntent() async {
        if startGateDecision() == .ignoreBusy {
            WakeLog.debug(.intent, "StartCableParkSessionIntent: busy \(busyStateDescription) — ignored")
            return
        }
        let code = ActivityCodes.resolvedStartCode()
        WakeLog.debug(
            .intent,
            "StartCableParkSessionIntent: starting session activity=\(code) fromSummary=\(endedSessionSummary != nil)"
        )
        await startSession(activityCode: code)
    }

    func startGateDecision() -> SessionStartGate.Decision {
        // An undecided permission can still show its system sheet; `startSession` prompts for it
        // and re-checks, so only decided (denied/unavailable) blockers stop the start here.
        let states = permissionStates
        let blocker = WatchPermissionOrder.startBlocker(states: states)
            .flatMap { states[$0] == .notDetermined ? nil : $0 }
        return SessionStartGate.decide(
            isRunning: isRunning,
            isStarting: isStarting,
            isStopping: isStopping,
            isFinalizing: isFinalizing,
            permissionBlocker: blocker
        )
    }

    var busyStateDescription: String {
        "running=\(isRunning) starting=\(isStarting) stopping=\(isStopping) finalizing=\(isFinalizing)"
    }

    func logSessionStartDetection() {
        let event = detectionEngine.makeSessionStartEvent(at: Date())
        detectionCode = event.code
        lastConfidentCode = detectionEngine.lastConfidentCode
        persistDetection(event)
    }

    /// No new fix: 1 Hz timer or a water-state change. Keeps the gap / timeout clocks running so
    /// detection does not stall while GPS is silent, without passing an old speed off as current.
    func processDetectionHeartbeat(at timestamp: Date = Date()) {
        processDetection(
            tick: .heartbeat(
                at: timestamp,
                waterSubmersionState: latestWaterState,
                motionActivity: latestActivity
            )
        )
    }

    /// New GPS fix — the only tick that carries speed evidence.
    func processDetectionFix(_ location: CLLocation) {
        processDetection(
            tick: DetectionTick(
                timestamp: location.timestamp,
                speedMps: location.speed >= 0 ? location.speed : nil,
                horizontalAccuracy: location.horizontalAccuracy,
                waterSubmersionState: latestWaterState,
                motionActivity: latestActivity
            )
        )
    }

    private func processDetection(tick: DetectionTick) {
        guard isRunning, !isProductPaused else { return }
        guard detectionSimulationMode == .detected else { return }
        let events = detectionEngine.process(tick)
        filterRejectionReason = detectionEngine.lastFilterRejection
        detectionCode = detectionEngine.currentCode
        lastConfidentCode = detectionEngine.lastConfidentCode
        liveSetTracker.update(
            currentCode: detectionCode,
            lastConfident: lastConfidentCode,
            events: events
        )
        for event in events where event.code == DetectionCodes.riding && event.detectorId == "ride_enter" {
            replayLocationRingForRideEnter(holdStart: event.timestamp)
        }
        applySensorSamplingMode(dense: SensorSamplingMode.isDense(currentCode: detectionCode))
        guard !events.isEmpty else { return }
        for event in events {
            persistDetection(event)
        }
    }

    func processLocationSample(_ sample: LocationSample) {
        liveSetTracker.addLocation(sample)
        accumulateRideDistanceForHealthKit()
        trackRidePeakSpeed(sample)
    }

    func trackRidePeakSpeed(_ sample: LocationSample) {
        guard liveSetTracker.isSetOngoing else { return }
        let tick = DetectionTick(
            timestamp: sample.timestamp,
            speedMps: sample.speed,
            horizontalAccuracy: sample.horizontalAccuracy
        )
        let outcome = hkGpsFilter.evaluate(
            tick,
            previousUsableSpeedMps: hkPreviousUsableSpeedMps,
            previousUsableAt: hkPreviousUsableAt,
            pendingJumpSpeedMps: hkPendingJumpSpeedMps
        )
        hkPendingJumpSpeedMps = outcome.jumpCandidateSpeedMps
        guard let usable = outcome.usableSpeedMps else { return }
        hkPreviousUsableSpeedMps = usable
        hkPreviousUsableAt = sample.timestamp
        hkPeakSpeedMps = max(hkPeakSpeedMps, usable)
    }

    func accumulateRideDistanceForHealthKit() {
        guard liveSetTracker.isSetOngoing else { return }
        let current = liveSetTracker.currentSetMeters
        if current > hkRideDistanceAnchorMeters {
            hkRideDistanceMeters += current - hkRideDistanceAnchorMeters
            hkRideDistanceAnchorMeters = current
        }
    }

    func persistDetection(_ event: DetectionEvent) {
        // Live behavior (HealthKit interval, haptic, set timers) must not depend on the disk: a
        // failed write used to skip all of it. The event is queued and written as soon as it can be.
        handleDetectionTransition(event)
        pendingDetections.enqueue(event)
        flushPendingDetections()
    }

    /// Writes queued detection events oldest first. Called per event and from every buffer flush,
    /// so an event that failed once lands in `detections.jsonl` as soon as writing works again.
    func flushPendingDetections() {
        guard !pendingDetections.isEmpty else { return }
        guard let store, let manifest else {
            WakeLog.error(.detection, "appendDetection skipped — no store/manifest")
            return
        }
        let result = pendingDetections.drain { event in
            try store.appendDetection(event, sessionId: manifest.sessionId)
            WakeLog.debug(.detection, "appended code=\(event.code) reason=\(event.reason)")
        }
        detectionCount += result.written
        if let error = result.error {
            errorText = String(localized: "Detection: \(error.localizedDescription)")
            WakeLog.error(
                .detection,
                "appendDetection: \(error.localizedDescription) — \(pendingDetections.count) kept for retry"
            )
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
                hkPreviousUsableAt = nil
                hkPendingJumpSpeedMps = nil
            }
            if let previousSegmentStart = currentSegmentStartedAt {
                let completedSegmentDuration = event.timestamp.timeIntervalSince(previousSegmentStart)
                if lastPersistedConfidentCode == DetectionCodes.riding {
                    cumulativeRidingDuration += completedSegmentDuration
                } else if lastPersistedConfidentCode == DetectionCodes.inactive {
                    cumulativeInactiveDuration += completedSegmentDuration
                }
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

    /// Keep HK session running. Fitness intervals = set then dock-wait activities (no rest labels).
}
