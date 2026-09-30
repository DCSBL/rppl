#if PARK_ARRIVAL_NOTIFICATIONS
import CoreLocation
import Foundation
import Observation
import RpplCore
import UserNotifications

/// Opt-in, fully local "welcome to <park>" notification: geofences the favorite + nearest parks
/// with small on-device regions, and fires a one-shot local notification on confirmed arrival.
/// No continuous tracking, no server — CoreLocation delivers region enter/exit events to the app
/// without Rppl polling location itself.
///
/// Deliberately asks for **When In Use** location only, not Always: simpler ask, easier to reason
/// about for users, and it's the same permission Rppl already requests for map/distance features.
/// The trade-off is real and stated in the Settings footer: region events only reach a When In Use
/// app while Rppl is still running in the foreground or background — not once iOS has fully
/// suspended/terminated it after a while unused, and never after a manual force-quit (that stops
/// delivery regardless of authorization level). Reopening Rppl re-arms monitoring.
///
/// Default off. Turning it on requests location + notification permission; either denial turns it
/// back off with an explanation instead of silently degrading.
@Observable
@MainActor
final class ParkArrivalController: NSObject {
    static let shared = ParkArrivalController()

    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: CLAuthorizationStatus
    /// Set when the user turned the feature on but location or notifications got denied —
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

    /// Turns the feature on: requests When In Use location + notification permission. Any denial
    /// reverts the toggle and sets `permissionDenied`.
    func enable() async {
        permissionDenied = false
        if authorizationStatus == .notDetermined {
            await requestLocationAuthorization()
        }
        guard Self.isAuthorizedForMonitoring(authorizationStatus) else {
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
        guard isEnabled, Self.isAuthorizedForMonitoring(authorizationStatus) else { return }
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

    private func requestLocationAuthorization() async {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private static func isAuthorizedForMonitoring(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
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
        let weather = await ParksWeatherProvider.shared.weather(for: park)
        let waterTemperature = await ParkWaterTemperatureProvider.shared.temperature(for: park)
        do {
            try await scheduleNotification(
                for: park, weather: weather, waterTemperature: waterTemperature, trigger: nil, identifierSuffix: ""
            )
            Self.setLastNotifiedDate(parkID: parkID, date: Date())
        } catch {
            WakeLog.error(.permissions, "park arrival notification for \(parkID): \(error.localizedDescription)")
        }
    }

    /// Debug screen only. The real reflection of what CoreLocation is actually watching right now
    /// (not just what Rppl intended to monitor) — sorted for stable list ordering.
    var monitoredParkIDs: [String] {
        locationManager.monitoredRegions.map(\.identifier).sorted()
    }

    enum TestNotificationOutcome: Equatable {
        case success
        case failure(String)
    }

    /// Debug screen only: fires a real local notification for `parkID` after `delay`, as if a
    /// geofence had just fired for it. Ignores `isEnabled` / cooldown; still requests notification
    /// permission if not yet granted. Surfaces the actual `add(_:)` failure instead of swallowing it.
    func sendTestArrivalNotification(parkID: String, delay: TimeInterval) async -> TestNotificationOutcome {
        guard await requestNotificationPermission() else {
            return .failure(String(localized: "Notification permission is not granted."))
        }
        if ParkStore.shared.entries.isEmpty {
            ParkStore.shared.reload()
        }
        guard let park = ParkStore.shared.entry(id: parkID)?.park else {
            return .failure(String(localized: "Unknown park."))
        }
        let weather = await ParksWeatherProvider.shared.weather(for: park)
        let waterTemperature = await ParkWaterTemperatureProvider.shared.temperature(for: park)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        do {
            try await scheduleNotification(
                for: park, weather: weather, waterTemperature: waterTemperature, trigger: trigger, identifierSuffix: "-test"
            )
            return .success
        } catch {
            WakeLog.error(.permissions, "park arrival test notification: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    /// Debug screen only: fires immediately, with no park/weather involved, to isolate whether
    /// local notifications work on this device/build at all.
    func sendImmediateDiagnosticNotification() async -> TestNotificationOutcome {
        guard await requestNotificationPermission() else {
            return .failure(String(localized: "Notification permission is not granted."))
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rppl test notification")
        content.body = String(localized: "If you see this, local notifications work on this device.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "park-arrival.diagnostic", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Debug screen only: a human-readable snapshot of the current notification permission.
    func notificationSettingsSummary() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return String(localized: "Not determined")
        case .denied:
            return String(localized: "Denied")
        case .authorized:
            let alerts = settings.alertSetting == .enabled
            let sound = settings.soundSetting == .enabled
            return String(localized: "Authorized (alerts \(alerts ? "on" : "off"), sound \(sound ? "on" : "off"))")
        case .provisional:
            return String(localized: "Provisional (quiet delivery only)")
        case .ephemeral:
            return String(localized: "Ephemeral (App Clip)")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    private func scheduleNotification(
        for park: Park,
        weather: ParkWeather?,
        waterTemperature: ParkWaterTemperature?,
        trigger: UNNotificationTrigger?,
        identifierSuffix: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Welcome to \(park.name)")
        content.body = Self.notificationBody(park: park, weather: weather, waterTemperature: waterTemperature)
        content.sound = .default
        // Relevant right now, not later: breaks through Focus and skips the scheduled summary.
        // The only notification type Rppl sends today, so this doesn't crowd out anything else.
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["parkID": park.id]
        let request = UNNotificationRequest(
            identifier: "park-arrival.\(park.id)\(identifierSuffix)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private static func notificationBody(park: Park, weather: ParkWeather?, waterTemperature: ParkWaterTemperature?) -> String {
        var parts: [String] = []
        if let weather {
            let temperature = Int(weather.temperatureCelsius.rounded())
            let wind = Int(weather.windKmh.rounded())
            parts.append(String(localized: "\(temperature)°C, wind \(wind) km/h"))
        }
        if let waterTemperature {
            let temperature = Int(waterTemperature.celsius.rounded())
            parts.append(String(localized: "water ~\(temperature)°C"))
        }
        parts.append(openingHoursText(for: park))
        parts.append(String(localized: "Read more about this park."))
        return parts.joined(separator: " · ")
    }

    private static func openingHoursText(for park: Park) -> String {
        let day = park.schedule()
        guard day.isScheduleKnown else { return String(localized: "Opening hours unknown") }
        guard day.isOpen, !day.windows.isEmpty else { return park.openStatus().badgeText }
        return day.windows.map(ParkFormatting.openFromTo).joined(separator: ", ")
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

    /// UIKit requires this completion handler to be called on the main thread and asserts otherwise
    /// ("Call must be made on main thread" in `_performBlockAfterCATransactionCommitSynchronizes:`).
    /// The `async` variant can't guarantee that: as a `nonisolated` witness, Swift's Objective-C
    /// bridging thunk runs the body — and then calls UIKit's completion — on a background executor,
    /// which crashed every notification tap. The completion-handler variant makes the hop explicit.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let parkID = response.notification.request.content.userInfo["parkID"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let parkID { self.handleNotificationTap(parkID: parkID) }
            }
            completionHandler()
        }
    }

    private func handleNotificationTap(parkID: String) {
        let isFirstTime = !UserDefaults.standard.bool(forKey: AppSettingsKey.didShowParkArrivalExplainer)
        if isFirstTime {
            UserDefaults.standard.set(true, forKey: AppSettingsKey.didShowParkArrivalExplainer)
        }
        pendingArrival = PendingParkArrival(parkID: parkID, isFirstTime: isFirstTime)
    }
}
#endif
