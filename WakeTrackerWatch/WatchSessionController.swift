import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import WakeTrackerCore
import Observation

@Observable
@MainActor
final class WatchSessionController: NSObject {
    static let shared = WatchSessionController()

    var isRunning = false
    var currentLabel = LabelCodes.waiting
    var elapsed: TimeInterval = 0
    var locationCount = 0
    var motionCount = 0
    var labelCount = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastHeartRate: Double?
    var statusText = "Idle"
    var errorText: String?

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
    private var locationBuffer: [LocationSample] = []
    private var motionBuffer: [MotionSample] = []
    private var healthBuffer: [HealthMetricSample] = []
    private var flushTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?

    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.workoutType(),
    ]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.activityType = .fitness

        if CMWaterSubmersionManager.waterSubmersionAvailable {
            let manager = CMWaterSubmersionManager()
            manager.delegate = self
            waterManager = manager
        }
    }

    func requestPermissions() async {
        locationManager.requestWhenInUseAuthorization()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            statusText = "Permissions ready"
        } catch {
            errorText = error.localizedDescription
        }
    }

    func startSession() async {
        guard !isRunning else { return }
        errorText = nil
        statusText = "Starting…"

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

        do {
            _ = try fileStore.createSession(manifest: manifest)
        } catch {
            errorText = "Store: \(error.localizedDescription)"
            statusText = "Failed"
            return
        }

        do {
            try await startWorkout()
        } catch {
            errorText = "Workout: \(error.localizedDescription)"
            statusText = "Failed"
            return
        }

        startLocation()
        startMotion()
        startActivityUpdates()

        currentLabel = LabelCodes.waiting
        labelCount = 0
        locationCount = 0
        motionCount = 0
        startedAt = Date()
        isRunning = true
        statusText = "Recording"

        logLabel(code: LabelCodes.waiting)
        WKInterfaceDevice.current().enableWaterLock()

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
    }

    func stopSession() async {
        guard isRunning, let manifest, let store else { return }
        statusText = "Stopping…"
        isRunning = false
        flushTask?.cancel()
        timerTask?.cancel()

        stopSensors()
        await flushBuffers()

        do {
            try store.markReadyToTransfer(sessionId: manifest.sessionId)
        } catch {
            errorText = "Mark transfer: \(error.localizedDescription)"
        }

        await endWorkoutDiscardingHealthSave()

        statusText = "Transferring…"
        WatchTransferService.shared.enqueueTransfer(sessionId: manifest.sessionId, store: store)
        statusText = "Stopped — waiting for phone ack"
        self.manifest = nil
    }

    func cycleLabelFromActionButton() {
        guard isRunning else { return }
        let next = LabelCodes.next(after: currentLabel)
        currentLabel = next
        logLabel(code: next)
    }

    private func logLabel(code: String) {
        guard let store, let manifest else { return }
        let gps: GPSSnapshot?
        if let loc = latestLocation {
            gps = GPSSnapshot(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                altitude: loc.altitude,
                horizontalAccuracy: loc.horizontalAccuracy,
                verticalAccuracy: loc.verticalAccuracy,
                speed: loc.speed >= 0 ? loc.speed : nil,
                course: loc.course >= 0 ? loc.course : nil,
                timestamp: loc.timestamp
            )
        } else {
            gps = nil
        }

        let event = LabelEvent(
            code: code,
            timestamp: Date(),
            gps: gps,
            waterSubmersionState: latestWaterState,
            waterTemperatureCelsius: latestWaterTempC,
            motionActivity: latestActivity
        )
        do {
            try store.appendLabel(event, sessionId: manifest.sessionId)
            labelCount += 1
        } catch {
            errorText = "Label: \(error.localizedDescription)"
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
        let end = Date()
        workoutSession?.stopActivity(with: end)
        do {
            try await workoutBuilder?.endCollection(at: end)
            // Intentionally do NOT call finishWorkout() — dry-run, keep Health clean.
        } catch {
            errorText = "End workout: \(error.localizedDescription)"
        }
        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
    }

    private func startLocation() {
        locationManager.startUpdatingLocation()
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
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
    }

    private func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            if activity.automotive { self?.latestActivity = "automotive" }
            else if activity.cycling { self?.latestActivity = "cycling" }
            else if activity.running { self?.latestActivity = "running" }
            else if activity.walking { self?.latestActivity = "walking" }
            else if activity.stationary { self?.latestActivity = "stationary" }
            else { self?.latestActivity = "unknown" }
        }
    }

    private func stopSensors() {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
    }

    private func flushBuffers() async {
        guard let store, let manifest else { return }
        let locations = locationBuffer
        let motions = motionBuffer
        let health = healthBuffer
        locationBuffer.removeAll(keepingCapacity: true)
        motionBuffer.removeAll(keepingCapacity: true)
        healthBuffer.removeAll(keepingCapacity: true)

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
        } catch {
            errorText = "Flush: \(error.localizedDescription)"
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
            locationBuffer.append(
                LocationSample(
                    timestamp: loc.timestamp,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    altitude: loc.altitude,
                    horizontalAccuracy: loc.horizontalAccuracy,
                    verticalAccuracy: loc.verticalAccuracy,
                    speed: loc.speed >= 0 ? loc.speed : nil,
                    course: loc.course >= 0 ? loc.course : nil
                )
            )
            locationCount += 1
        }
    }
}

extension WatchSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            errorText = error.localizedDescription
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
            switch event.state {
            case .unknown: latestWaterState = "unknown"
            case .notSubmerged: latestWaterState = "notSubmerged"
            case .submerged: latestWaterState = "submerged"
            @unknown default: latestWaterState = "other"
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterSubmersionMeasurement
    ) {
        Task { @MainActor in
            latestWaterState = String(describing: measurement.submersionState)
            if let depth = measurement.depth {
                let meters = depth.converted(to: UnitLength.meters).value
                if meters > 0 { latestWaterState = "submerged" }
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterTemperature
    ) {
        Task { @MainActor in
            latestWaterTempC = measurement.temperature.converted(to: UnitTemperature.celsius).value
        }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: any Error) {
        // Best-effort only for alpha.
    }
}
