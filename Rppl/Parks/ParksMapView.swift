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

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var detailPark: Park?
    @State private var query = ""
    @State private var searchFailed = false
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var searchPin: ParksSearchPin?
    @State private var favorites = ParkFavorites.shared
    @State private var cameraDistance: CLLocationDistance = .greatestFiniteMagnitude
    @State private var pendingRecenter = false

    /// Below this camera distance, cable traces are close enough to read; above it they're just clutter.
    private static let cableLineVisibleDistance: CLLocationDistance = 3_000
    /// "Reasonable distance" for the here/reset button: close enough to be useful, wide enough to
    /// see nearby landmarks around the park.
    private static let recenterCameraDistance: CLLocationDistance = 5_000

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
        .overlay(alignment: .bottomTrailing) {
            // Bottom-trailing, like Apple Maps' own locate-me/layers buttons: keeps these clear
            // of the floating header above (which draws on top of this view and previously hid
            // top-trailing controls whenever its measured height lagged a layout pass behind).
            VStack(spacing: 8) {
                MapStyleToggleButton(usesSatellite: $usesSatellite)
                MapRecenterButton(action: recenterOnUser)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .top)
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
        .onChange(of: location.coordinate) { _, coordinate in
            guard pendingRecenter, let coordinate else { return }
            pendingRecenter = false
            moveCamera(to: coordinate)
        }
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

    /// Jumps to the user's location at a reasonable distance; requests a fresh fix first if needed.
    private func recenterOnUser() {
        if let coordinate = location.coordinate {
            moveCamera(to: coordinate)
        } else {
            pendingRecenter = true
            location.refresh()
        }
    }

    private func moveCamera(to coordinate: ParkCoordinate) {
        let center = CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: center, distance: Self.recenterCameraDistance))
        }
    }
}

private struct ParksSearchPin {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

/// Standard/satellite toggle, using the same native Liquid Glass chrome as the rest of the app's
/// floating buttons (see the search/add buttons in ParksView) instead of hand-rolled material.
private struct MapStyleToggleButton: View {
    @Binding var usesSatellite: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { usesSatellite.toggle() }
        } label: {
            Image(systemName: usesSatellite ? "map.fill" : "globe.europe.africa.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(
            usesSatellite
                ? Text("Show standard map")
                : Text("Show satellite map")
        )
    }
}

/// Recenters the map on the user's current location at a fixed, useful zoom — unlike MapKit's own
/// user-location button, which recenters without changing the current zoom level.
private struct MapRecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text("Center on my location"))
    }
}
