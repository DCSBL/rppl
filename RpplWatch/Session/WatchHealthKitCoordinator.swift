import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import WatchKit
import RpplCore

// MARK: - HealthKit
extension WatchSessionController {
    func syncWorkoutForDetection(code: String, at date: Date = Date()) {
        guard !isProductPaused else { return }
        guard workoutSession != nil else { return }
        switch code {
        case DetectionCodes.riding:
            setRideMetricsCollection(enabled: true)
            beginDetectionActivity(code: code, at: date)
            WakeLog.debug(.workout, "HK riding activity")
        case DetectionCodes.inactive:
            beginDetectionActivity(code: code, at: date)
            setRideMetricsCollection(enabled: false)
            WakeLog.debug(.workout, "HK inactive activity")
        default:
            break
        }
    }

    func beginDetectionActivity(code: String, at date: Date) {
        guard let session = workoutSession, let config = workoutConfiguration else { return }
        session.beginNewActivity(
            configuration: config,
            date: date,
            metadata: [WorkoutMetadataKeys.detectionCode: code]
        )
        hkRideActivityOpen = true
    }

    func endRideActivity(at date: Date) {
        guard let session = workoutSession, hkRideActivityOpen else { return }
        session.endCurrentActivity(on: date)
        hkRideActivityOpen = false
    }

    func setRideMetricsCollection(enabled: Bool) {
        guard let dataSource = workoutDataSource else { return }
        if enabled {
            dataSource.enableCollection(for: activeEnergyType, predicate: nil)
        } else {
            dataSource.disableCollection(for: activeEnergyType)
        }
    }

    func startBackgroundLoops() {
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
                // Detection ticks otherwise only arrive with GPS fixes, so a blackout froze the
                // engine: no `gps_gap`, no `unsure_timeout`, set left open.
                self.processDetectionHeartbeat()
            }
        }
    }

    func computeElapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        var total = date.timeIntervalSince(startedAt) - pausedAccumulated
        if let productPausedAt {
            total -= date.timeIntervalSince(productPausedAt)
        }
        return max(0, total)
    }

    func applyForcedInactive(reason: String, detectorId: String) {
        let event = detectionEngine.makeForcedInactiveEvent(
            at: Date(),
            reason: reason,
            detectorId: detectorId
        )
        detectionCode = event.code
        lastConfidentCode = detectionEngine.lastConfidentCode
        filterRejectionReason = nil
        liveSetTracker.update(
            currentCode: detectionCode,
            lastConfident: lastConfidentCode,
            events: [event]
        )
        persistDetection(event)
    }

    func refreshSegmentDurations() {
        guard let segmentStart = currentSegmentStartedAt else {
            currentSetDuration = 0
            currentInactiveDuration = 0
            return
        }
        let segmentElapsed = Date().timeIntervalSince(segmentStart)
        if lastConfidentCode == DetectionCodes.riding {
            currentSetDuration = segmentElapsed
            currentInactiveDuration = 0
        } else if lastConfidentCode == DetectionCodes.inactive {
            currentInactiveDuration = segmentElapsed
            currentSetDuration = 0
        } else {
            currentSetDuration = 0
            currentInactiveDuration = 0
        }
    }

    /// Waits until `workoutSession` reaches `.running`, or times out.
    func waitForWorkoutSessionRunning(timeoutSeconds: TimeInterval = 5) async -> Bool {
        guard let session = workoutSession else { return false }
        if session.state == .running { return true }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.workoutRunningContinuation = continuation
                    if session.state == .running {
                        self.workoutRunningContinuation = nil
                        continuation.resume()
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }
            guard let first = await group.next() else { return false }
            group.cancelAll()
            if !first {
                workoutRunningContinuation = nil
            }
            return first
        }
    }

    /// Ends a workout session left dangling by a crash so watchOS stops handing it back
    /// on every relaunch. Runs off the launch path; each step is time-bounded.
    func recoverDanglingWorkoutSession() async {
        let store = healthStore
        let recovered: HKWorkoutSession? = await withTaskGroup(of: HKWorkoutSession?.self) { group in
            group.addTask { try? await store.recoverActiveWorkoutSession() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let session = recovered, workoutSession == nil else { return }
        WakeLog.debug(.workout, "recovered dangling HKWorkoutSession state=\(session.state.rawValue)")
        let builder = session.associatedWorkoutBuilder()
        if session.state == .running || session.state == .paused {
            session.stopActivity(with: Date())
            for _ in 0..<20 where session.state != .stopped {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            WakeLog.error(.workout, "dangling finishWorkout: \(error.localizedDescription)")
        }
        session.end()
    }

    /// Returns true if an HK workout session is running.
    func startWorkoutIfAuthorized() async -> Bool {
        refreshPermissionStatus()
        await refreshHealthPermissionStatus()
        if healthPermission == .denied {
            errorText = String(localized: "Workout not authorized - tap Request permissions or enable in Health settings. Continuing without workout.")
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

    func startWorkout() async throws {
        let config = HealthKitWorkoutPolicy.makeConfiguration()

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        dataSource.enableCollection(for: heartRateType, predicate: nil)
        dataSource.enableCollection(for: basalEnergyType, predicate: nil)
        dataSource.enableCollection(for: activeEnergyType, predicate: nil)
        // Do not live-collect GPS distance (dock walking). Ride-gated samples attach at save.
        dataSource.disableCollection(for: distanceType)
        builder.dataSource = dataSource
        workoutDataSource = dataSource
        session.delegate = self
        builder.delegate = self

        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyWorkoutBrandName: "Rppl",
        ]
        if let sessionId = manifest?.sessionId {
            metadata[WorkoutMetadataKeys.sessionId] = sessionId
        }
        if let activityCode = manifest?.activityCode, !activityCode.isEmpty {
            metadata[AppConstants.hkMetadataActivityCode] = activityCode
        }
        try await builder.addMetadata(metadata)

        workoutSession = session
        workoutBuilder = builder
        workoutConfiguration = config
        workoutRouteBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        hkRideDistanceMeters = 0
        hkRideDistanceAnchorMeters = 0
        hkRides = []
        hkRideStartedAt = nil
        hkRideActivityOpen = false
        hkGpsFilter = GpsSignalFilter()
        hkPreviousUsableSpeedMps = nil
        hkPreviousUsableAt = nil
        hkPendingJumpSpeedMps = nil
        hkPeakSpeedMps = 0

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())
        // Session starts inactive: keep HR/basal streaming; set-scoped metrics off until riding.
        setRideMetricsCollection(enabled: false)
        WakeLog.debug(.workout, "HK collection began (inactive — set metrics gated)")
    }

    func finishAndSaveWorkout() async {
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        WakeLog.debug(.workout, "finishAndSaveWorkout begin")
        accumulateRideDistanceForHealthKit()

        let requestEnd = Date()
        recordFinishedHkRide(endedAt: requestEnd)
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
            var closingMetadata: [String: Any] = [
                WorkoutMetadataKeys.setCount: liveSetTracker.setCount,
                WorkoutMetadataKeys.totalDistanceMeters: hkRideDistanceMeters
            ]
            if let speedMps = LocationSpeedStats.averageSpeedMetersPerSecond(
                distanceMeters: hkRideDistanceMeters,
                duration: liveSetTracker.sessionRidingDuration
            ) {
                closingMetadata[HKMetadataKeyAverageSpeed] = HKQuantity(
                    unit: .meter().unitDivided(by: .second()),
                    doubleValue: speedMps
                )
            }
            if hkPeakSpeedMps > 0 {
                closingMetadata[HKMetadataKeyMaximumSpeed] = HKQuantity(
                    unit: .meter().unitDivided(by: .second()),
                    doubleValue: hkPeakSpeedMps
                )
            }
            try await builder.addMetadata(closingMetadata)
            await attachAirWeatherMetadata(to: builder)
            try await builder.endCollection(at: stoppedDate)
            do {
                try await addRideDistanceSamples(to: builder)
                try await attachRideMetricsToActivities(builder)
            } catch {
                WakeLog.error(.workout, "ride distance/interval samples: \(error.localizedDescription)")
            }
            do {
                try await addWaterTemperatureSamples(to: builder)
            } catch {
                WakeLog.error(.workout, "waterTemperature samples: \(error.localizedDescription)")
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
        clearWorkoutSessionRefs()
    }

    /// User-confirmed tiny-session discard: no Health save, no phone transfer.
    func discardWorkoutWithoutSaving() async {
        guard let session = workoutSession else {
            clearWorkoutSessionRefs()
            return
        }
        WakeLog.debug(.workout, "discardWorkout begin")
        let requestEnd = Date()
        endRideActivity(at: requestEnd)
        if session.state != .stopped {
            _ = await withCheckedContinuation { continuation in
                workoutStoppedContinuation = continuation
                session.stopActivity(with: requestEnd)
            }
        }
        workoutBuilder?.discardWorkout()
        session.end()
        clearWorkoutSessionRefs()
        WakeLog.debug(.workout, "discardWorkout OK — no Health save")
    }

    private func clearWorkoutSessionRefs() {
        workoutSession = nil
        workoutBuilder = nil
        workoutDataSource = nil
        workoutConfiguration = nil
        workoutRouteBuilder = nil
        workoutStoppedContinuation = nil
        workoutRunningContinuation = nil
        hkRideActivityOpen = false
    }

    func resetAirWeather() {
        airWeatherFetchTask?.cancel()
        airWeatherFetchTask = nil
        airWeatherSnapshot = nil
        airWeatherAttempted = false
    }

    func requestAirWeatherIfNeeded(from location: CLLocation) {
        guard !airWeatherAttempted else { return }
        guard AirWeatherKit.isUsable(location) else { return }
        airWeatherAttempted = true
        let loc = location
        airWeatherFetchTask = Task { [weak self] in
            let snapshot = await AirWeatherKit.fetch(location: loc)
            guard let self, !Task.isCancelled else { return }
            self.airWeatherSnapshot = snapshot
            self.airWeatherFetchTask = nil
            if let snapshot {
                self.persistAirWeather(snapshot)
                WakeLog.debug(.workout, "air weather cached")
            }
        }
    }

    func persistAirWeather(_ snapshot: AirWeatherSnapshot) {
        guard let store, var current = manifest else { return }
        let weather = snapshot.sessionWeather
        current.weather = weather
        manifest = current
        do {
            try store.updateWeather(weather, sessionId: current.sessionId)
        } catch {
            WakeLog.error(.store, "weather manifest: \(error.localizedDescription)")
        }
    }

    func attachAirWeatherMetadata(to builder: HKLiveWorkoutBuilder) async {
        if airWeatherSnapshot == nil, let task = airWeatherFetchTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(AirWeatherKit.fetchTimeout))
                }
                await group.next()
                group.cancelAll()
            }
        }
        if airWeatherSnapshot == nil, let loc = latestLocation, AirWeatherKit.isUsable(loc) {
            airWeatherFetchTask?.cancel()
            airWeatherFetchTask = nil
            airWeatherSnapshot = await AirWeatherKit.fetch(location: loc)
            if let late = airWeatherSnapshot { persistAirWeather(late) }
        }
        guard let snapshot = airWeatherSnapshot else {
            WakeLog.debug(.workout, "air weather skipped — none cached")
            return
        }
        do {
            try await builder.addMetadata(snapshot.healthKitMetadata)
            WakeLog.debug(.workout, "air weather metadata attached")
        } catch {
            WakeLog.error(.workout, "air weather metadata: \(error.localizedDescription)")
        }
    }

    func recordFinishedHkRide(endedAt: Date) {
        guard let start = hkRideStartedAt else { return }
        let meters = liveSetTracker.lastSetMeters
        let duration = liveSetTracker.lastSetDuration > 0
            ? liveSetTracker.lastSetDuration
            : max(0, endedAt.timeIntervalSince(start))
        if meters > 0 {
            hkRides.append(
                HKRideMetric(startedAt: start, endedAt: endedAt, meters: meters, duration: duration)
            )
        }
        hkRideStartedAt = nil
    }

    func addRideDistanceSamples(to builder: HKLiveWorkoutBuilder) async throws {
        var samples: [HKSample] = []
        for set in hkRides where set.meters > 0 {
            samples.append(
                HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: set.meters),
                    start: set.startedAt,
                    end: set.endedAt
                )
            )
        }
        try await addSamples(samples, to: builder)
        if !samples.isEmpty {
            WakeLog.debug(.workout, "added \(samples.count) set distance HK windows")
        }
    }

    /// Interval distance + speed on set HKWorkoutActivity rows (not cable-park laps).
    func attachRideMetricsToActivities(_ builder: HKLiveWorkoutBuilder) async throws {
        for activity in builder.workoutActivities {
            let code = activity.metadata?[WorkoutMetadataKeys.detectionCode] as? String
            guard code == DetectionCodes.riding else { continue }
            guard let set = hkRides.first(where: {
                abs($0.startedAt.timeIntervalSince(activity.startDate)) < 1
            }) else { continue }

            var metadata: [String: Any] = [
                WorkoutMetadataKeys.setDistanceMeters: set.meters
            ]
            if let speedMps = LocationSpeedStats.averageSpeedMetersPerSecond(
                distanceMeters: set.meters,
                duration: set.duration
            ) {
                metadata[HKMetadataKeyAverageSpeed] = HKQuantity(
                    unit: .meter().unitDivided(by: .second()),
                    doubleValue: speedMps
                )
            }
            try await builder.updateActivity(uuid: activity.uuid, adding: metadata)
        }
    }

    func addWaterTemperatureSamples(to builder: HKLiveWorkoutBuilder) async throws {
        guard !sessionWaterSamples.isEmpty else { return }
        let samples = sessionWaterSamples.map { sample in
            HKQuantitySample(
                type: waterTemperatureType,
                quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: sample.celsius),
                start: sample.timestamp,
                end: sample.timestamp
            )
        }
        try await addSamples(samples, to: builder)
        WakeLog.debug(.workout, "added \(samples.count) waterTemperature samples")
    }

    func addSamples(_ samples: [HKSample], to builder: HKLiveWorkoutBuilder) async throws {
        guard !samples.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SessionStoreError.ioFailure("Failed to add workout samples"))
                }
            }
        }
    }

    func insertRouteLocations(_ locations: [CLLocation]) async {
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

}
