import CoreLocation
import Foundation
import MapKit
import RpplCore

/// Reverse-geocodes **session GPS samples** (Watch JSONL) to a city name.
///
/// Does **not** use `CLLocationManager`, live iPhone GPS, or Location permission.
/// A denied/delayed Location prompt must never affect city naming or WC sync.
@MainActor
final class SessionCityResolver {
    static let shared = SessionCityResolver()

    private var cache: [String: String] = [:]

    private init() {}

    func cityName(sessionId: String, locations: [LocationSample]) async -> String? {
        if let cached = cache[sessionId] {
            return cached
        }
        guard let coordinate = SessionLocationHelpers.representativeCoordinate(from: locations) else {
            return nil
        }

        // Coordinate comes from imported Watch track points — not a phone location fix.
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            guard let city = Self.city(from: mapItems.first) else { return nil }
            cache[sessionId] = city
            WakeLog.debug(.ui, "geocoded \(sessionId.prefix(8))… → \(city)")
            return city
        } catch {
            WakeLog.debug(.ui, "reverse geocode \(sessionId.prefix(8))…: \(error.localizedDescription)")
            return nil
        }
    }

    func invalidate(sessionId: String) {
        cache.removeValue(forKey: sessionId)
    }

    /// Seed RAM cache from phone-only derived `cityName` without geocoding.
    func remember(sessionId: String, cityName: String) {
        cache[sessionId] = cityName
    }

    /// City only; ignore the item's `name` (often a venue) and country/admin fields.
    private static func city(from mapItem: MKMapItem?) -> String? {
        guard let mapItem else { return nil }
        let locality = mapItem.addressRepresentations?.cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality, !locality.isEmpty else { return nil }
        return locality
    }
}
