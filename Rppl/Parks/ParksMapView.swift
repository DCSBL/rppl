import MapKit
import RpplCore
import SwiftUI

/// Map of all parks, shown in place of the parks list: red pins with names, place search,
/// tap a pin for the park detail.
struct ParksMapView: View {
    let parks: [Park]
    let location: ParksLocationProvider
    /// Height of the floating header above this view, so its own controls sit below it
    /// instead of hiding underneath.
    var topInset: CGFloat = 0
    /// Owned by the parent: the style-toggle/recenter buttons live in its header overlay
    /// (see ParksView), sharing this same camera so they can drive it directly.
    @Binding var position: MapCameraPosition

    @State private var selectedID: String?
    @State private var detailPark: Park?
    @State private var query = ""
    @State private var searchFailed = false
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var searchPin: ParksSearchPin?
    @State private var favorites = ParkFavorites.shared
    @State private var cameraDistance: CLLocationDistance = .greatestFiniteMagnitude

    /// Below this camera distance, cable traces are close enough to read; above it they're just clutter.
    private static let cableLineVisibleDistance: CLLocationDistance = 10_000

    private var showsCableLines: Bool { cameraDistance < Self.cableLineVisibleDistance }

    private var parkMatches: [Park] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return parks.filter { $0.name.localizedCaseInsensitiveContains(needle) }.prefix(5).map { $0 }
    }

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(parks) { park in
                let coordinate = CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
                if favorites.contains(park.id) {
                    Marker(park.name, systemImage: "star.fill", coordinate: coordinate)
                        .tint(.yellow)
                        .tag(park.id)
                } else {
                    Marker(park.name, coordinate: coordinate)
                        .tint(.red)
                        .tag(park.id)
                }
            }
            if showsCableLines {
                ForEach(parks) { park in
                    ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { _, cable in
                        if let points = cable.points, points.count >= 2 {
                            let line = points.map {
                                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                            }
                            MapPolyline(coordinates: cable.direction?.isLoop == true ? line + [line[0]] : line)
                                .stroke(Color.orange, lineWidth: 3)
                        }
                    }
                }
            }
            if let searchPin {
                Marker(searchPin.name, systemImage: "magnifyingglass", coordinate: searchPin.coordinate)
                    .tint(.blue)
            }
            UserAnnotation()
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .onMapCameraChange(frequency: .onEnd) { context in
            cameraDistance = context.camera.distance
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topInset)
        }
        .ignoresSafeArea()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search places"))
        .searchSuggestions {
            ForEach(parkMatches) { park in
                Button {
                    query = ""
                    detailPark = park
                } label: {
                    Label(park.name, systemImage: "mappin")
                }
            }
        }
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: selectedID) { _, id in
            guard let id, let park = parks.first(where: { $0.id == id }) else { return }
            selectedID = nil
            detailPark = park
        }
        .navigationDestination(item: $detailPark) { park in
            ParkDetailContainer(park: park)
        }
        .alert(Text("No place found"), isPresented: $searchFailed) {
            Button("OK", role: .cancel) {}
        }
        .onAppear { location.refresh() }
    }

    /// Countries and towns only: address results without a street.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        let place = items.first { $0.placemark.thoroughfare == nil } ?? items.first
        guard let place else {
            searchFailed = true
            return
        }
        let center = place.placemark.coordinate
        let region = (place.placemark.region as? CLCircularRegion)?.radius ?? 20_000
        searchPin = ParksSearchPin(name: place.name ?? text, coordinate: center)
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: center, distance: max(region * 3, 5_000)))
        }
    }
}

private struct ParksSearchPin {
    let name: String
    let coordinate: CLLocationCoordinate2D
}
