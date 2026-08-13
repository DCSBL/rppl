import MapKit
import SwiftUI
import RpplCore

struct SessionMapView: View {
    let locations: [LocationSample]
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if locations.count >= 2 {
                Map(position: $camera) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 3)
                }
                .mapStyle(.standard(elevation: .realistic))
                .onChange(of: locationSignature) { _, _ in
                    fitCamera()
                }
                .onAppear { fitCamera() }
            } else if let only = locations.first {
                Map(position: $camera) {
                    Marker("fix", coordinate: CLLocationCoordinate2D(
                        latitude: only.latitude,
                        longitude: only.longitude
                    ))
                }
                .onAppear {
                    camera = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: only.latitude,
                                longitude: only.longitude
                            ),
                            latitudinalMeters: 200,
                            longitudinalMeters: 200
                        )
                    )
                }
            } else {
                ContentUnavailableView("No GPS in window", systemImage: "map")
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        locations.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var locationSignature: String {
        guard let first = locations.first, let last = locations.last else { return "empty" }
        return "\(locations.count)-\(first.timestamp.timeIntervalSinceReferenceDate)-\(last.timestamp.timeIntervalSinceReferenceDate)"
    }

    private func fitCamera() {
        guard let region = regionFitting(coordinates) else { return }
        camera = .region(region)
    }

    private func regionFitting(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for coord in coords.dropFirst() {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.001),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.001)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
