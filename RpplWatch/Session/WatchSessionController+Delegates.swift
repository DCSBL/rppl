import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import RpplCore

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
            captureSessionStartCoordinate(from: sample)
            appendToLocationRing(sample)
            processLocationSample(sample)
            processDetectionTick(timestamp: loc.timestamp)
            #if RPPL_WEATHERKIT
            requestAirWeatherIfNeeded(from: loc)
            #endif
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
            if toState == .running, let continuation = workoutRunningContinuation {
                workoutRunningContinuation = nil
                continuation.resume()
            }
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
                applyWaterSubmersionState(next)
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
                applyWaterSubmersionState(next)
            }
        }
    }

    nonisolated func manager(
        _ manager: CMWaterSubmersionManager,
        didUpdate measurement: CMWaterTemperature
    ) {
        Task { @MainActor in
            let temp = measurement.temperature.converted(to: UnitTemperature.celsius).value
            considerPersistingWaterTemperature(temp)
        }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: any Error) {
        Task { @MainActor in
            WakeLog.error(.water, "submersion error: \(error.localizedDescription)")
        }
    }
}
