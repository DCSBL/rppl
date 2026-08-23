import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore

// MARK: - Lifecycle
extension WatchSessionController {
    func refreshPermissionStatus() {
        let loc = locationManager.authorizationStatus
        locationAuthStatus = Self.locationLabel(loc)
        locationPermission = Self.locationPermissionState(loc)

        if CMMotionActivityManager.isActivityAvailable() {
            switch CMMotionActivityManager.authorizationStatus() {
            case .notDetermined:
                motionPermission = .notDetermined
                motionAvailability = "activity: notDetermined"
            case .restricted, .denied:
                motionPermission = .denied
                motionAvailability = "activity: denied"
            case .authorized:
                motionPermission = .authorized
                motionAvailability = motionManager.isDeviceMotionAvailable
                    ? "deviceMotion available"
                    : "activity authorized"
            @unknown default:
                motionPermission = .notDetermined
                motionAvailability = "activity: unknown"
            }
        } else if motionManager.isDeviceMotionAvailable {
            // No activity auth surface — device motion alone does not prompt; treat ready.
            motionPermission = .authorized
            motionAvailability = "deviceMotion available"
        } else {
            motionPermission = .unavailable
            motionAvailability = "unavailable (skipped)"
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthStatus = String(localized: "Health unavailable")
            healthPermission = .unavailable
            return
        }
        switch healthStore.authorizationStatus(for: workoutType) {
        case .notDetermined:
            healthAuthStatus = String(localized: "workout: notDetermined")
            healthPermission = .notDetermined
        case .sharingDenied:
            healthAuthStatus = String(localized: "workout: denied - enable in Settings › Health")
            healthPermission = .denied
        case .sharingAuthorized:
            healthAuthStatus = String(localized: "workout: authorized")
            healthPermission = .authorized
        @unknown default:
            healthAuthStatus = String(localized: "workout: unknown")
            healthPermission = .notDetermined
        }
    }

    /// Safe to call repeatedly. System may only show the sheet while status is notDetermined.
    func requestPermissions() async {
        WakeLog.debug(.permissions, "requestPermissions begin")
        errorText = nil
        await requestLocationPermission()
        await requestHealthPermission()
        await requestMotionPermission()
        statusText = String(localized: "Permissions updated")
        WakeLog.debug(
            .permissions,
            "status health=\(healthAuthStatus) loc=\(locationAuthStatus) motion=\(motionAvailability)"
        )
    }

    func requestLocationPermission() async {
        errorText = nil
        locationManager.requestWhenInUseAuthorization()
        // Authorization callback updates via delegate; refresh snapshot now too.
        refreshPermissionStatus()
    }

    func requestHealthPermission() async {
        errorText = nil
        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthStatus = String(localized: "Health unavailable")
            healthPermission = .unavailable
            WakeLog.debug(.permissions, "Health unavailable")
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            WakeLog.debug(.permissions, "Health authorization requested OK")
        } catch {
            errorText = String(localized: "Health auth: \(error.localizedDescription)")
            WakeLog.error(.permissions, "Health auth: \(error.localizedDescription)")
        }
        refreshPermissionStatus()
    }

    func requestMotionPermission() async {
        errorText = nil
        guard CMMotionActivityManager.isActivityAvailable() else {
            refreshPermissionStatus()
            return
        }
        if CMMotionActivityManager.authorizationStatus() != .notDetermined {
            refreshPermissionStatus()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let manager = CMMotionActivityManager()
            let now = Date()
            manager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in
                continuation.resume()
            }
        }
        refreshPermissionStatus()
        WakeLog.debug(.permissions, "Motion authorization queried status=\(motionAvailability)")
    }

    static func locationPermissionState(_ status: CLAuthorizationStatus) -> WatchPermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    func startSession(activityCode: String = ActivityCodes.resolvedStartCode()) async {
        endedSessionSummary = nil

        guard !isRunning, !isStopping, !isStarting else {
            WakeLog.debug(
                .session,
                "startSession ignored — running=\(isRunning) stopping=\(isStopping) starting=\(isStarting)"
            )
            return
        }
        let code = activityCode.isEmpty ? ActivityCodes.wakeboard : activityCode
        WakeLog.debug(.session, "startSession begin activity=\(code)")
        errorText = nil
        statusText = String(localized: "Starting…")
        recordingMode = "none"
        isStarting = true
        startingActivityCode = code

        await requestPermissions()

        let root = AppConstants.documentsSessionsRoot
        let fileStore = SessionFileStore(rootURL: root)
        store = fileStore

        let info = Bundle.main
        let manifest = SessionManifest(
            testerId: TesterIdentity.resolve(),
            appVersion: info.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            buildNumber: info.infoDictionary?["CFBundleVersion"] as? String ?? "1",
            watchModel: WatchSessionController.deviceModel(),
            systemVersion: WKInterfaceDevice.current().systemVersion,
            waterTemperatureAvailable: waterTemperatureAvailable,
            activityCode: code,
            wristLocation: WatchSessionController.wristLocationCode(),
            crownOrientation: WatchSessionController.crownOrientationCode()
        )
        self.manifest = manifest
        WakeLog.debug(.session, "created manifest \(manifest.sessionId.prefix(8))…")

        do {
            _ = try fileStore.createSession(manifest: manifest)
            refreshStoredByteSize()
            WakeLog.debug(.store, "createSession OK \(manifest.sessionId.prefix(8))…")
        } catch {
            errorText = String(localized: "Store: \(error.localizedDescription)")
            statusText = String(localized: "Failed")
            WakeLog.error(.store, "createSession: \(error.localizedDescription)")
            isStarting = false
            startingActivityCode = nil
            return
        }
        ActivityCodes.rememberLastUsed(code)

        let workoutStarted = await startWorkoutIfAuthorized()
        if workoutStarted {
            recordingMode = "workout"
        } else {
            recordingMode = "sensorsOnly"
            statusText = String(localized: "Sensors-only (no HK workout)")
        }
        WakeLog.debug(.session, "recordingMode=\(recordingMode)")

        detectionCode = DetectionCodes.inactive
        lastConfidentCode = DetectionCodes.inactive
        lastPersistedConfidentCode = DetectionCodes.inactive
        detectionSimulationMode = .detected
        detectionCount = 0
        locationCount = 0
        motionCount = 0
        currentRideDuration = 0
        currentInactiveDuration = 0
        lastSpeedMps = nil
        lastHorizontalAccuracy = nil
        filterRejectionReason = nil
        detectionEngine = DetectionEngine()
        liveRideTracker.reset()
        sessionStartLatitude = nil
        sessionStartLongitude = nil
        recentLocationRing.removeAll(keepingCapacity: true)
        resetWaterTemperatureTracking()
        #if RPPL_WEATHERKIT
        resetAirWeather()
        #endif
        sensorSamplingDense = false

        startLocation()
        startMotionIfAvailable()
        startActivityUpdatesIfAvailable()

        startedAt = Date()
        pausedAccumulated = 0
        productPausedAt = nil
        isProductPaused = false
        currentSegmentStartedAt = Date()
        isRunning = true
        isStarting = false
        startingActivityCode = nil
        if recordingMode == "workout" {
            statusText = String(localized: "Recording")
        }

        logSessionStartDetection()
        WKInterfaceDevice.current().enableWaterLock()
        WakeLog.debug(.session, "Water Lock enabled")
        WKInterfaceDevice.current().play(.start)

        startBackgroundLoops()
        WakeLog.debug(.session, "startSession running sessionId=\(manifest.sessionId.prefix(8))…")
    }

    func stopSession() async {
        guard isRunning, !isStopping, let manifest, let store else {
            WakeLog.debug(.session, "stopSession ignored — running=\(isRunning) stopping=\(isStopping)")
            return
        }
        WakeLog.debug(.session, "stopSession begin \(manifest.sessionId.prefix(8))…")
        beginSessionTeardown(status: String(localized: "Stopping…"))

        stopSensors()
        liveRideTracker.closeOpenRide()
        await flushBuffers()

        do {
            try store.markReadyToTransfer(sessionId: manifest.sessionId)
            WakeLog.debug(.store, "markReadyToTransfer \(manifest.sessionId.prefix(8))…")
            do {
                _ = try store.ensureDerivedView(sessionId: manifest.sessionId)
                WakeLog.debug(.store, "derived view written \(manifest.sessionId.prefix(8))…")
            } catch {
                WakeLog.error(.store, "ensureDerivedView: \(error.localizedDescription)")
            }
        } catch {
            errorText = String(localized: "Mark transfer: \(error.localizedDescription)")
            WakeLog.error(.store, "markReadyToTransfer: \(error.localizedDescription)")
        }

        await finishAndSaveWorkout()
        recordingMode = "none"
        motionRecordingEnabled = false

        statusText = String(localized: "Transferring…")
        let stoppedSessionId = manifest.sessionId
        WatchTransferService.shared.enqueueTransfer(sessionId: stoppedSessionId, store: store)
        statusText = String(localized: "Stopped - waiting for phone ack")

        let finalDuration = computeElapsed(at: Date())
        endedSessionSummary = EndedSessionSummary(
            sessionId: stoppedSessionId,
            duration: finalDuration,
            rideCount: liveRideTracker.rideCount,
            distanceMeters: liveRideTracker.sessionRideMeters,
            lastRideDuration: liveRideTracker.lastRideDuration,
            lastRideMeters: liveRideTracker.lastRideMeters,
            lastRideLapCount: liveRideTracker.lastRideLapCount,
            didCompleteRide: liveRideTracker.didCompleteRide,
            startLatitude: sessionStartLatitude,
            startLongitude: sessionStartLongitude
        )

        WKInterfaceDevice.current().play(.stop)
        WakeLog.debug(.session, "stopSession done — summary shown sessionId=\(stoppedSessionId.prefix(8))…")
        clearSessionRuntimeState()
    }

    /// Confirmed tiny-session discard: delete local package, no transfer, no Health save.
    /// Keep-until-phone-ack still applies only when the rider chooses Keep (transfer).
    func discardSession() async {
        guard isRunning, !isStopping, let manifest, let store else {
            WakeLog.debug(.session, "discardSession ignored — running=\(isRunning) stopping=\(isStopping)")
            return
        }
        let sessionId = manifest.sessionId
        WakeLog.debug(.session, "discardSession begin \(sessionId.prefix(8))…")
        beginSessionTeardown(status: String(localized: "Discarding…"))

        stopSensors()
        liveRideTracker.closeOpenRide()
        // No flush — package will be deleted; never queue transfer for discard.

        await discardWorkoutWithoutSaving()
        recordingMode = "none"
        motionRecordingEnabled = false

        do {
            try store.deleteSession(sessionId: sessionId)
            WakeLog.debug(.store, "deleteSession discarded \(sessionId.prefix(8))…")
        } catch {
            errorText = String(localized: "Discard: \(error.localizedDescription)")
            WakeLog.error(.store, "deleteSession: \(error.localizedDescription)")
        }

        endedSessionSummary = nil
        statusText = String(localized: "Idle")
        WKInterfaceDevice.current().play(.stop)
        WakeLog.debug(.session, "discardSession done \(sessionId.prefix(8))…")
        clearSessionRuntimeState()
    }

    private func beginSessionTeardown(status: String) {
        isStopping = true
        statusText = status
        if isProductPaused {
            if let productPausedAt {
                pausedAccumulated += Date().timeIntervalSince(productPausedAt)
            }
            productPausedAt = nil
            isProductPaused = false
        }
        flushTask?.cancel()
        timerTask?.cancel()
    }

    private func clearSessionRuntimeState() {
        liveRideTracker.reset()
        storedByteSize = 0
        currentRideDuration = 0
        currentInactiveDuration = 0
        lastSpeedMps = nil
        lastHorizontalAccuracy = nil
        filterRejectionReason = nil
        detectionSimulationMode = .detected
        currentSegmentStartedAt = nil
        lastPersistedConfidentCode = DetectionCodes.inactive
        resetWaterTemperatureTracking()
        #if RPPL_WEATHERKIT
        resetAirWeather()
        #endif
        hkRideDistanceMeters = 0
        hkRideDistanceAnchorMeters = 0
        hkRides = []
        hkRideStartedAt = nil
        hkRideActivityOpen = false
        hkGpsFilter = GpsSignalFilter()
        hkPreviousUsableSpeedMps = nil
        hkPeakSpeedMps = 0
        pausedAccumulated = 0
        productPausedAt = nil
        isProductPaused = false
        sessionStartLatitude = nil
        sessionStartLongitude = nil
        self.manifest = nil
        isRunning = false
        isStopping = false
    }

    func pauseSession() async {
        guard isRunning, !isStopping, !isProductPaused else {
            WakeLog.debug(.session, "pauseSession ignored")
            return
        }
        WakeLog.debug(.session, "pauseSession begin")
        applyForcedInactive(reason: "product_pause", detectorId: "product_pause")
        await flushBuffers()
        flushTask?.cancel()
        timerTask?.cancel()
        flushTask = nil
        timerTask = nil
        stopSensors()
        if let session = workoutSession, session.state == .running {
            session.pause()
            WakeLog.debug(.workout, "HK pause (product)")
        }
        productPausedAt = Date()
        elapsed = computeElapsed(at: Date())
        isProductPaused = true
        statusText = String(localized: "Paused")
        WKInterfaceDevice.current().play(.stop)
        WakeLog.debug(.session, "pauseSession done")
    }

    func resumeSession() {
        guard isRunning, !isStopping, isProductPaused else {
            WakeLog.debug(.session, "resumeSession ignored")
            return
        }
        WakeLog.debug(.session, "resumeSession begin")
        if let productPausedAt {
            pausedAccumulated += Date().timeIntervalSince(productPausedAt)
        }
        productPausedAt = nil
        isProductPaused = false
        applyForcedInactive(reason: "product_resume", detectorId: "product_resume")
        startLocation()
        startMotionIfAvailable()
        startActivityUpdatesIfAvailable()
        startBackgroundLoops()
        if let session = workoutSession, session.state == .paused {
            session.resume()
            WakeLog.debug(.workout, "HK resume (product)")
        }
        syncWorkoutForDetection(code: lastPersistedConfidentCode)
        statusText = recordingMode == "workout"
            ? String(localized: "Recording")
            : String(localized: "Sensors-only (no HK workout)")
        WKInterfaceDevice.current().play(.start)
        WakeLog.debug(.session, "resumeSession done")
    }

    func enableWaterLock() {
        WKInterfaceDevice.current().enableWaterLock()
        WakeLog.debug(.ui, "Water Lock enabled (manual)")
    }

    func dismissSessionSummary() {
        guard endedSessionSummary != nil else { return }
        WakeLog.debug(.ui, "dismiss session summary")
        endedSessionSummary = nil
        statusText = String(localized: "Idle")
    }

    func captureSessionStartCoordinate(from sample: LocationSample) {
        guard sessionStartLatitude == nil else { return }
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= DetectionThresholds.default.maxHorizontalAccuracyM
        else { return }
        sessionStartLatitude = sample.latitude
        sessionStartLongitude = sample.longitude
    }

    /// Cycle debug simulation: detected → inactive → ride → detected.
}
