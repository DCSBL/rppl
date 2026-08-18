import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore
import Observation

@Observable
@MainActor
final class WatchSessionController: NSObject {
    static let shared = WatchSessionController()

    var isRunning = false
    /// True while stop teardown / Health save runs — keep active UI with spinner; block Start.
    var isStopping = false
    /// Product pause: sensors/timers halted; distinct from detection `inactive`.
    var isProductPaused = false
    var detectionCode = DetectionCodes.inactive
    var lastConfidentCode = DetectionCodes.inactive
    var elapsed: TimeInterval = 0
    var locationCount = 0
    var motionCount = 0
    var detectionCount = 0
    /// On-disk size of the active session package (updated after flushes / detection writes).
    var storedByteSize: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastHorizontalAccuracy: Double?
    var lastHeartRate: Double?
    var lastSpeedMps: Double?
    /// Ride-gated session distance (sum of ride meters). Not dock/pause walking.
    var totalDistanceM: Double { liveRideTracker.sessionRideMeters }
    var currentRideDuration: TimeInterval = 0
    var currentInactiveDuration: TimeInterval = 0
    var filterRejectionReason: String?
    var statusText = String(localized: "Idle")
    var errorText: String?
    var healthAuthStatus = "unknown"
    var locationAuthStatus = "unknown"
    var motionAvailability = "unknown"
    /// `workout` when HK session started; `sensorsOnly` when Health denied / simulator fallback.
    var recordingMode = "none"
    var motionRecordingEnabled = false

    var isUnsure: Bool { detectionCode == DetectionCodes.unsure }
    var rideCount: Int { liveRideTracker.rideCount }
    var currentRideSpeedKmh: Double? { liveRideTracker.currentSpeedKmh }
    var currentRideLapCount: Int { liveRideTracker.currentRideLapCount }
    var lastRideLapCount: Int { liveRideTracker.lastRideLapCount }
    /// Live meters while riding; frozen last-ride meters when inactive (`0 m` before first ride).
    var displayRideMeters: Double {
        liveRideTracker.isRideOngoing
            ? liveRideTracker.currentRideMeters
            : liveRideTracker.lastRideMeters
    }
    var lastRideMeters: Double { liveRideTracker.lastRideMeters }
    var lastRideDuration: TimeInterval { liveRideTracker.lastRideDuration }
    var didCompleteRide: Bool { liveRideTracker.didCompleteRide }
    var isRideOngoing: Bool { liveRideTracker.isRideOngoing }

    /// Debug-only: force pause/ride UI, or leave live detection (`detected`).
    private(set) var detectionSimulationMode: DetectionSimulationMode = .detected

    private var liveRideTracker = LiveRideTracker()
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutDataSource: HKLiveWorkoutDataSource?
    private var workoutConfiguration: HKWorkoutConfiguration?
    private var workoutRouteBuilder: HKWorkoutRouteBuilder?
    /// True while an HK ride activity is open (ended on detection `inactive`).
    private var hkRideActivityOpen = false
    private var workoutStoppedContinuation: CheckedContinuation<Date, Never>?
    private var hkRideDistanceMeters = 0.0
    private var hkRideDistanceAnchorMeters = 0.0
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private var waterManager: CMWaterSubmersionManager?

    private var store: SessionFileStore?
    private var manifest: SessionManifest?
    private var latestLocation: CLLocation?
    private var latestActivity: String?
    private var latestWaterState: String?
    private var latestWaterTempC: Double?
    private var detectionEngine = DetectionEngine()
    private var locationBuffer: [LocationSample] = []
    private var motionBuffer: [MotionSample] = []
    private var healthBuffer: [HealthMetricSample] = []
    private var flushTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?
    /// Wall time excluded from `elapsed` while product-paused (completed pauses).
    private var pausedAccumulated: TimeInterval = 0
    private var productPausedAt: Date?
    private var currentSegmentStartedAt: Date?
    private var lastPersistedConfidentCode = DetectionCodes.inactive
    private var motionUpdatesStarted = false
    private var activityUpdatesStarted = false

    private let workoutType = HKObjectType.workoutType()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let basalEnergyType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
    private let distanceType = HKObjectType.quantityType(forIdentifier: .distancePaddleSports)!
    private let workoutRouteType = HKSeriesType.workoutRoute()

    /// Write access required to start HKWorkoutSession and save the workout/route.
    private var typesToShare: Set<HKSampleType> {
        [workoutType, activeEnergyType, basalEnergyType, heartRateType, distanceType, workoutRouteType]
    }

    private var typesToRead: Set<HKObjectType> {
        [heartRateType, activeEnergyType, basalEnergyType, workoutType, distanceType]
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        refreshPermissionStatus()

        if CMWaterSubmersionManager.waterSubmersionAvailable {
            let manager = CMWaterSubmersionManager()
            manager.delegate = self
            waterManager = manager
        }
    }

    func refreshPermissionStatus() {
        locationAuthStatus = Self.locationLabel(locationManager.authorizationStatus)

        if motionManager.isDeviceMotionAvailable {
            motionAvailability = "deviceMotion available"
        } else {
            motionAvailability = "unavailable (skipped)"
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthStatus = String(localized: "Health unavailable")
            return
        }
        switch healthStore.authorizationStatus(for: workoutType) {
        case .notDetermined:
            healthAuthStatus = String(localized: "workout: notDetermined")
        case .sharingDenied:
            healthAuthStatus = String(localized: "workout: denied — enable in Settings › Health")
        case .sharingAuthorized:
            healthAuthStatus = String(localized: "workout: authorized")
        @unknown default:
            healthAuthStatus = String(localized: "workout: unknown")
        }
    }

    /// Safe to call repeatedly. System may only show the sheet while status is notDetermined.
    func requestPermissions() async {
        WakeLog.debug(.permissions, "requestPermissions begin")
        errorText = nil
        locationManager.requestWhenInUseAuthorization()

        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthStatus = String(localized: "Health unavailable")
            WakeLog.debug(.permissions, "Health unavailable")
            refreshPermissionStatus()
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            statusText = String(localized: "Permissions updated")
            WakeLog.debug(.permissions, "Health authorization requested OK")
        } catch {
            errorText = String(localized: "Health auth: \(error.localizedDescription)")
            WakeLog.error(.permissions, "Health auth: \(error.localizedDescription)")
        }
        refreshPermissionStatus()
        WakeLog.debug(
            .permissions,
            "status health=\(healthAuthStatus) loc=\(locationAuthStatus) motion=\(motionAvailability)"
        )
    }

    func startSession() async {
        guard !isRunning, !isStopping else {
            WakeLog.debug(.session, "startSession ignored — running=\(isRunning) stopping=\(isStopping)")
            return
        }
        WakeLog.debug(.session, "startSession begin")
        errorText = nil
        statusText = String(localized: "Starting…")
        recordingMode = "none"

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
            systemVersion: WKInterfaceDevice.current().systemVersion
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
            return
        }

        let workoutStarted = await startWorkoutIfAuthorized()
        if workoutStarted {
            recordingMode = "workout"
        } else {
            recordingMode = "sensorsOnly"
            statusText = String(localized: "Sensors-only (no HK workout)")
        }
        WakeLog.debug(.session, "recordingMode=\(recordingMode)")

        startLocation()
        startMotionIfAvailable()
        startActivityUpdatesIfAvailable()

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
        startedAt = Date()
        pausedAccumulated = 0
        productPausedAt = nil
        isProductPaused = false
        currentSegmentStartedAt = Date()
        isRunning = true
        if recordingMode == "workout" {
            statusText = String(localized: "Recording")
        }

        logSessionStartDetection()
        WKInterfaceDevice.current().enableWaterLock()
        WakeLog.debug(.session, "Water Lock enabled")

        startBackgroundLoops()
        WakeLog.debug(.session, "startSession running sessionId=\(manifest.sessionId.prefix(8))…")
    }

    func stopSession() async {
        guard isRunning, !isStopping, let manifest, let store else {
            WakeLog.debug(.session, "stopSession ignored — running=\(isRunning) stopping=\(isStopping)")
            return
        }
        WakeLog.debug(.session, "stopSession begin \(manifest.sessionId.prefix(8))…")
        isStopping = true
        statusText = String(localized: "Stopping…")
        if isProductPaused {
            if let productPausedAt {
                pausedAccumulated += Date().timeIntervalSince(productPausedAt)
            }
            productPausedAt = nil
            isProductPaused = false
        }
        flushTask?.cancel()
        timerTask?.cancel()

        stopSensors()
        liveRideTracker.closeOpenRide()
        await flushBuffers()

        do {
            try store.markReadyToTransfer(sessionId: manifest.sessionId)
            WakeLog.debug(.store, "markReadyToTransfer \(manifest.sessionId.prefix(8))…")
        } catch {
            errorText = String(localized: "Mark transfer: \(error.localizedDescription)")
            WakeLog.error(.store, "markReadyToTransfer: \(error.localizedDescription)")
        }

        await finishAndSaveWorkout()
        recordingMode = "none"
        motionRecordingEnabled = false

        statusText = String(localized: "Transferring…")
        WatchTransferService.shared.enqueueTransfer(sessionId: manifest.sessionId, store: store)
        statusText = String(localized: "Stopped — waiting for phone ack")
        WakeLog.debug(.session, "stopSession done — awaiting phone ack")
        storedByteSize = 0
        currentRideDuration = 0
        currentInactiveDuration = 0
        lastSpeedMps = nil
        lastHorizontalAccuracy = nil
        filterRejectionReason = nil
        detectionSimulationMode = .detected
        currentSegmentStartedAt = nil
        lastPersistedConfidentCode = DetectionCodes.inactive
        hkRideDistanceMeters = 0
        hkRideDistanceAnchorMeters = 0
        hkRideActivityOpen = false
        pausedAccumulated = 0
        productPausedAt = nil
        isProductPaused = false
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
        WakeLog.debug(.session, "resumeSession done")
    }

    func enableWaterLock() {
        WKInterfaceDevice.current().enableWaterLock()
        WakeLog.debug(.ui, "Water Lock enabled (manual)")
    }

    /// Cycle debug simulation: detected → inactive → ride → detected.
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

    private func applyDetectionSimulation(_ mode: DetectionSimulationMode) {
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

    private func playRideHaptic(for code: String) {
        switch code {
        case DetectionCodes.riding:
            WKInterfaceDevice.current().play(.success)
        case DetectionCodes.inactive:
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
    }

    private func forceSimulatedDetection(code: String) {
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
        if isRunning || isStopping {
            WakeLog.debug(.intent, "StartCableParkSessionIntent: busy running=\(isRunning) stopping=\(isStopping) — no-op")
            return
        }
        WakeLog.debug(.intent, "StartCableParkSessionIntent: starting session")
        await startSession()
    }

    private func logSessionStartDetection() {
        let event = detectionEngine.makeSessionStartEvent(at: Date())
        detectionCode = event.code
        lastConfidentCode = detectionEngine.lastConfidentCode
        persistDetection(event)
    }

    private func processDetectionTick(timestamp: Date = Date()) {
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
        guard !events.isEmpty else { return }
        for event in events {
            persistDetection(event)
        }
    }

    private func processLocationSample(_ sample: LocationSample) {
        liveRideTracker.addLocation(sample)
        accumulateRideDistanceForHealthKit()
    }

    private func accumulateRideDistanceForHealthKit() {
        guard liveRideTracker.isRideOngoing else { return }
        let current = liveRideTracker.currentRideMeters
        if current > hkRideDistanceAnchorMeters {
            hkRideDistanceMeters += current - hkRideDistanceAnchorMeters
            hkRideDistanceAnchorMeters = current
        }
    }

    private func persistDetection(_ event: DetectionEvent) {
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

    private func handleDetectionTransition(_ event: DetectionEvent) {
        guard DetectionCodes.isConfident(event.code) else { return }
        if event.code != lastPersistedConfidentCode {
            if lastPersistedConfidentCode == DetectionCodes.riding {
                accumulateRideDistanceForHealthKit()
                hkRideDistanceAnchorMeters = 0
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

    /// Keep HK session running. Ride activities only (Fitness interval rows). Dock wait is a gap, not a rest activity.
    private func syncWorkoutForDetection(code: String, at date: Date = Date()) {
        guard !isProductPaused else { return }
        guard workoutSession != nil else { return }
        switch code {
        case DetectionCodes.riding:
            setRideMetricsCollection(enabled: true)
            beginRideActivity(at: date)
            WakeLog.debug(.workout, "HK riding activity")
        case DetectionCodes.inactive:
            endRideActivity(at: date)
            setRideMetricsCollection(enabled: false)
            WakeLog.debug(.workout, "HK ride activity ended (inactive)")
        default:
            break
        }
    }

    private func beginRideActivity(at date: Date) {
        guard let session = workoutSession, let config = workoutConfiguration else { return }
        guard !hkRideActivityOpen else { return }
        session.beginNewActivity(
            configuration: config,
            date: date,
            metadata: ["nl.dcsbl.rppl.detectionCode": DetectionCodes.riding]
        )
        hkRideActivityOpen = true
    }

    private func endRideActivity(at date: Date) {
        guard let session = workoutSession, hkRideActivityOpen else { return }
        session.endCurrentActivity(on: date)
        hkRideActivityOpen = false
    }

    private func setRideMetricsCollection(enabled: Bool) {
        guard let dataSource = workoutDataSource else { return }
        if enabled {
            dataSource.enableCollection(for: activeEnergyType, predicate: nil)
            dataSource.enableCollection(for: distanceType, predicate: nil)
        } else {
            dataSource.disableCollection(for: activeEnergyType)
            dataSource.disableCollection(for: distanceType)
        }
    }

    private func startBackgroundLoops() {
        flushTask?.cancel()
        timerTask?.cancel()
        flushTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning, !self.isProductPaused {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.flushBuffers()
            }
        }
        timerTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning, !self.isProductPaused {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.elapsed = self.computeElapsed(at: Date())
                self.refreshSegmentDurations()
            }
        }
    }

    private func computeElapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        var total = date.timeIntervalSince(startedAt) - pausedAccumulated
        if let productPausedAt {
            total -= date.timeIntervalSince(productPausedAt)
        }
        return max(0, total)
    }

    private func applyForcedInactive(reason: String, detectorId: String) {
        let event = detectionEngine.makeForcedInactiveEvent(
            at: Date(),
            reason: reason,
            detectorId: detectorId
        )
        detectionCode = event.code
        lastConfidentCode = detectionEngine.lastConfidentCode
        filterRejectionReason = nil
        liveRideTracker.update(
            currentCode: detectionCode,
            lastConfident: lastConfidentCode,
            events: [event]
        )
        persistDetection(event)
    }

    private func refreshSegmentDurations() {
        guard let segmentStart = currentSegmentStartedAt else {
            currentRideDuration = 0
            currentInactiveDuration = 0
            return
        }
        let segmentElapsed = Date().timeIntervalSince(segmentStart)
        if lastConfidentCode == DetectionCodes.riding {
            currentRideDuration = segmentElapsed
            currentInactiveDuration = 0
        } else if lastConfidentCode == DetectionCodes.inactive {
            currentInactiveDuration = segmentElapsed
            currentRideDuration = 0
        } else {
            currentRideDuration = 0
            currentInactiveDuration = 0
        }
    }

    /// Returns true if an HK workout session is running.
    private func startWorkoutIfAuthorized() async -> Bool {
        refreshPermissionStatus()
        let status = healthStore.authorizationStatus(for: workoutType)
        if status == .sharingDenied {
            errorText = String(localized: "Workout not authorized — tap Request permissions or enable in Health settings. Continuing without workout.")
            WakeLog.debug(.workout, "sharingDenied — sensors-only")
            return false
        }

        do {
            try await startWorkout()
            WakeLog.debug(.workout, "HKWorkoutSession started (save on stop)")
            return true
        } catch {
            // Simulator / denied / notDetermined often surfaces here as "Not authorized".
            errorText = String(localized: "Workout: \(error.localizedDescription). Continuing sensors-only.")
            WakeLog.error(.workout, "start failed: \(error.localizedDescription) — sensors-only")
            workoutSession = nil
            workoutBuilder = nil
            workoutDataSource = nil
            workoutConfiguration = nil
            workoutRouteBuilder = nil
            hkRideActivityOpen = false
            return false
        }
    }

    private func startWorkout() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .waterSports
        config.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        dataSource.enableCollection(for: heartRateType, predicate: nil)
        dataSource.enableCollection(for: basalEnergyType, predicate: nil)
        dataSource.enableCollection(for: activeEnergyType, predicate: nil)
        dataSource.enableCollection(for: distanceType, predicate: nil)
        builder.dataSource = dataSource
        workoutDataSource = dataSource
        session.delegate = self
        builder.delegate = self

        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyWorkoutBrandName: "Rppl",
        ]
        if let sessionId = manifest?.sessionId {
            metadata["nl.dcsbl.rppl.sessionId"] = sessionId
            metadata["nl.dcsbl.rppl.activityName"] = "Cable Park"
        }
        try await builder.addMetadata(metadata)

        workoutSession = session
        workoutBuilder = builder
        workoutConfiguration = config
        workoutRouteBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        hkRideDistanceMeters = 0
        hkRideDistanceAnchorMeters = 0
        hkRideActivityOpen = false

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())
        // Session starts inactive: keep HR/basal streaming; ride-scoped metrics off until riding.
        setRideMetricsCollection(enabled: false)
        WakeLog.debug(.workout, "HK collection began (inactive — ride metrics gated)")
    }

    private func finishAndSaveWorkout() async {
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        WakeLog.debug(.workout, "finishAndSaveWorkout begin")
        accumulateRideDistanceForHealthKit()

        let requestEnd = Date()
        endRideActivity(at: requestEnd)
        let stoppedDate: Date
        if session.state == .stopped {
            stoppedDate = requestEnd
        } else {
            stoppedDate = await withCheckedContinuation { continuation in
                workoutStoppedContinuation = continuation
                session.stopActivity(with: requestEnd)
            }
        }

        do {
            try await builder.addMetadata(["nl.dcsbl.rppl.rideCount": liveRideTracker.rideCount])
            try await builder.endCollection(at: stoppedDate)
            if hkRideDistanceMeters > 0, let start = startedAt {
                let quantity = HKQuantity(unit: .meter(), doubleValue: hkRideDistanceMeters)
                let sample = HKQuantitySample(
                    type: distanceType,
                    quantity: quantity,
                    start: start,
                    end: stoppedDate
                )
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.add([sample]) { success, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: SessionStoreError.ioFailure("Failed to add distance sample"))
                        }
                    }
                }
                WakeLog.debug(.workout, "added ride distance \(Int(hkRideDistanceMeters)) m")
            }
            let workout = try await builder.finishWorkout()
            if let workout, let routeBuilder = workoutRouteBuilder {
                do {
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                    WakeLog.debug(.workout, "workout route saved")
                } catch {
                    WakeLog.error(.workout, "finishRoute: \(error.localizedDescription)")
                }
            }
            WakeLog.debug(.workout, "finishWorkout OK — Health save complete")
        } catch {
            errorText = String(localized: "Save workout: \(error.localizedDescription)")
            WakeLog.error(.workout, "finishWorkout: \(error.localizedDescription)")
        }

        session.end()
        workoutSession = nil
        workoutBuilder = nil
        workoutDataSource = nil
        workoutConfiguration = nil
        workoutRouteBuilder = nil
        workoutStoppedContinuation = nil
        hkRideActivityOpen = false
    }

    private func insertRouteLocations(_ locations: [CLLocation]) async {
        guard let routeBuilder = workoutRouteBuilder else { return }
        let usable = locations.filter { loc in
            loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 50
        }
        guard !usable.isEmpty else { return }
        do {
            try await routeBuilder.insertRouteData(usable)
        } catch {
            WakeLog.error(.workout, "insertRouteData: \(error.localizedDescription)")
        }
    }

    private func startLocation() {
        // Background updates need Always auth; avoid enabling them when not allowed.
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            locationManager.allowsBackgroundLocationUpdates = false
        }
        locationManager.startUpdatingLocation()
        WakeLog.debug(.session, "location updates started auth=\(locationAuthStatus)")
    }

    private func startMotionIfAvailable() {
        motionRecordingEnabled = false
        motionUpdatesStarted = false
        guard motionManager.isDeviceMotionAvailable else {
            motionAvailability = "unavailable (skipped)"
            WakeLog.debug(.session, "device motion unavailable — skipped")
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 25.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.isRunning, !self.isProductPaused else { return }
            let sample = MotionSample(
                timestamp: Date(),
                userAccelX: motion.userAcceleration.x,
                userAccelY: motion.userAcceleration.y,
                userAccelZ: motion.userAcceleration.z,
                rotationX: motion.rotationRate.x,
                rotationY: motion.rotationRate.y,
                rotationZ: motion.rotationRate.z,
                pitch: motion.attitude.pitch,
                roll: motion.attitude.roll,
                yaw: motion.attitude.yaw
            )
            self.motionBuffer.append(sample)
            self.motionCount += 1
        }
        motionUpdatesStarted = true
        motionRecordingEnabled = true
        motionAvailability = "recording"
        WakeLog.debug(.session, "device motion recording @25Hz (zlib JSONL)")
    }

    private func startActivityUpdatesIfAvailable() {
        activityUpdatesStarted = false
        guard CMMotionActivityManager.isActivityAvailable() else {
            WakeLog.debug(.session, "motion activity unavailable")
            return
        }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            let next: String
            if activity.automotive { next = "automotive" }
            else if activity.cycling { next = "cycling" }
            else if activity.running { next = "running" }
            else if activity.walking { next = "walking" }
            else if activity.stationary { next = "stationary" }
            else { next = "unknown" }
            if self.latestActivity != next {
                self.latestActivity = next
                WakeLog.debug(.session, "motionActivity → \(next)")
            }
        }
        activityUpdatesStarted = true
        WakeLog.debug(.session, "motion activity updates started")
    }

    private func stopSensors() {
        WakeLog.debug(.session, "stopSensors")
        locationManager.stopUpdatingLocation()
        if motionUpdatesStarted {
            motionManager.stopDeviceMotionUpdates()
            motionUpdatesStarted = false
        }
        if activityUpdatesStarted {
            activityManager.stopActivityUpdates()
            activityUpdatesStarted = false
        }
    }

    private func flushBuffers() async {
        guard let store, let manifest else { return }
        let locations = locationBuffer
        let motions = motionBuffer
        let health = healthBuffer
        locationBuffer.removeAll(keepingCapacity: true)
        motionBuffer.removeAll(keepingCapacity: true)
        healthBuffer.removeAll(keepingCapacity: true)

        guard !locations.isEmpty || !motions.isEmpty || !health.isEmpty else { return }

        do {
            if !locations.isEmpty {
                try store.appendLocationSamples(locations, sessionId: manifest.sessionId)
            }
            if !motions.isEmpty {
                try store.appendMotionSamples(motions, sessionId: manifest.sessionId)
            }
            if !health.isEmpty {
                try store.appendHealthSamples(health, sessionId: manifest.sessionId)
            }
            refreshStoredByteSize()
            // Success path silent — every ~2s while recording would drown action logs.
        } catch {
            errorText = String(localized: "Flush: \(error.localizedDescription)")
            WakeLog.error(
                .store,
                "flush loc=\(locations.count) mot=\(motions.count) health=\(health.count): \(error.localizedDescription)"
            )
        }
    }

    private func refreshStoredByteSize() {
        guard let store, let manifest else {
            storedByteSize = 0
            return
        }
        do {
            storedByteSize = try store.sessionByteSize(sessionId: manifest.sessionId)
        } catch {
            WakeLog.error(.store, "sessionByteSize: \(error.localizedDescription)")
        }
    }

    private static func locationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default: return "unknown"
        }
    }

    private static func deviceModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

extension WatchSessionController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard isRunning, !isProductPaused, let loc = locations.last else { return }
            await insertRouteLocations(locations)
            if loc.speed >= 0 {
                lastSpeedMps = loc.speed
            }
            if loc.horizontalAccuracy >= 0 {
                lastHorizontalAccuracy = loc.horizontalAccuracy
            }
            latestLocation = loc
            lastLatitude = loc.coordinate.latitude
            lastLongitude = loc.coordinate.longitude
            let sample = LocationSample(
                timestamp: loc.timestamp,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                altitude: loc.altitude,
                horizontalAccuracy: loc.horizontalAccuracy,
                verticalAccuracy: loc.verticalAccuracy,
                speed: loc.speed >= 0 ? loc.speed : nil,
                course: loc.course >= 0 ? loc.course : nil
            )
            locationBuffer.append(sample)
            locationCount += 1
            processLocationSample(sample)
            processDetectionTick(timestamp: loc.timestamp)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let before = locationAuthStatus
            refreshPermissionStatus()
            WakeLog.debug(.permissions, "location auth \(before) → \(locationAuthStatus)")
        }
    }
}

extension WatchSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            WakeLog.debug(.workout, "state \(Self.workoutStateName(fromState)) → \(Self.workoutStateName(toState))")
            if toState == .stopped, let continuation = workoutStoppedContinuation {
                workoutStoppedContinuation = nil
                continuation.resume(returning: date)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            errorText = error.localizedDescription
            WakeLog.error(.workout, "session failed: \(error.localizedDescription)")
            if let continuation = workoutStoppedContinuation {
                workoutStoppedContinuation = nil
                continuation.resume(returning: Date())
            }
        }
    }

    private static func workoutStateName(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted: return "notStarted"
        case .running: return "running"
        case .ended: return "ended"
        case .paused: return "paused"
        case .prepared: return "prepared"
        case .stopped: return "stopped"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}

extension WatchSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            guard isRunning, !isProductPaused else { return }
            let now = Date()
            var hr: Double?
            var energy: Double?
            var basal: Double?

            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
               collectedTypes.contains(hrType),
               let statistics = workoutBuilder.statistics(for: hrType),
               let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                hr = value
                lastHeartRate = value
            }
            if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
               collectedTypes.contains(energyType),
               let statistics = workoutBuilder.statistics(for: energyType),
               let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                energy = value
            }
            if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
               collectedTypes.contains(basalType),
               let statistics = workoutBuilder.statistics(for: basalType),
               let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                basal = value
            }
            if hr != nil || energy != nil || basal != nil {
                healthBuffer.append(
                    HealthMetricSample(
                        timestamp: now,
                        heartRateBPM: hr,
                        activeEnergyKilocalories: energy,
                        basalEnergyKilocalories: basal
                    )
                )
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchSessionController: CMWaterSubmersionManagerDelegate {
    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate event: CMWaterSubmersionEvent) {
        Task { @MainActor in
            let next: String
            switch event.state {
            case .unknown: next = "unknown"
            case .notSubmerged: next = "notSubmerged"
            case .submerged: next = "submerged"
            @unknown default: next = "other"
            }
            if latestWaterState != next {
                latestWaterState = next
                WakeLog.debug(.water, "submersion → \(next)")
                processDetectionTick()
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterSubmersionMeasurement
    ) {
        Task { @MainActor in
            var next = String(describing: measurement.submersionState)
            if let depth = measurement.depth {
                let meters = depth.converted(to: UnitLength.meters).value
                if meters > 0 { next = "submerged" }
            }
            if latestWaterState != next {
                latestWaterState = next
                WakeLog.debug(.water, "measurement → \(next)")
                processDetectionTick()
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterTemperature
    ) {
        Task { @MainActor in
            let temp = measurement.temperature.converted(to: UnitTemperature.celsius).value
            let previous = latestWaterTempC
            latestWaterTempC = temp
            if previous == nil || abs((previous ?? 0) - temp) >= 0.5 {
                WakeLog.debug(.water, String(format: "waterTemp %.1f°C", temp))
            }
        }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: any Error) {
        Task { @MainActor in
            WakeLog.error(.water, "submersion error: \(error.localizedDescription)")
        }
    }
}
