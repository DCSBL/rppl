import MapKit
import RpplCore
import SwiftUI

/// Map of all parks, shown in place of the parks list: red pins with names, place search,
/// tap a pin for the park detail.
struct ParksMapView: View {
    let parks: [Park]
    /// Only read here: the blue dot appears once access was granted elsewhere (the recenter button
    /// asks). Opening the map never prompts.
    let location: ParksLocationProvider
    /// Height of the floating header above this view, so its own controls sit below it
    /// instead of hiding underneath.
    var topInset: CGFloat = 0
    /// Owned by the parent: the style-toggle/recenter buttons live in its navigation bar
    /// (see `MapScreenToolbar`), sharing this same camera so they can drive it directly.
    @Binding var position: MapCameraPosition
    /// The search field in the header above (opened with the search button, as on the list): submitting it
    /// (`placeSearchToken`) looks the text up as a place and moves there.
    var placeQuery = ""
    var placeSearchToken = 0
    /// Beside the list a tapped pin selects the park there; otherwise it pushes the detail.
    var onSelectPark: ((Park) -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.mapScreenScope) private var mapScreenScope
    @State private var selectedID: String?
    @State private var detailPark: Park?
    @State private var searchFailed = false
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var searchPin: ParksSearchPin?
    @State private var favorites = ParkFavorites.shared
    @State private var cameraDistance: CLLocationDistance = .greatestFiniteMagnitude

    /// Below this camera distance, cable traces are close enough to read; above it they're just clutter.
    private static let cableLineVisibleDistance: CLLocationDistance = 30_000

    private var showsCableLines: Bool { cameraDistance < Self.cableLineVisibleDistance }

    private var map: some View {
        Map(position: $position, selection: $selectedID, scope: mapScreenScope) {
            parkMarkers
            if showsCableLines {
                cableLines
            }
            searchPinMarker
            if location.availability == .available {
                UserAnnotation()
            }
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .onMapCameraChange(frequency: .onEnd) { context in
            cameraDistance = context.camera.distance
        }
        .mapScreenControls(scope: mapScreenScope, position: $position)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topInset)
        }
    }

    private func open(_ park: Park) {
        if let onSelectPark {
            onSelectPark(park)
        } else {
            detailPark = park
        }
    }

    var body: some View {
        map
            .onChange(of: placeSearchToken) { _, _ in
                Task { await search() }
            }
            .onChange(of: placeQuery) { _, query in
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchPin = nil }
            }
            .onChange(of: selectedID) { _, id in
                guard let id, let park = parks.first(where: { $0.id == id }) else { return }
                selectedID = nil
                open(park)
            }
            .navigationDestination(item: $detailPark) { park in
                ParkDetailContainer(park: park)
            }
            .alert(Text("No place found"), isPresented: $searchFailed) {
                Button("OK", role: .cancel) {}
            }
    }

    @MapContentBuilder
    private var parkMarkers: some MapContent {
        ForEach(parks) { park in
            let coordinate = CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
            let color = Self.pinColor(for: park)
            if favorites.contains(park.id) {
                Marker(park.name, systemImage: "star.fill", coordinate: coordinate)
                    .tint(color)
                    .tag(park.id)
            } else {
                if differentiateWithoutColor {
                    Marker(park.name, systemImage: park.openStatusDetail().badgeSymbol, coordinate: coordinate)
                        .tint(color)
                        .tag(park.id)
                } else {
                    Marker(park.name, coordinate: coordinate)
                        .tint(color)
                        .tag(park.id)
                }
            }
        }
    }

    /// Open now (green) / opens later today or tomorrow (yellow) / closed (red) / no opening-hours data (grey) — same
    /// palette as the detail badge, so the map and the card agree. A favorite keeps its star glyph
    /// but is colored the same way, rather than always yellow, so status doesn't disappear on tap.
    private static func pinColor(for park: Park) -> Color {
        return park.openStatusDetail().badgeColor
    }

    @MapContentBuilder
    private var cableLines: some MapContent {
        ForEach(parks) { park in
            ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                if let line = Self.cableLine(for: cable) {
                    MapPolyline(coordinates: line)
                        .stroke(Color.orange, lineWidth: 3)
                }
            }
        }
    }

    private static func cableLine(for cable: ParkCable) -> [CLLocationCoordinate2D]? {
        guard let points = cable.points, points.count >= 2 else { return nil }
        let line = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        return cable.direction?.isLoop == true ? line + [line[0]] : line
    }

    @MapContentBuilder
    private var searchPinMarker: some MapContent {
        if let searchPin {
            Marker(searchPin.name, systemImage: "magnifyingglass", coordinate: searchPin.coordinate)
                .tint(.blue)
        }
    }

    /// `MKMapItem.placemark` (and its `thoroughfare`/`region`) is gone in the iOS 26 API, so a
    /// street-free administrative match can no longer be preferred explicitly — take MapKit's
    /// own best address match and frame it at a fixed, comfortable zoom.
    private static let searchCameraDistance: CLLocationDistance = 60_000

    private func search() async {
        let text = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        guard let place = items.first else {
            searchFailed = true
            return
        }
        let center = place.location.coordinate
        searchPin = ParksSearchPin(name: place.name ?? text, coordinate: center)
        withRpplAnimation {
            position = .camera(MapCamera(centerCoordinate: center, distance: Self.searchCameraDistance))
        }
    }
}

private struct ParksSearchPin {
    let name: String
    let coordinate: CLLocationCoordinate2D
}
