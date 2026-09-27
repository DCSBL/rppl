import CoreLocation
import MapKit
import Observation
import RpplCore
import SwiftUI
import UIKit
import WeatherKit

/// Whether the Nearby sort can use a location fix right now.
enum ParksLocationAvailability: Equatable {
    case available
    case notDetermined
    case denied
    case servicesDisabled
}

/// One-shot iPhone location fix for "nearby" sorting. Denied or unavailable simply means no distances.
///
/// `refresh()` is the only entry point that requests a fix — callers trigger it on view appear and on
/// return from background, never continuously, so the Nearby sort doesn't reorder mid-use.
@Observable
@MainActor
final class ParksLocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: ParkCoordinate?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var servicesEnabled = true
    private let manager = CLLocationManager()

    var availability: ParksLocationAvailability {
        guard servicesEnabled else { return .servicesDisabled }
        switch authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedWhenInUse, .authorizedAlways: return .available
        @unknown default: return .notDetermined
        }
    }

    override init() {
        authorizationStatus = .notDetermined
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func refresh() {
        authorizationStatus = manager.authorizationStatus
        servicesEnabled = CLLocationManager.locationServicesEnabled()
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
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
    static let shared = ParkFavorites()

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

    static var appSettingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }
}

/// Shown in place of the Nearby-sorted list when there's no location fix to sort by.
struct ParksLocationNeededCard: View {
    let availability: ParksLocationAvailability
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.rpplText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.rpplMuted)
            if let buttonTitle {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.rpplAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .logbookCardChrome()
    }

    private var title: String {
        switch availability {
        case .servicesDisabled: String(localized: "Location Services is off")
        case .notDetermined, .denied, .available: String(localized: "Location needed")
        }
    }

    private var message: String {
        switch availability {
        case .notDetermined:
            String(localized: "Allow location access to sort parks by distance.")
        case .denied:
            String(localized: "Location access was denied. Turn it on in Settings to sort parks by distance.")
        case .servicesDisabled:
            String(
                localized: "Turn on Location Services in Settings > Privacy & Security to sort parks by distance."
            )
        case .available:
            ""
        }
    }

    private var buttonTitle: String? {
        switch availability {
        case .notDetermined: String(localized: "Grant Access")
        case .denied: String(localized: "Open Settings")
        case .servicesDisabled, .available: nil
        }
    }

    private var buttonAction: () -> Void {
        switch availability {
        case .notDetermined: onRequestAccess
        case .denied: onOpenSettings
        case .servicesDisabled, .available: {}
        }
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
        return tokens.map { dayName($0) }.joined(separator: ", ")
    }

    /// Slang: a cable that goes round is "full size"; a 2-point cable is "2.0".
    static func cableType(_ direction: ParkCableDirection?) -> String? {
        switch direction {
        case .some(.clockwise), .some(.counterClockwise): String(localized: "Full size")
        case .some(.twoD): String(localized: "2.0")
        case .some(let other): other.rawValue
        case .none: nil
        }
    }

    /// Travel direction of a loop cable; 2.0 cables have none.
    static func loopDirection(_ direction: ParkCableDirection?) -> String? {
        switch direction {
        case .some(.clockwise): String(localized: "Clockwise")
        case .some(.counterClockwise): String(localized: "Counter-clockwise")
        default: nil
        }
    }

    /// "1 hour or 2 hours" from booking durations in minutes.
    static func bookingDurations(_ minutes: [Int]?) -> String? {
        guard let minutes, !minutes.isEmpty else { return nil }
        return minutes
            .map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)) }
            .formatted(.list(type: .or))
    }

    static func monthName(_ month: Int?) -> String {
        guard let month, (1...12).contains(month) else { return String(localized: "All year") }
        return Calendar.current.standaloneMonthSymbols[month - 1].capitalized
    }

    static func openFromTo(_ window: ParkTimeWindow) -> String {
        let from = time(window.startMinute)
        let to = time(window.endMinute)
        return String(localized: "Open from \(from) to \(to)")
    }

    /// YAML labels often repeat the month ("September"); those add nothing next to a month heading.
    static func isMonthLabel(_ label: String) -> Bool {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US")
        return english.standaloneMonthSymbols.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    static func currentMonth(in park: Park, now: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park.resolvedTimeZone
        return calendar.component(.month, from: now)
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

struct ParkWeather: Equatable, Sendable {
    var temperatureCelsius: Double
    var windKmh: Double
    /// Meteorological "wind from" bearing, degrees clockwise from true north.
    var windDirectionDegrees: Double
    var isHighUV: Bool
    var rainForecast: RainForecast
    var markLightURL: URL?
    var markDarkURL: URL?
    var legalURL: URL?
}

/// Current air temperature and wind at a park via WeatherKit. Failures just hide the weather row.
///
/// Shared (`.shared`) rather than per-view so the success cache and failure backoff below actually
/// apply across park-detail navigations and geofence arrivals, instead of resetting every time a
/// caller makes its own instance.
@Observable
@MainActor
final class ParksWeatherProvider {
    static let shared = ParksWeatherProvider()

    private var cache: [String: (date: Date, weather: ParkWeather)] = [:]
    private var lastFailure: [String: Date] = [:]
    private static let maxAge: TimeInterval = 15 * 60
    /// Skip re-hitting WeatherKit for a park that just failed (e.g. a provisioning/auth outage) —
    /// without this, every screen visit or geofence arrival retried an already-failing request.
    private static let failureBackoff: TimeInterval = 5 * 60
    private static let fetchTimeout: TimeInterval = 8

    func weather(for park: Park) async -> ParkWeather? {
        if let hit = cache[park.id], Date().timeIntervalSince(hit.date) < Self.maxAge {
            return hit.weather
        }
        if let failedAt = lastFailure[park.id], Date().timeIntervalSince(failedAt) < Self.failureBackoff {
            return nil
        }
        let location = CLLocation(latitude: park.location.lat, longitude: park.location.lon)
        do {
            let result = try await Self.withTimeout(Self.fetchTimeout) {
                let service = WeatherService.shared
                let (current, hourly) = try await service.weather(for: location, including: .current, .hourly)
                let attribution = try? await service.attribution
                let rainChances = hourly.map { HourlyRainChance(date: $0.date, chance: $0.precipitationChance) }
                return ParkWeather(
                    temperatureCelsius: current.temperature.converted(to: .celsius).value,
                    windKmh: current.wind.speed.converted(to: .kilometersPerHour).value,
                    windDirectionDegrees: current.wind.direction.converted(to: .degrees).value,
                    isHighUV: current.uvIndex.category >= .high,
                    rainForecast: RainForecastPlanner.forecast(from: rainChances),
                    markLightURL: attribution?.combinedMarkLightURL,
                    markDarkURL: attribution?.combinedMarkDarkURL,
                    legalURL: attribution?.legalPageURL
                )
            }
            cache[park.id] = (Date(), result)
            lastFailure[park.id] = nil
            return result
        } catch is ParksWeatherTimeoutError {
            WakeLog.debug(.ui, "park weather: timed out")
            lastFailure[park.id] = Date()
            return nil
        } catch {
            WakeLog.error(.ui, "park weather: \(error)")
            lastFailure[park.id] = Date()
            return nil
        }
    }

    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ParksWeatherTimeoutError()
            }
            guard let result = try await group.next() else {
                throw ParksWeatherTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct ParksWeatherTimeoutError: Error {}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

struct ParkChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Color.rpplText
    var fill: Color = Color.rpplFill

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fill, in: Capsule())
    }
}

extension ParkOpenStatus {
    var badgeText: String {
        switch self {
        case .openToday: String(localized: "Open today")
        case .opensTomorrow: String(localized: "Opens tomorrow")
        case .closed: String(localized: "Closed")
        case .unknown: String(localized: "Opening hours unknown")
        }
    }

    var badgeColor: Color {
        switch self {
        case .openToday: .green
        case .opensTomorrow: .yellow
        case .closed: .red
        case .unknown: .gray
        }
    }
}

enum ParkOriginBadge {
    static func text(for entry: ParkEntry?) -> String? {
        guard let entry else { return nil }
        if entry.hasNewerBundled { return String(localized: "Update available") }
        switch entry.origin {
        case .bundled: return nil
        case .custom: return String(localized: "Custom")
        case .edited: return String(localized: "Edited")
        }
    }
}

/// Park detail wired to the shared favorites and park store; used from the Parks tab and the session page.
struct ParkDetailContainer: View {
    let park: Park
    @State private var favorites = ParkFavorites.shared
    @State private var store = ParkStore.shared

    var body: some View {
        let entry = store.entry(id: park.id)
        ParkDetailView(
            park: entry?.park ?? park,
            entry: entry,
            isFavorite: favorites.contains(park.id),
            onToggleFavorite: { favorites.toggle(park.id) }
        )
    }
}
