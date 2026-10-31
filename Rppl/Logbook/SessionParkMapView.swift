import SwiftUI
import MapKit
import RpplCore

/// Map for a session without a GPS track: the park's cable layout, or a pin on the park when no layout is known.
struct SessionParkMapView: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false

    let park: Park
    /// Cable outlines from `Park.cables`; empty falls back to a pin.
    let cableOverlays: [[CLLocationCoordinate2D]]

    private var parkCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
    }

    private var position: MapCameraPosition {
        let points = cableOverlays.flatMap { $0 }
        guard points.count >= 2 else {
            return .region(MKCoordinateRegion(center: parkCoordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        }
        let rect = points
            .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
            .reduce(MKMapRect.null) { $0.union($1) }
        let pad = max(rect.size.width, rect.size.height) * 0.25
        return .rect(rect.insetBy(dx: -pad, dy: -pad))
    }

    var body: some View {
        Map(initialPosition: position, interactionModes: []) {
            ForEach(Array(cableOverlays.enumerated()), id: \.offset) { item in
                MapPolyline(coordinates: item.element)
                    .stroke(
                        Color.rpplAccent,
                        style: StrokeStyle(lineWidth: 3, dash: differentiateWithoutColor ? [4, 3] : [])
                    )
            }
            if cableOverlays.isEmpty {
                Marker(park.compactName, systemImage: MetricKind.park.systemImage, coordinate: parkCoordinate)
                    .tint(Color.rpplAccent)
            }
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(park.compactName)
    }
}
