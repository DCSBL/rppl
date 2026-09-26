import CoreLocation
import Foundation
import Observation
import RpplCore
import UserNotifications

/// Opt-in, fully local "welcome to <park>" notification: geofences the favorite + nearest parks
/// with small always-on-device regions, and fires a one-shot local notification on confirmed
/// arrival. No background continuous tracking, no server — CoreLocation delivers region
/// enter/exit events to the app without Rppl polling location itself.
///
/// Default off. Turning it on requests Always location + notification permission; either denial
/// turns it back off with an explanation instead of silently degrading.
@Observable
@MainActor
final class ParkArrivalController: NSObject {
    static let shared = ParkArrivalController()

    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: CLAuthorizationStatus
    /// Set when the user turned the feature on but Always location or notifications got denied —
    /// the Settings toggle reads this to show why it snapped back off.
    private(set) var permissionDenied = false
    /// Tapped-notification hand-off for `ContentView` to open that park (and, first time, the
    /// explainer sheet on how this notification works).
    private(set) var pendingArrival: PendingParkArrival?

    private let locationManager = CLLocationManager()
    private var lastFix: ParkCoordinate?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    struct PendingParkArrival: Equatable {
        var parkID: String
        var isFirstTime: Bool
    }

    private override init() {
        isEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.parkArrivalNotificationsEnabled)
        authorizationStatus = .notDetermined
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
        UNUserNotificationCenter.current().delegate = self
    }

    /// Turns the feature on: requests Always location (upgrading from When In Use if needed) and
    /// notification permission. Any denial reverts the toggle and sets `permissionDenied`.
    func enable() async {
        permissionDenied = false
        if locationManager.authorizationStatus == .notDetermined {
            await requestLocationAuthorization(always: false)
        }
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            await requestLocationAuthorization(always: true)
        }
        guard locationManager.authorizationStatus == .authorizedAlways else {
            finishEnable(granted: false)
            return
        }
        guard await requestNotificationPermission() else {
            finishEnable(granted: false)
            return
        }
        finishEnable(granted: true)
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: AppSettingsKey.parkArrivalNotificationsEnabled)
        isEnabled = false
        permissionDenied = false
        stopMonitoringAll()
    }

    /// Re-derives the monitored region set from the current favorites + nearest parks. Called on
    /// app foreground and right after enabling — never on a background timer.
    func refreshMonitoredRegionsIfEnabled() {
        guard isEnabled, locationManager.authorizationStatus == .authorizedAlways else { return }
        if ParkStore.shared.entries.isEmpty {
            ParkStore.shared.reload()
        }
        applyMonitoredRegions(currentLocation: lastFix)
        locationManager.requestLocation()
    }

    func consumePendingArrival() {
        pendingArrival = nil
    }

    private func finishEnable(granted: Bool) {
        guard granted else {
            UserDefaults.standard.set(false, forKey: AppSettingsKey.parkArrivalNotificationsEnabled)
            isEnabled = false
            permissionDenied = true
            stopMonitoringAll()
            WakeLog.debug(.permissions, "park arrival: enable denied")
            return
        }
        UserDefaults.standard.set(true, forKey: AppSettingsKey.parkArrivalNotificationsEnabled)
        isEnabled = true
        refreshMonitoredRegionsIfEnabled()
        WakeLog.debug(.permissions, "park arrival: enabled")
    }

    private func requestLocationAuthorization(always: Bool) async {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            if always {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    private func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    private func applyMonitoredRegions(currentLocation: ParkCoordinate?) {
        let parks = ParkStore.shared.entries.map(\.park)
        let favoriteIDs = ParkFavorites.shared.ids
        let selectedIDs = Set(
            ParkArrivalPlanner.selectMonitoredParkIDs(
                favoriteIDs: favoriteIDs, allParks: parks, currentLocation: currentLocation
            )
        )

        for region in locationManager.monitoredRegions where !selectedIDs.contains(region.identifier) {
            locationManager.stopMonitoring(for: region)
        }
        let alreadyMonitored = Set(locationManager.monitoredRegions.map(\.identifier))
        for park in parks where selectedIDs.contains(park.id) && !alreadyMonitored.contains(park.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon),
                radius: ParkArrivalPlanner.regionRadiusMeters,
                identifier: park.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
        }
    }

    private func stopMonitoringAll() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func handleArrival(parkID: String) async {
        guard isEnabled, let park = ParkStore.shared.entry(id: parkID)?.park else { return }
        guard ParkArrivalPlanner.shouldNotify(lastNotifiedAt: Self.lastNotifiedDate(parkID: parkID)) else { return }
        let weather = await ParksWeatherProvider().weather(for: park)
        await scheduleNotification(for: park, weather: weather)
        Self.setLastNotifiedDate(parkID: parkID, date: Date())
    }

    private func scheduleNotification(for park: Park, weather: ParkWeather?) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Welcome to \(park.name)")
        content.body = Self.notificationBody(park: park, weather: weather)
        content.sound = .default
        content.userInfo = ["parkID": park.id]
        let request = UNNotificationRequest(
            identifier: "park-arrival.\(park.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func notificationBody(park: Park, weather: ParkWeather?) -> String {
        var parts: [String] = []
        if let weather {
            let temperature = Int(weather.temperatureCelsius.rounded())
            let wind = Int(weather.windKmh.rounded())
            parts.append(String(localized: "\(temperature)°C, wind \(wind) km/h"))
        }
        parts.append(park.openStatus().badgeText)
        return parts.joined(separator: " · ")
    }

    private static func lastNotifiedDate(parkID: String) -> Date? {
        let dict = UserDefaults.standard.dictionary(forKey: AppSettingsKey.parkArrivalLastNotified) as? [String: Double]
        guard let value = dict?[parkID] else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private static func setLastNotifiedDate(parkID: String, date: Date) {
        var dict = UserDefaults.standard.dictionary(forKey: AppSettingsKey.parkArrivalLastNotified) as? [String: Double] ?? [:]
        dict[parkID] = date.timeIntervalSince1970
        UserDefaults.standard.set(dict, forKey: AppSettingsKey.parkArrivalLastNotified)
    }
}

extension ParkArrivalController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let fix = ParkCoordinate(lat: last.coordinate.latitude, lon: last.coordinate.longitude)
        Task { @MainActor in
            lastFix = fix
            guard isEnabled else { return }
            applyMonitoredRegions(currentLocation: fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        WakeLog.debug(.permissions, "park arrival location: \(error.localizedDescription)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in await handleArrival(parkID: region.identifier) }
    }
}

extension ParkArrivalController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let parkID = response.notification.request.content.userInfo["parkID"] as? String else { return }
        await MainActor.run {
            let isFirstTime = !UserDefaults.standard.bool(forKey: AppSettingsKey.didShowParkArrivalExplainer)
            if isFirstTime {
                UserDefaults.standard.set(true, forKey: AppSettingsKey.didShowParkArrivalExplainer)
            }
            pendingArrival = PendingParkArrival(parkID: parkID, isFirstTime: isFirstTime)
        }
    }
}
