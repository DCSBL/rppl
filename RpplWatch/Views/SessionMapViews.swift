import SwiftUI
import MapKit
import RpplCore

/// Hashable wrapper so NavigationLink can push a map coordinate.
struct StartMapCoordinate: Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Compact map strip (tap → fullscreen). Prefers start pin; falls back to derived map frame.
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
        ZStack {
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

            NavigationLink(value: StartMapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "Session start location"))
        .accessibilityHint(String(localized: "Shows full-screen map"))
    }

    @ViewBuilder
    private func framedStrip(fit: MapTrackFit, markerCoordinate: CLLocationCoordinate2D) -> some View {
        ZStack {
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

            NavigationLink(
                value: StartMapCoordinate(
                    latitude: markerCoordinate.latitude,
                    longitude: markerCoordinate.longitude
                )
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
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
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    var headingDegrees: Double = 0

    var body: some View {
        Map(initialPosition: .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: distanceMeters,
            heading: headingDegrees,
            pitch: 0
        ))) {
            Marker("Start", coordinate: coordinate)
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .accessibilityLabel(String(localized: "Session start location map"))
    }
}
