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
    var detectionCode = DetectionCodes.paused
    var lastConfidentCode = DetectionCodes.paused
    var elapsed: TimeInterval = 0
    var locationCount = 0
    var motionCount = 0
    var detectionCount = 0
    /// On-disk size of the active session package (updated after flushes / detection writes).
    var storedByteSize: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastHeartRate: Double?
    var statusText = "Idle"
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
    /// Live meters while riding; frozen last-ride meters when paused (`0 m` before first ride).
    var displayRideMeters: Double {
        liveRideTracker.isRideOngoing
            ? liveRideTracker.currentRideMeters
            : liveRideTracker.lastRideMeters
    }
    var isRideOngoing: Bool { liveRideTracker.isRideOngoing }

    private var liveRideTracker = LiveRideTracker()
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
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
    private var motionUpdatesStarted = false
    private var activityUpdatesStarted = false

    private let workoutType = HKObjectType.workoutType()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!

    /// Write access is required to *start* HKWorkoutSession, even if we never finish/save the workout.
    private var typesToShare: Set<HKSampleType> {
        [workoutType, activeEnergyType, heartRateType]
    }

    private var typesToRead: Set<HKObjectType> {
        [heartRateType, activeEnergyType, workoutType]
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
            healthAuthStatus = "Health unavailable"
            return
        }
        switch healthStore.authorizationStatus(for: workoutType) {
        case .notDetermined:
            healthAuthStatus = "workout: notDetermined"
        case .sharingDenied:
            healthAuthStatus = "workout: denied — enable in Settings › Health"
        case .sharingAuthorized:
            healthAuthStatus = "workout: authorized"
        @unknown default:
            healthAuthStatus = "workout: unknown"
        }
    }

    /// Safe to call repeatedly. System may only show the sheet while status is notDetermined.
    func requestPermissions() async {
        WakeLog.debug(.permissions, "requestPermissions begin")
        errorText = nil
        locationManager.requestWhenInUseAuthorization()

        guard HKHealthStore.isHealthDataAvailable() else {
            healthAuthStatus = "Health unavailable"
            WakeLog.debug(.permissions, "Health unavailable")
            refreshPermissionStatus()
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            statusText = "Permissions updated"
            WakeLog.debug(.permissions, "Health authorization requested OK")
        } catch {
            errorText = "Health auth: \(error.localizedDescription)"
            WakeLog.error(.permissions, "Health auth: \(error.localizedDescription)")
        }
        refreshPermissionStatus()
        WakeLog.debug(
            .permissions,
            "status health=\(healthAuthStatus) loc=\(locationAuthStatus) motion=\(motionAvailability)"
        )
    }

    func startSession() async {
        guard !isRunning else {
            WakeLog.debug(.session, "startSession ignored — already running")
            return
        }
        WakeLog.debug(.session, "startSession begin")
        errorText = nil
        statusText = "Starting…"
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
            errorText = "Store: \(error.localizedDescription)"
            statusText = "Failed"
            WakeLog.error(.store, "createSession: \(error.localizedDescription)")
            return
        }

        let workoutStarted = await startWorkoutIfAuthorized()
        if workoutStarted {
            recordingMode = "workout"
        } else {
            recordingMode = "sensorsOnly"
            statusText = "Sensors-only (no HK workout)"
        }
        WakeLog.debug(.session, "recordingMode=\(recordingMode)")

        startLocation()
        startMotionIfAvailable()
        startActivityUpdatesIfAvailable()

        detectionCode = DetectionCodes.paused
        lastConfidentCode = DetectionCodes.paused
        detectionCount = 0
        locationCount = 0
        motionCount = 0
        detectionEngine = DetectionEngine()
        liveRideTracker.reset()
        startedAt = Date()
        isRunning = true
        if recordingMode == "workout" {
            statusText = "Recording"
        }

        logSessionStartDetection()
        WKInterfaceDevice.current().enableWaterLock()
        WakeLog.debug(.session, "Water Lock enabled")

        flushTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.flushBuffers()
            }
        }
        timerTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        }
        WakeLog.debug(.session, "startSession running sessionId=\(manifest.sessionId.prefix(8))…")
    }

    func stopSession() async {
        guard isRunning, let manifest, let store else {
            WakeLog.debug(.session, "stopSession ignored — not running")
            return
        }
        WakeLog.debug(.session, "stopSession begin \(manifest.sessionId.prefix(8))…")
        statusText = "Stopping…"
        isRunning = false
        flushTask?.cancel()
        timerTask?.cancel()

        stopSensors()
        liveRideTracker.closeOpenRide()
        await flushBuffers()

        do {
            try store.markReadyToTransfer(sessionId: manifest.sessionId)
            WakeLog.debug(.store, "markReadyToTransfer \(manifest.sessionId.prefix(8))…")
        } catch {
            errorText = "Mark transfer: \(error.localizedDescription)"
            WakeLog.error(.store, "markReadyToTransfer: \(error.localizedDescription)")
        }

        await endWorkoutDiscardingHealthSave()
        recordingMode = "none"
        motionRecordingEnabled = false

        statusText = "Transferring…"
        WatchTransferService.shared.enqueueTransfer(sessionId: manifest.sessionId, store: store)
        statusText = "Stopped — waiting for phone ack"
        WakeLog.debug(.session, "stopSession done — awaiting phone ack")
        storedByteSize = 0
        self.manifest = nil
    }

    /// Start-workout Action Button entry: start session, or no-op if already recording.
    func handleStartWorkoutIntent() async {
        if isRunning {
            WakeLog.debug(.intent, "StartCableParkSessionIntent: already running — no-op")
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
        guard isRunning else { return }
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
        detectionCode = detectionEngine.currentCode
        lastConfidentCode = detectionEngine.lastConfidentCode
        liveRideTracker.update(
            currentCode: detectionCode,
            lastConfident: lastConfidentCode,
            events: events
        )
        for event in events {
            persistDetection(event)
        }
    }

    private func processLocationSample(_ sample: LocationSample) {
        liveRideTracker.addLocation(sample)
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
        } catch {
            errorText = "Detection: \(error.localizedDescription)"
            WakeLog.error(.detection, "appendDetection: \(error.localizedDescription)")
        }
    }

    /// Returns true if an HK workout session is running.
    private func startWorkoutIfAuthorized() async -> Bool {
        refreshPermissionStatus()
        let status = healthStore.authorizationStatus(for: workoutType)
        if status == .sharingDenied {
            errorText = "Workout not authorized — tap Request permissions or enable in Health settings. Continuing without workout."
            WakeLog.debug(.workout, "sharingDenied — sensors-only")
            return false
        }

        do {
            try await startWorkout()
            WakeLog.debug(.workout, "HKWorkoutSession started (dry-run)")
            return true
        } catch {
            // Simulator / denied / notDetermined often surfaces here as "Not authorized".
            errorText = "Workout: \(error.localizedDescription). Continuing sensors-only."
            WakeLog.error(.workout, "start failed: \(error.localizedDescription) — sensors-only")
            workoutSession = nil
            workoutBuilder = nil
            return false
        }
    }

    private func startWorkout() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .waterSports
        config.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        session.delegate = self
        builder.delegate = self

        workoutSession = session
        workoutBuilder = builder

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())
    }

    private func endWorkoutDiscardingHealthSave() async {
        guard workoutSession != nil || workoutBuilder != nil else { return }
        WakeLog.debug(.workout, "end workout (no finishWorkout / Health save)")
        let end = Date()
        workoutSession?.stopActivity(with: end)
        do {
            try await workoutBuilder?.endCollection(at: end)
            // Intentionally do NOT call finishWorkout() — dry-run, keep Health clean.
        } catch {
            errorText = "End workout: \(error.localizedDescription)"
            WakeLog.error(.workout, "endCollection: \(error.localizedDescription)")
        }
        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
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
            guard let self, let motion, self.isRunning else { return }
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
            errorText = "Flush: \(error.localizedDescription)"
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
            guard isRunning, let loc = locations.last else { return }
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
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            errorText = error.localizedDescription
            WakeLog.error(.workout, "session failed: \(error.localizedDescription)")
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
            guard isRunning else { return }
            let now = Date()
            var hr: Double?
            var energy: Double?

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
            if hr != nil || energy != nil {
                healthBuffer.append(
                    HealthMetricSample(
                        timestamp: now,
                        heartRateBPM: hr,
                        activeEnergyKilocalories: energy
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
