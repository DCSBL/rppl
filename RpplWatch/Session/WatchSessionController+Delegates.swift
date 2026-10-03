import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import RpplCore

extension WatchSessionController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard isRunning, !isProductPaused else { return }
            // Never await here: a route insert that stalls in healthd once held good fixes back
            // for minutes while poor ones went straight to detection (field session 2026-09-30).
            enqueueRouteLocations(locations)
            let dropped = locationSequencer.droppedCount
            let fresh = locationSequencer.accepted(locations) { $0.timestamp }
            if locationSequencer.droppedCount > dropped {
                WakeLog.debug(
                    .session,
                    "dropped \(locationSequencer.droppedCount - dropped) repeated/out-of-order fix(es)"
                )
            }
            for loc in fresh {
                handleLocationFix(loc)
            }
        }
    }

    /// One new fix, in time order: record, live set meters, detection.
    private func handleLocationFix(_ loc: CLLocation) {
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
        captureSessionStartCoordinate(from: sample)
        appendToLocationRing(sample)
        processLocationSample(sample)
        processDetectionFix(loc)
        requestAirWeatherIfNeeded(from: loc)
        requestWaterEstimateIfNeeded(from: loc)
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
        let sessionId = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            WakeLog.debug(.workout, "state \(Self.workoutStateName(fromState)) → \(Self.workoutStateName(toState))")
            if toState == .running, let continuation = workoutRunningContinuation {
                workoutRunningContinuation = nil
                continuation.resume()
            }
            if toState == .stopped, let continuation = workoutStoppedContinuation {
                workoutStoppedContinuation = nil
                continuation.resume(returning: date)
            }
            if WorkoutSessionLossPolicy.isUnexpectedLoss(
                isRunning: isRunning,
                isStopping: isStopping,
                isCurrentSession: self.workoutSession.map(ObjectIdentifier.init) == sessionId,
                toStateRaw: toState.rawValue
            ) {
                await handleWorkoutSessionLost(reason: "state \(Self.workoutStateName(toState))")
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionId = ObjectIdentifier(workoutSession)
        let nsError = error as NSError
        Task { @MainActor in
            errorText = error.localizedDescription
            WakeLog.error(.workout, "session failed: \(error.localizedDescription)")
            if let continuation = workoutStoppedContinuation {
                workoutStoppedContinuation = nil
                continuation.resume(returning: Date())
            }
            if WorkoutSessionLossPolicy.isUnexpectedFailure(
                isRunning: isRunning,
                isStopping: isStopping,
                isCurrentSession: self.workoutSession.map(ObjectIdentifier.init) == sessionId
            ) {
                await handleWorkoutSessionLost(reason: "failed \(nsError.domain) \(nsError.code)")
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
                activeEnergyKilocalories = value
            }
            if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
               collectedTypes.contains(basalType),
               let statistics = workoutBuilder.statistics(for: basalType),
               let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                basal = value
                basalEnergyKilocalories = value
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
                applyWaterSubmersionState(next)
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterSubmersionMeasurement
    ) {
        Task { @MainActor in
            // Depth-zone enum ≠ event `.submerged`. Map all in-water zones to the opaque
            // detection string `submerged` so water-temp persist + bout flags keep working.
            let next = Self.normalizedWaterSubmersionState(measurement.submersionState)
            if latestWaterState != next {
                applyWaterSubmersionState(next)
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterTemperature
    ) {
        Task { @MainActor in
            // Temperature only arrives while submerged; don't wait on measurement/event race.
            if latestWaterState != "submerged" {
                applyWaterSubmersionState("submerged")
            }
            let temp = measurement.temperature.converted(to: UnitTemperature.celsius).value
            considerPersistingWaterTemperature(temp)
        }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: any Error) {
        Task { @MainActor in
            let nsError = error as NSError
            WakeLog.error(
                .water,
                "submersion error: \(error.localizedDescription) "
                    + "domain=\(nsError.domain) code=\(nsError.code)"
            )
        }
    }

    /// Collapse depth zones into opaque session strings.
    static func normalizedWaterSubmersionState(_ state: CMWaterSubmersionMeasurement.DepthState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .notSubmerged:
            return "notSubmerged"
        case .submergedShallow, .submergedDeep, .approachingMaxDepth, .pastMaxDepth:
            return "submerged"
        case .sensorDepthError:
            return "unknown"
        @unknown default:
            let raw = String(describing: state)
            if raw.contains("submerged"), !raw.contains("notSubmerged") {
                return "submerged"
            }
            return raw
        }
    }
}
