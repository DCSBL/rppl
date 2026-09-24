import CoreLocation
import MapKit
import Observation
import RpplCore
import SwiftUI

/// One-shot iPhone location fix for "nearby" sorting. Denied or unavailable simply means no distances.
@Observable
@MainActor
final class ParksLocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: ParkCoordinate?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.start() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let fix = ParkCoordinate(lat: last.coordinate.latitude, lon: last.coordinate.longitude)
        Task { @MainActor in self.coordinate = fix }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        WakeLog.debug(.ui, "parks location: \(error.localizedDescription)")
    }
}

@Observable
@MainActor
final class ParkFavorites {
    private static let key = "rppl.favoriteParkIDs"
    private(set) var ids: Set<String>

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if !ids.insert(id).inserted { ids.remove(id) }
        UserDefaults.standard.set(ids.sorted(), forKey: Self.key)
    }
}

enum ParkNavigation {
    /// Hands the park to Apple Maps with driving directions.
    static func openDirections(to park: Park) {
        let item = MKMapItem(
            location: CLLocation(latitude: park.location.lat, longitude: park.location.lon),
            address: nil
        )
        item.name = park.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

enum ParkFormatting {
    static func visits(_ count: Int) -> String {
        String(localized: "\(count) visits")
    }

    static func time(_ minutes: Int) -> String {
        ParkSchedule.timeText(minutes: minutes)
    }

    static func window(_ window: ParkTimeWindow) -> String {
        "\(time(window.startMinute)) – \(time(window.endMinute))"
    }

    static func slot(_ slot: ParkSlot) -> String {
        "\(slot.start) – \(slot.end)"
    }

    static func days(_ tokens: [String]?) -> String? {
        guard let tokens, !tokens.isEmpty else { return nil }
        return tokens.map(dayName).joined(separator: ", ")
    }

    static func direction(_ direction: ParkCableDirection?) -> String? {
        switch direction {
        case .some(.clockwise): String(localized: "Clockwise")
        case .some(.counterClockwise): String(localized: "Counter-clockwise")
        case .some(.twoD): String(localized: "2D")
        case .some(let other): other.rawValue
        case .none: nil
        }
    }

    private static func dayName(_ token: String) -> String {
        switch token.lowercased() {
        case "daily", "all": String(localized: "Daily")
        case "weekdays": String(localized: "Mon–Fri")
        case "weekend": String(localized: "Sat–Sun")
        case "mon": String(localized: "Mon")
        case "tue": String(localized: "Tue")
        case "wed": String(localized: "Wed")
        case "thu": String(localized: "Thu")
        case "fri": String(localized: "Fri")
        case "sat": String(localized: "Sat")
        case "sun": String(localized: "Sun")
        default: token
        }
    }
}
