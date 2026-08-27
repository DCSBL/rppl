import SwiftUI
import MapKit
import RpplCore

/// Compact square start-location preview for Ultra session overview (no marker label).
struct SessionStartMapPinView: View {
    let coordinate: CLLocationCoordinate2D
    var size: CGFloat = 64
    var cameraDistanceMeters: CLLocationDistance = 450

    var body: some View {
        SessionMapSnapshotView(
            source: .coordinate(coordinate, distanceMeters: cameraDistanceMeters),
            size: CGSize(width: size, height: size),
            cornerRadius: 10,
            showsPin: true
        )
    }
}

/// Non-interactive map preview strip. Full-screen map deferred on Watch.
struct SessionMapStripView: View {
    var startCoordinate: CLLocationCoordinate2D?
    var mapFrame: MapTrackFrame?
    var mapHeight: CGFloat = 96
    var startMapDistanceMeters: CLLocationDistance = 500

    var body: some View {
        Group {
            if let source = snapshotSource {
                GeometryReader { geo in
                    SessionMapSnapshotView(
                        source: source,
                        size: CGSize(width: max(geo.size.width, 1), height: mapHeight),
                        cornerRadius: 12,
                        showsPin: true
                    )
                }
                .frame(height: mapHeight)
            } else {
                noGPSPlaceholder
            }
        }
    }

    private var snapshotSource: SessionMapSnapshotSource? {
        if let startCoordinate {
            return .coordinate(startCoordinate, distanceMeters: startMapDistanceMeters)
        }
        if let mapFrame {
            return .frame(mapFrame)
        }
        return nil
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
}
