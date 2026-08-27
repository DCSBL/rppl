import SwiftUI
import MapKit
import RpplCore

/// Full-screen map push value (camera distance + heading differ from strip preview).
struct SessionMapDestination: Hashable {
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let headingDegrees: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func startPin(_ coordinate: CLLocationCoordinate2D, distanceMeters: Double = 500) -> SessionMapDestination {
        SessionMapDestination(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: distanceMeters,
            headingDegrees: 0
        )
    }

    static func framed(_ fit: MapTrackFit) -> SessionMapDestination {
        SessionMapDestination(
            latitude: fit.centerLatitude,
            longitude: fit.centerLongitude,
            distanceMeters: fit.cameraDistanceMeters,
            headingDegrees: fit.headingDegrees
        )
    }
}

/// Compact map strip (tap → fullscreen). Prefers start pin; falls back to derived map frame.
struct SessionMapStripView: View {
    var startCoordinate: CLLocationCoordinate2D?
    var mapFrame: MapTrackFrame?
    var mapHeight: CGFloat = 96
    var startMapDistanceMeters: CLLocationDistance = 500
    let onMapTap: (SessionMapDestination) -> Void

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
        Button {
            onMapTap(.startPin(coordinate, distanceMeters: distanceMeters))
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Session start location"))
        .accessibilityHint(String(localized: "Shows full-screen map"))
    }

    @ViewBuilder
    private func framedStrip(fit: MapTrackFit, markerCoordinate: CLLocationCoordinate2D) -> some View {
        Button {
            onMapTap(.framed(fit))
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Session map"))
        .accessibilityHint(String(localized: "Shows full-screen map"))
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

/// Full-screen interactive map (pan / zoom); system Back dismisses.
struct SessionStartMapFullscreenView: View {
    let destination: SessionMapDestination

    var body: some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: destination.coordinate,
            distance: destination.distanceMeters,
            heading: destination.headingDegrees,
            pitch: 0
        )), interactionModes: [.pan, .zoom]) {
            Marker("Start", coordinate: destination.coordinate)
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(String(localized: "Map"))
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .accessibilityLabel(String(localized: "Session location map"))
    }
}
