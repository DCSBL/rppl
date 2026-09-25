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

    private var parkMatches: [Park] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return parks.filter { $0.name.localizedCaseInsensitiveContains(needle) }.prefix(5).map { $0 }
    }

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(parks) { park in
                Marker(
                    park.name,
                    coordinate: CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
                )
                .tint(.red)
                .tag(park.id)
            }
            if let searchPin {
                Marker(searchPin.name, systemImage: "magnifyingglass", coordinate: searchPin.coordinate)
                    .tint(.blue)
            }
            UserAnnotation()
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topInset)
        }
        .overlay(alignment: .topTrailing) {
            MapStyleToggleButton(usesSatellite: $usesSatellite)
                .padding(.top, topInset + 8)
                .padding(.trailing, 12)
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

/// Standard/satellite toggle, styled to match MapKit's own controls (MapCompass, MapPitchToggle)
/// rather than the app's own button chrome.
private struct MapStyleToggleButton: View {
    @Binding var usesSatellite: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { usesSatellite.toggle() }
        } label: {
            Image(systemName: usesSatellite ? "map.fill" : "globe.europe.africa.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderless)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityLabel(
            usesSatellite
                ? Text("Show standard map")
                : Text("Show satellite map")
        )
    }
}
