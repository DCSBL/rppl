import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore

// MARK: - Sensors
extension WatchSessionController {
    func startLocation() {
        // The `location` background mode is declared; When-In-Use is enough to keep updates
        // flowing while a session runs (sensors-only has no workout session to keep us alive).
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.allowsBackgroundLocationUpdates = true
        default:
            locationManager.allowsBackgroundLocationUpdates = false
        }
        applySensorSamplingMode(dense: SensorSamplingMode.isDense(currentCode: detectionCode))
        locationManager.startUpdatingLocation()
        WakeLog.debug(.session, "location updates started auth=\(locationAuthStatus)")
    }

    func startMotionIfAvailable() {
        motionRecordingEnabled = false
        motionUpdatesStarted = false
        guard motionStoppedReason == nil else {
            motionAvailability = "stopped (\(motionStoppedReason ?? "?"))"
            return
        }
        if let freeBytes = store?.availableCapacityBytes() {
            let decision = MotionRecordingPolicy.decide(elapsed: 0, motionBytes: 0, freeBytes: freeBytes)
            if decision != .record {
                applyMotionDecision(decision)
                return
            }
        }
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
            guard let self, let motion, self.isRunning, !self.isProductPaused, self.motionRecordingEnabled else {
                return
            }
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
        if isRunning, !isProductPaused, motionStoppedReason == nil {
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

    /// Persist buffered samples. File work runs off the main actor so encoding and disk I/O never
    /// stall the UI or sensor callbacks; flushes are chained so batches land in order.
    ///
    /// Motion is written once per `MotionRecordingPolicy.frameInterval` (or when `force`), after
    /// every other stream, and its failure never costs the others.
    func flushBuffers(force: Bool = false) async {
        drainRouteLocations()
        guard let store, let manifest else { return }
        considerPersistingBattery()
        let now = Date()
        let motionDue = force || lastMotionFlushAt.map {
            now.timeIntervalSince($0) >= MotionRecordingPolicy.frameInterval
        } ?? true
        let locations = locationBuffer
        let motions = motionDue ? motionBuffer : []
        let health = healthBuffer
        let water = waterBuffer
        let battery = batteryBuffer
        locationBuffer.removeAll(keepingCapacity: true)
        if motionDue {
            motionBuffer.removeAll(keepingCapacity: true)
            lastMotionFlushAt = now
        }
        healthBuffer.removeAll(keepingCapacity: true)
        waterBuffer.removeAll(keepingCapacity: true)
        batteryBuffer.removeAll(keepingCapacity: true)

        guard !locations.isEmpty || !motions.isEmpty || !health.isEmpty || !water.isEmpty || !battery.isEmpty
        else {
            await flushChain?.value
            return
        }

        let sessionId = manifest.sessionId
        let elapsedNow = computeElapsed(at: now)
        let checkMotionBudget = !motions.isEmpty && motionStoppedReason == nil
        let previous = flushChain
        let flush = Task { [weak self] in
            await previous?.value
            // Each stream is written on its own: one failing (full disk) must not cost the
            // others, and only what failed goes back in the buffer for the next flush.
            let outcome = await StoreIO.runOffMainCollectingFailures(
                locations: locations,
                health: health,
                water: water,
                battery: battery,
                store: store,
                sessionId: sessionId
            )
            self?.handleFlushOutcome(outcome, locations: locations, health: health, water: water, battery: battery)
            guard !motions.isEmpty else { return }
            let decision: MotionRecordingPolicy.Decision
            do {
                decision = try await StoreIO.runOffMain { () throws -> MotionRecordingPolicy.Decision in
                    try store.appendMotionSamples(motions, sessionId: sessionId)
                    guard checkMotionBudget else { return .record }
                    return MotionRecordingPolicy.decide(
                        elapsed: elapsedNow,
                        motionBytes: try store.motionByteSize(sessionId: sessionId),
                        freeBytes: store.availableCapacityBytes()
                    )
                }
            } catch {
                // Motion is expendable: a failed write stops it instead of retrying.
                WakeLog.error(.store, "motion flush n=\(motions.count): \(error.localizedDescription)")
                decision = .stop(reason: MotionRecordingPolicy.Reason.lowStorage)
            }
            if decision != .record {
                self?.applyMotionDecision(decision)
            }
        }
        flushChain = flush
        await flush.value
    }

    /// Put batches that failed to write back in front of the buffers (bounded) and surface the
    /// problem once; the next flush retries them.
    func handleFlushOutcome(
        _ outcome: FlushOutcome,
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        battery: [BatterySample]
    ) {
        if let byteSize = outcome.byteSize {
            storedByteSize = byteSize
        }
        guard let error = outcome.error else { return }
        if outcome.failed.contains(.locations) {
            locationBuffer = SampleRequeue.merge(failed: locations, before: locationBuffer, cap: SampleRequeue.locationCap)
        }
        if outcome.failed.contains(.health) {
            healthBuffer = SampleRequeue.merge(failed: health, before: healthBuffer, cap: SampleRequeue.healthCap)
        }
        if outcome.failed.contains(.water) {
            waterBuffer = SampleRequeue.merge(failed: water, before: waterBuffer, cap: SampleRequeue.waterCap)
        }
        if outcome.failed.contains(.battery) {
            batteryBuffer = SampleRequeue.merge(failed: battery, before: batteryBuffer, cap: SampleRequeue.batteryCap)
        }
        errorText = String(localized: "Flush: \(error)")
        WakeLog.error(
            .store,
            "flush failed \(outcome.failed.map(\.rawValue).sorted()) loc=\(locations.count) health=\(health.count) "
                + "water=\(water.count) battery=\(battery.count): \(error) — kept for retry"
        )
    }

    /// Stop motion for the rest of the session (and delete it when storage is critical). Motion
    /// gives way first so GPS, detection and health keep recording.
    func applyMotionDecision(_ decision: MotionRecordingPolicy.Decision) {
        guard let reason = decision.reason, motionStoppedReason == nil else { return }
        motionStoppedReason = reason
        motionRecordingEnabled = false
        if motionUpdatesStarted {
            motionManager.stopDeviceMotionUpdates()
            motionUpdatesStarted = false
        }
        motionBuffer.removeAll()
        motionAvailability = "stopped (\(reason))"
        WakeLog.debug(.session, "motion stopped reason=\(reason)")
        guard let store, let sessionId = manifest?.sessionId else { return }
        let dropRecorded: Bool
        if case .dropRecorded = decision { dropRecorded = true } else { dropRecorded = false }
        let stoppedAt = Date()
        Task {
            do {
                try await StoreIO.runOffMain {
                    if dropRecorded {
                        try store.deleteMotion(sessionId: sessionId)
                    }
                    try store.markMotionStopped(reason: reason, at: stoppedAt, sessionId: sessionId)
                }
            } catch {
                WakeLog.error(.store, "motion stop bookkeeping: \(error.localizedDescription)")
            }
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

    func resetBatteryTracking() {
        batteryBuffer.removeAll(keepingCapacity: true)
        lastPersistedBatteryAt = nil
        lastPersistedBatteryLevel = nil
        lastPersistedBatteryState = nil
    }

    func enableBatteryMonitoring() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    func disableBatteryMonitoring() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
    }

    /// Persist when level/state changes, every 60s heartbeat, or when `force` (lifecycle anchors).
    func considerPersistingBattery(force: Bool = false) {
        guard isRunning else { return }
        if !force, isProductPaused { return }

        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let rawLevel = Double(device.batteryLevel)
        guard rawLevel >= 0 else { return }

        let state = Self.batteryStateCode(device.batteryState)
        let now = Date()
        let intervalElapsed = lastPersistedBatteryAt.map {
            now.timeIntervalSince($0) >= Self.batteryPersistInterval
        } ?? true
        let levelChanged = lastPersistedBatteryLevel.map { abs($0 - rawLevel) > 0 } ?? true
        let stateChanged = lastPersistedBatteryState.map { $0 != state } ?? true
        guard force || intervalElapsed || levelChanged || stateChanged else { return }

        let sample = BatterySample(timestamp: now, level: rawLevel, state: state)
        batteryBuffer.append(sample)
        lastPersistedBatteryAt = now
        lastPersistedBatteryLevel = rawLevel
        lastPersistedBatteryState = state
        WakeLog.debug(
            .session,
            String(format: "battery level=%.4f state=%@", rawLevel, state)
        )
    }

    static func batteryStateCode(_ state: WKInterfaceDeviceBatteryState) -> String {
        switch state {
        case .unplugged:
            return BatteryStateCodes.unplugged
        case .charging:
            return BatteryStateCodes.charging
        case .full:
            return BatteryStateCodes.full
        case .unknown:
            return BatteryStateCodes.unknown
        @unknown default:
            return BatteryStateCodes.unknown
        }
    }

    func applyWaterSubmersionState(_ next: String) {
        if latestWaterState != next {
            if next == "submerged" {
                waterTempNeedsBoutSample = true
            }
            latestWaterState = next
            WakeLog.debug(.water, "submersion → \(next)")
            processDetectionHeartbeat()
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
    static let batteryPersistInterval: TimeInterval = 60
    static let locationRingMaxAge: TimeInterval = 5
}

extension StoreIO {
    /// Write each stream separately off the main actor and report which ones failed.
    static func runOffMainCollectingFailures(
        locations: [LocationSample],
        health: [HealthMetricSample],
        water: [WaterTemperatureSample],
        battery: [BatterySample],
        store: SessionFileStore,
        sessionId: String
    ) async -> FlushOutcome {
        let result = try? await StoreIO.runOffMain {
            SessionFlushWriter.write(
                locations: locations,
                health: health,
                water: water,
                battery: battery,
                store: store,
                sessionId: sessionId
            )
        }
        return result ?? FlushOutcome(failed: Set(FlushStream.allCases), error: "flush task failed")
    }
}
