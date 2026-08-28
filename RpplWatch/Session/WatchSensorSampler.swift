import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore

// MARK: - Sensors
extension WatchSessionController {
    func startLocation() {
        // Background updates need Always auth; avoid enabling them when not allowed.
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            locationManager.allowsBackgroundLocationUpdates = false
        }
        applySensorSamplingMode(dense: SensorSamplingMode.isDense(currentCode: detectionCode))
        locationManager.startUpdatingLocation()
        WakeLog.debug(.session, "location updates started auth=\(locationAuthStatus)")
    }

    func startMotionIfAvailable() {
        motionRecordingEnabled = false
        motionUpdatesStarted = false
        guard motionManager.isDeviceMotionAvailable else {
            motionAvailability = "unavailable (skipped)"
            WakeLog.debug(.session, "device motion unavailable — skipped")
            return
        }
        startDeviceMotionUpdates(interval: motionUpdateInterval(dense: sensorSamplingDense))
        motionRecordingEnabled = true
        motionAvailability = "recording"
        WakeLog.debug(
            .session,
            "device motion recording @\(Int(1.0 / motionUpdateInterval(dense: sensorSamplingDense)))Hz (zlib JSONL)"
        )
    }

    private func startDeviceMotionUpdates(interval: TimeInterval) {
        motionManager.deviceMotionUpdateInterval = interval
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
    }

    func applySensorSamplingMode(dense: Bool) {
        guard sensorSamplingDense != dense else { return }
        sensorSamplingDense = dense
        if dense {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = kCLDistanceFilterNone
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 8
        }
        if isRunning, !isProductPaused {
            if motionUpdatesStarted {
                motionManager.stopDeviceMotionUpdates()
                motionUpdatesStarted = false
            }
            if motionManager.isDeviceMotionAvailable {
                startDeviceMotionUpdates(interval: motionUpdateInterval(dense: dense))
                motionRecordingEnabled = true
            }
        }
        WakeLog.debug(.session, "sensor sampling dense=\(dense)")
    }

    private func motionUpdateInterval(dense: Bool) -> TimeInterval {
        dense ? (1.0 / 25.0) : 1.0
    }

    func appendToLocationRing(_ sample: LocationSample) {
        recentLocationRing.append(sample)
        let cutoff = sample.timestamp.addingTimeInterval(-Self.locationRingMaxAge)
        recentLocationRing.removeAll { $0.timestamp < cutoff }
    }

    func replayLocationRingForRideEnter(holdStart: Date) {
        let samples = recentLocationRing
            .filter { $0.timestamp >= holdStart }
            .sorted { $0.timestamp < $1.timestamp }
        guard !samples.isEmpty else { return }
        liveSetTracker.replayLocationsForSetEnter(samples, from: holdStart)
    }

    func startActivityUpdatesIfAvailable() {
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

    func stopSensors() {
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

    func flushBuffers() async {
        guard let store, let manifest else { return }
        let locations = locationBuffer
        let motions = motionBuffer
        let health = healthBuffer
        let water = waterBuffer
        locationBuffer.removeAll(keepingCapacity: true)
        motionBuffer.removeAll(keepingCapacity: true)
        healthBuffer.removeAll(keepingCapacity: true)
        waterBuffer.removeAll(keepingCapacity: true)

        guard !locations.isEmpty || !motions.isEmpty || !health.isEmpty || !water.isEmpty else { return }

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
            if !water.isEmpty {
                try store.appendWaterTemperatureSamples(water, sessionId: manifest.sessionId)
            }
            refreshStoredByteSize()
            // Success path silent — every ~2s while recording would drown action logs.
        } catch {
            errorText = String(localized: "Flush: \(error.localizedDescription)")
            WakeLog.error(
                .store,
                "flush loc=\(locations.count) mot=\(motions.count) health=\(health.count) "
                    + "water=\(water.count): \(error.localizedDescription)"
            )
        }
    }

    func resetWaterTemperatureTracking() {
        waterBuffer.removeAll(keepingCapacity: true)
        sessionWaterSamples.removeAll(keepingCapacity: true)
        lastPersistedWaterTempAt = nil
        lastLoggedWaterTempC = nil
        waterTempNeedsBoutSample = latestWaterState == "submerged"
        waterTempSum = 0
        waterTempCount = 0
        averageWaterTemperatureCelsius = nil
    }

    func applyWaterSubmersionState(_ next: String) {
        if latestWaterState != next {
            if next == "submerged" {
                waterTempNeedsBoutSample = true
            }
            latestWaterState = next
            WakeLog.debug(.water, "submersion → \(next)")
            processDetectionTick()
        }
    }

    func considerPersistingWaterTemperature(_ temp: Double) {
        guard isRunning, !isProductPaused, latestWaterState == "submerged" else { return }
        let now = Date()
        let intervalElapsed = lastPersistedWaterTempAt.map {
            now.timeIntervalSince($0) >= Self.waterTempPersistInterval
        } ?? true
        guard waterTempNeedsBoutSample || intervalElapsed else { return }

        let isBoutStart = waterTempNeedsBoutSample
        let sample = WaterTemperatureSample(timestamp: now, celsius: temp)
        waterBuffer.append(sample)
        sessionWaterSamples.append(sample)
        lastPersistedWaterTempAt = now
        waterTempNeedsBoutSample = false
        waterTempSum += temp
        waterTempCount += 1
        averageWaterTemperatureCelsius = waterTempSum / Double(waterTempCount)

        let jumped = lastLoggedWaterTempC.map { abs($0 - temp) >= Self.waterTempLogDeltaC } ?? true
        if isBoutStart || jumped {
            lastLoggedWaterTempC = temp
            WakeLog.debug(.water, String(format: "waterTemp %.1f C n=%d", temp, waterTempCount))
        }
    }

    func refreshStoredByteSize() {
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

    static func locationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default: return "unknown"
        }
    }

    static func deviceModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// User Watch setting at session start — CoreMotion axes stay hardware-fixed.
    static func wristLocationCode() -> String {
        switch WKInterfaceDevice.current().wristLocation {
        case .left: return "left"
        case .right: return "right"
        @unknown default: return "unknown"
        }
    }

    static func crownOrientationCode() -> String {
        switch WKInterfaceDevice.current().crownOrientation {
        case .left: return "left"
        case .right: return "right"
        @unknown default: return "unknown"
        }
    }

    static let waterTempPersistInterval: TimeInterval = 15
    static let waterTempLogDeltaC = 2.0
    static let locationRingMaxAge: TimeInterval = 5
}
