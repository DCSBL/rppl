import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import RpplCore
import Observation

/// Reads / requests iPhone companion permissions. Never gates WatchConnectivity sync.
@Observable
@MainActor
final class PhonePermissionsController: NSObject {
    static let shared = PhonePermissionsController()

    var locationPermission: WatchPermissionState = .notDetermined
    var healthPermission: WatchPermissionState = .notDetermined
    var motionPermission: WatchPermissionState = .notDetermined

    var permissionStates: [WatchPermissionKind: WatchPermissionState] {
        [
            .location: locationPermission,
            .health: healthPermission,
            .motion: motionPermission
        ]
    }

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!

    private override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    func refresh() {
        locationPermission = Self.locationState(locationManager.authorizationStatus)

        if HKHealthStore.isHealthDataAvailable() {
            switch healthStore.authorizationStatus(for: workoutType) {
            case .notDetermined:
                healthPermission = .notDetermined
            case .sharingDenied:
                healthPermission = .denied
            case .sharingAuthorized:
                healthPermission = .authorized
            @unknown default:
                healthPermission = .notDetermined
            }
        } else {
            healthPermission = .unavailable
        }

        if CMMotionActivityManager.isActivityAvailable() {
            switch CMMotionActivityManager.authorizationStatus() {
            case .notDetermined:
                motionPermission = .notDetermined
            case .restricted, .denied:
                motionPermission = .denied
            case .authorized:
                motionPermission = .authorized
            @unknown default:
                motionPermission = .notDetermined
            }
        } else {
            motionPermission = .unavailable
        }
    }

    /// After first successful Watch→phone import: ask only undetermined sheets once.
    /// Denial must not affect WC import/ack or session city geocoding.
    func requestAfterFirstSyncIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettingsKey.didImportSessionFromWatch) else { return }
        guard !defaults.bool(forKey: AppSettingsKey.didRequestPostSyncPermissions) else { return }
        defaults.set(true, forKey: AppSettingsKey.didRequestPostSyncPermissions)
        WakeLog.debug(.permissions, "post-sync permission asks begin")
        refresh()
        if locationPermission == .notDetermined {
            await requestLocation()
        }
        if healthPermission == .notDetermined {
            await requestHealth()
        }
        if motionPermission == .notDetermined {
            await requestMotion()
        }
        refresh()
        WakeLog.debug(.permissions, "post-sync permission asks done")
    }

    func request(_ kind: WatchPermissionKind) async {
        switch kind {
        case .location: await requestLocation()
        case .health: await requestHealth()
        case .motion: await requestMotion()
        }
    }

    private func requestLocation() async {
        // Companion display only — never used for city/spot naming (session GPS + geocoder).
        locationManager.requestWhenInUseAuthorization()
        refresh()
    }

    private func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthPermission = .unavailable
            return
        }
        // Read-oriented ask. Phone does not save workouts; denial must not block WC sync.
        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: [workoutType, heartRateType]
            )
        } catch {
            WakeLog.error(.permissions, "Health auth: \(error.localizedDescription)")
        }
        refresh()
    }

    private func requestMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionPermission = .unavailable
            return
        }
        guard CMMotionActivityManager.authorizationStatus() == .notDetermined else {
            refresh()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let manager = CMMotionActivityManager()
            let now = Date()
            manager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in
                continuation.resume()
            }
        }
        refresh()
    }

    private static func locationState(_ status: CLAuthorizationStatus) -> WatchPermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .notDetermined
        }
    }
}

extension PhonePermissionsController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refresh()
        }
    }
}
