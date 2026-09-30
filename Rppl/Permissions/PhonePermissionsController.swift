import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import RpplCore
import Observation
#if PARK_ARRIVAL_NOTIFICATIONS
import UserNotifications
#endif

/// Reads / requests iPhone companion permissions. Never gates WatchConnectivity sync.
@Observable
@MainActor
final class PhonePermissionsController: NSObject {
    static let shared = PhonePermissionsController()

    var locationPermission: WatchPermissionState = .notDetermined
    var healthPermission: WatchPermissionState = .notDetermined
    var motionPermission: WatchPermissionState = .notDetermined
    /// Not a `WatchPermissionKind` case — notifications aren't part of the Watch recording gate
    /// this enum was built for, so this row is added separately in `PhonePermissionsListSection`.
    /// Stays outside `#if PARK_ARRIVAL_NOTIFICATIONS`: `@Observable` skips members inside `#if`
    /// blocks, which would silently stop tracking it in the builds that show the row.
    var notificationPermission: WatchPermissionState = .notDetermined

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
        #if PARK_ARRIVAL_NOTIFICATIONS
        Task { await refreshNotifications() }
        #endif

        if HKHealthStore.isHealthDataAvailable() {
            refreshHealth()
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

    /// Read-only access: `authorizationStatus(for:)` reports *sharing* only and reads as denied
    /// (red x) even when the user allowed reads, worse on iOS 27. Read grants are private, so
    /// "sheet already shown" (`.unnecessary`) is the best signal available.
    private func refreshHealth() {
        healthStore.getRequestStatusForAuthorization(
            toShare: [], read: [workoutType, heartRateType]
        ) { [weak self] status, _ in
            guard let self else { return }
            let state: WatchPermissionState = switch status {
            case .unnecessary: .authorized
            default: .notDetermined
            }
            Task { @MainActor in self.healthPermission = state }
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
            await requestHealth(force: true)
        }
        if motionPermission == .notDetermined {
            await requestMotion(force: true)
        }
        refresh()
        WakeLog.debug(.permissions, "post-sync permission asks done")
    }

    func request(_ kind: WatchPermissionKind, force: Bool = false) async {
        switch kind {
        case .location: await requestLocation()
        case .health: await requestHealth(force: force)
        case .motion: await requestMotion(force: force)
        }
    }

    private func requestLocation() async {
        // Companion display only — never used for city/spot naming (session GPS + geocoder).
        locationManager.requestWhenInUseAuthorization()
        refresh()
    }

    private func requestHealth(force: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthPermission = .unavailable
            return
        }
        refresh()
        if !force, healthPermission != .notDetermined {
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

    private func requestMotion(force: Bool) async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionPermission = .unavailable
            return
        }
        let status = CMMotionActivityManager.authorizationStatus()
        if !force, status != .notDetermined {
            refresh()
            return
        }
        // Motion has no re-prompt API after deny; querying still refreshes status when possible.
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

    #if PARK_ARRIVAL_NOTIFICATIONS
    private func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = Self.notificationState(settings.authorizationStatus)
    }

    /// Only prompts while undetermined — notifications have no re-prompt API after deny, same as
    /// Motion. Used by the standalone Notifications row in `PhonePermissionsListSection`.
    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await refreshNotifications()
    }

    private static func notificationState(_ status: UNAuthorizationStatus) -> WatchPermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }
    #endif
}

extension PhonePermissionsController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refresh()
        }
    }
}
