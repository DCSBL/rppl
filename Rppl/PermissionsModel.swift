import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import Observation
import RpplCore

@Observable
@MainActor
final class PermissionsModel {
    var healthStatus = "unknown"
    var locationStatus = "unknown"
    var motionStatus = "unknown"
    var lastError: String?

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    func refresh() {
        locationStatus = Self.locationLabel(locationManager.authorizationStatus)
        motionStatus = CMMotionActivityManager.isActivityAvailable() ? "available" : "unavailable"
        healthStatus = HKHealthStore.isHealthDataAvailable() ? "available" : "unavailable"
        WakeLog.debug(
            .permissions,
            "refresh health=\(healthStatus) loc=\(locationStatus) motion=\(motionStatus)"
        )
    }

    func requestAll() async {
        WakeLog.debug(.permissions, "requestAll begin")
        lastError = nil
        locationManager.requestWhenInUseAuthorization()
        refresh()

        guard HKHealthStore.isHealthDataAvailable() else {
            WakeLog.debug(.permissions, "Health unavailable")
            return
        }
        let workout = HKObjectType.workoutType()
        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let basal = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
        let distance = HKObjectType.quantityType(forIdentifier: .distancePaddleSports)!
        let route = HKSeriesType.workoutRoute()
        let read: Set<HKObjectType> = [heartRate, energy, basal, workout, distance]
        // Mirror Watch share types so Health prompts stay consistent across the pair.
        let share: Set<HKSampleType> = [workout, heartRate, energy, basal, distance, route]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            switch healthStore.authorizationStatus(for: workout) {
            case .sharingAuthorized:
                healthStatus = "workout: authorized"
            case .sharingDenied:
                healthStatus = "workout: denied"
            case .notDetermined:
                healthStatus = "workout: notDetermined"
            @unknown default:
                healthStatus = "workout: unknown"
            }
            WakeLog.debug(.permissions, "Health auth result \(healthStatus)")
        } catch {
            lastError = error.localizedDescription
            healthStatus = "error"
            WakeLog.error(.permissions, "Health auth: \(error.localizedDescription)")
        }
        refresh()
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
}
