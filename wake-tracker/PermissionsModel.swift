import Foundation
import HealthKit
import CoreLocation
import CoreMotion
import Observation

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
    }

    func requestAll() async {
        lastError = nil
        locationManager.requestWhenInUseAuthorization()
        refresh()

        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType(),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: read)
            healthStatus = "authorized (read)"
        } catch {
            lastError = error.localizedDescription
            healthStatus = "error"
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
