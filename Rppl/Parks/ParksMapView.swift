import MapKit
import RpplCore
import SwiftUI

/// Map of all parks, shown in place of the parks list: red pins with names, place search,
/// tap a pin for the park detail.
struct ParksMapView: View {
    let parks: [Park]
    let location: ParksLocationProvider
    let onClose: () -> Void

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
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Close map"))

                Button {
                    usesSatellite.toggle()
                } label: {
                    Image(systemName: usesSatellite ? "map" : "globe.europe.africa.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(
                    usesSatellite
                        ? Text("Show standard map")
                        : Text("Show satellite map")
                )
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .ignoresSafeArea(edges: .bottom)
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
