import MapKit
import RpplCore
import SwiftUI

/// Full-screen map of all parks: red pins with names, place search, tap a pin for the park detail.
struct ParksMapView: View {
    let parks: [Park]

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var detailPark: Park?
    @State private var query = ""
    @State private var searchFailed = false

    private var parkMatches: [Park] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return parks.filter { $0.name.localizedCaseInsensitiveContains(needle) }.prefix(5).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedID) {
                ForEach(parks) { park in
                    Marker(
                        park.name,
                        coordinate: CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
                    )
                    .tint(.red)
                    .tag(park.id)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Close"), systemImage: "xmark") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: Text("Search places"))
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
        }
        .tint(Color.rpplAccent)
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
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: center, distance: max(region * 3, 5_000)))
        }
    }
}
