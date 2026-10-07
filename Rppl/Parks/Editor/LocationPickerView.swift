import CoreLocation
import MapKit
import RpplCore
import SwiftUI

/// Looks up what the map knows about a spot: its time zone. Answers are kept per spot, and a failed
/// lookup just means nothing is suggested.
@MainActor
final class ParkPlaceResolver {
    static let shared = ParkPlaceResolver()

    private var zones: [String: TimeZone] = [:]
    private var names: [String: String] = [:]

    private func key(_ coordinate: ParkCoordinate) -> String {
        String(format: "%.2f,%.2f", coordinate.lat, coordinate.lon)
    }

    /// What was already resolved near this spot; nil when nothing is known yet.
    func timeZone(near coordinate: ParkCoordinate) -> TimeZone? {
        zones[key(coordinate)]
    }

    /// City (or place) name for a spot, for labelling an own location; nil when the lookup fails.
    func placeName(at coordinate: ParkCoordinate) async -> String? {
        if let known = names[key(coordinate)] { return known }
        let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lon)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        let name = item.addressRepresentations?.cityName ?? item.name
        names[key(coordinate)] = name
        return name
    }

    func resolveTimeZone(at coordinate: ParkCoordinate) async -> TimeZone? {
        if let known = zones[key(coordinate)] { return known }
        let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lon)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            guard let zone = items.compactMap(\.timeZone).first else { return nil }
            zones[key(coordinate)] = zone
            return zone
        } catch {
            WakeLog.debug(.ui, "park time zone lookup: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Map with a crosshair in the middle and a button below: pan until the crosshair is on the spot,
/// then set it. Same way a cable point is placed.
struct LocationPickerView: View {
    @Binding var coordinate: ParkCoordinate
    let userLocation: ParkCoordinate?
    var title: LocalizedStringKey = "Park location"

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = true
    @State private var position: MapCameraPosition
    @State private var viewCenter: CLLocationCoordinate2D
    @State private var query = ""
    @State private var searchFailed = false
    @State private var here = ParksLocationProvider()
    @State private var wantsHere = false

    init(coordinate: Binding<ParkCoordinate>, userLocation: ParkCoordinate?, title: LocalizedStringKey = "Park location") {
        _coordinate = coordinate
        self.userLocation = userLocation
        self.title = title
        let start = Self.startingPoint(coordinate.wrappedValue, userLocation)
        let center = start.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            ?? CLLocationCoordinate2D(latitude: 52.1, longitude: 5.3)
        _viewCenter = State(initialValue: center)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: start == nil ? 300_000 : 700,
            longitudinalMeters: start == nil ? 300_000 : 700
        )))
    }

    /// The park pin when there is one, else where the person is. nil shows the Netherlands.
    private static func startingPoint(_ pin: ParkCoordinate, _ user: ParkCoordinate?) -> ParkCoordinate? {
        ParkDraft.isValid(pin) ? pin : user
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                if ParkDraft.isValid(coordinate) {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red, .white)
                            .accessibilityLabel(Text("Current pin"))
                    }
                }
            }
            .mapStyle(usesSatellite ? .hybrid(elevation: .flat) : .standard)
            .onMapCameraChange(frequency: .continuous) { context in
                viewCenter = context.camera.centerCoordinate
            }
            .overlay { MapCrosshair() }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text("Search for a place"))
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: here.coordinate) { _, fix in
                guard wantsHere, let fix else { return }
                wantsHere = false
                move(to: CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lon), meters: 700)
            }
            .alert("No place found", isPresented: $searchFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try another name, or pan the map to the spot.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let fix = here.coordinate {
                            move(to: CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lon), meters: 700)
                        } else {
                            wantsHere = true
                            here.requestAccess()
                        }
                    } label: {
                        Image(systemName: "location")
                    }
                    .accessibilityLabel(Text("Use my current location"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        usesSatellite.toggle()
                    } label: {
                        Image(systemName: usesSatellite ? "map" : "globe.europe.africa")
                    }
                    .accessibilityLabel(Text("Map style"))
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                coordinate = ParkCoordinate(lat: viewCenter.latitude, lon: viewCenter.longitude)
                dismiss()
            } label: {
                Label("Set location here", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Pan and zoom until the marker is on the dock, then set the location.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func move(to center: CLLocationCoordinate2D, meters: CLLocationDistance) {
        viewCenter = center
        position = .region(MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters))
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let place = (try? await MKLocalSearch(request: request).start())?.mapItems.first else {
            searchFailed = true
            return
        }
        move(to: place.location.coordinate, meters: 1_500)
    }
}
