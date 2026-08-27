import SwiftUI
import MapKit
import RpplCore

/// Non-interactive map preview strip. Full-screen map deferred on Watch.
struct SessionMapStripView: View {
    var startCoordinate: CLLocationCoordinate2D?
    var mapFrame: MapTrackFrame?
    var mapHeight: CGFloat = 96
    var startMapDistanceMeters: CLLocationDistance = 500

    var body: some View {
        Group {
            if let startCoordinate {
                startPinStrip(coordinate: startCoordinate, distanceMeters: startMapDistanceMeters)
            } else if let mapFrame, let fit = mapFrameFit(mapFrame) {
                framedStrip(fit: fit, markerCoordinate: fit.coordinate)
            } else {
                noGPSPlaceholder
            }
        }
    }

    @ViewBuilder
    private func startPinStrip(coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance) -> some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: distanceMeters,
            heading: 0,
            pitch: 0
        )), interactionModes: []) {
            Marker("Start", coordinate: coordinate)
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(String(localized: "Session start location"))
    }

    @ViewBuilder
    private func framedStrip(fit: MapTrackFit, markerCoordinate: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: fit.coordinate,
            distance: fit.cameraDistanceMeters,
            heading: fit.headingDegrees,
            pitch: 0
        )), interactionModes: []) {
            Marker("Track", coordinate: markerCoordinate)
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(String(localized: "Session map"))
    }

    private var noGPSPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .frame(height: mapHeight)
            .overlay {
                Label("No GPS", systemImage: "location.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(String(localized: "No GPS start location"))
    }

    private func mapFrameFit(_ frame: MapTrackFrame) -> MapTrackFit? {
        MapTrackFitter.fit(frame: frame, viewWidth: Double(mapHeight * 2), viewHeight: Double(mapHeight))
    }
}

private extension MapTrackFit {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
}
