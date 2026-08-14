import CoreLocation
import Foundation
import RpplCore

/// Reverse-geocodes session GPS to a city name (locality only — no POI, country, or facility).
@MainActor
final class SessionCityResolver {
    static let shared = SessionCityResolver()

    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]

    private init() {}

    func cityName(sessionId: String, locations: [LocationSample]) async -> String? {
        if let cached = cache[sessionId] {
            return cached
        }
        guard let coordinate = SessionLocationHelpers.representativeCoordinate(from: locations) else {
            return nil
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let city = Self.city(from: placemarks.first) else { return nil }
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

    /// `locality` is the city; ignore `name` (often a venue) and country/admin fields.
    private static func city(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality, !locality.isEmpty else { return nil }
        return locality
    }
}
