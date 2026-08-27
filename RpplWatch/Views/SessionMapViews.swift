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

/// Full-screen map (pushed on NavigationStack).
struct WatchSessionMapFullscreenView: View {
    let source: SessionMapSnapshotSource
    var showsTrackStyleToggle: Bool = false

    @AppStorage(AppConstants.sessionMapTrackStyleDefaultsKey)
    private var trackStyleRaw = SessionMapTrackStyle.averaged.rawValue

    private var trackStyle: SessionMapTrackStyle {
        SessionMapTrackStyle(rawValue: trackStyleRaw) ?? .averaged
    }

    var body: some View {
        GeometryReader { geo in
            SessionMapSnapshotView(
                source: resolvedSource,
                size: CGSize(width: geo.size.width, height: geo.size.height),
                cornerRadius: 0,
                showsPin: false
            )
            .overlay(alignment: .topLeading) {
                if showsTrackStyleToggle {
                    trackStyleToggle
                        .padding(8)
                }
            }
        }
        .navigationTitle(String(localized: "Map"))
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .preferredColorScheme(.dark)
        .accessibilityLabel(String(localized: "Session map"))
    }

    private var resolvedSource: SessionMapSnapshotSource {
        if case let .sessionTracks(data, _, frame) = source {
            return .sessionTracks(data, style: trackStyle, frame: frame)
        }
        return source
    }

    private var trackStyleToggle: some View {
        Button {
            trackStyleRaw = trackStyle == .averaged
                ? SessionMapTrackStyle.heatmap.rawValue
                : SessionMapTrackStyle.averaged.rawValue
        } label: {
            Image(systemName: trackStyle == .averaged
                ? "point.topleft.down.curvedto.point.bottomright.up"
                : "square.3.layers.3d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rpplIdlePrimary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            trackStyle == .averaged
                ? String(localized: "Show heatmap")
                : String(localized: "Show averaged track")
        )
    }
}

/// Tappable map preview with optional city name directly below the map.
struct WatchSessionMapPreview: View {
    var mapTracks: SessionMapTrackData?
    var startCoordinate: CLLocationCoordinate2D?
    var mapFrame: MapTrackFrame?
    var cityName: String?
    var mapHeight: CGFloat = 96
    var startMapDistanceMeters: CLLocationDistance = 500

    @AppStorage(AppConstants.sessionMapTrackStyleDefaultsKey)
    private var trackStyleRaw = SessionMapTrackStyle.averaged.rawValue

    private var trackStyle: SessionMapTrackStyle {
        SessionMapTrackStyle(rawValue: trackStyleRaw) ?? .averaged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source = snapshotSource {
                NavigationLink {
                    WatchSessionMapFullscreenView(
                        source: source,
                        showsTrackStyleToggle: mapTracks != nil
                    )
                } label: {
                    GeometryReader { geo in
                        SessionMapSnapshotView(
                            source: source,
                            size: CGSize(width: max(geo.size.width, 1), height: mapHeight),
                            cornerRadius: 12,
                            showsPin: mapTracks == nil
                        )
                    }
                    .frame(height: mapHeight)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Opens full screen map"))
            } else {
                SessionMapStripView(
                    startCoordinate: startCoordinate,
                    mapFrame: mapFrame,
                    mapHeight: mapHeight,
                    startMapDistanceMeters: startMapDistanceMeters
                )
            }

            if mapTracks != nil {
                trackStyleToggle
            }

            if let cityName, !cityName.isEmpty {
                Text(cityName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var snapshotSource: SessionMapSnapshotSource? {
        SessionMapSnapshotSource.sessionMap(
            mapTracks: mapTracks,
            trackStyle: trackStyle,
            startCoordinate: startCoordinate,
            mapFrame: mapFrame,
            startDistanceMeters: startMapDistanceMeters
        )
    }

    private var trackStyleToggle: some View {
        Button {
            trackStyleRaw = trackStyle == .averaged
                ? SessionMapTrackStyle.heatmap.rawValue
                : SessionMapTrackStyle.averaged.rawValue
        } label: {
            Label(
                trackStyle == .averaged
                    ? String(localized: "Heatmap")
                    : String(localized: "Averaged track"),
                systemImage: trackStyle == .averaged
                    ? "square.3.layers.3d"
                    : "point.topleft.down.curvedto.point.bottomright.up"
            )
            .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color.rpplIdleAccent)
    }
}

/// Non-interactive map preview strip. Full-screen map deferred on Watch.
struct SessionMapStripView: View {
    var mapTracks: SessionMapTrackData?
    var startCoordinate: CLLocationCoordinate2D?
    var mapFrame: MapTrackFrame?
    var mapHeight: CGFloat = 96
    var startMapDistanceMeters: CLLocationDistance = 500

    @AppStorage(AppConstants.sessionMapTrackStyleDefaultsKey)
    private var trackStyleRaw = SessionMapTrackStyle.averaged.rawValue

    private var trackStyle: SessionMapTrackStyle {
        SessionMapTrackStyle(rawValue: trackStyleRaw) ?? .averaged
    }

    var body: some View {
        Group {
            if let source = snapshotSource {
                GeometryReader { geo in
                    SessionMapSnapshotView(
                        source: source,
                        size: CGSize(width: max(geo.size.width, 1), height: mapHeight),
                        cornerRadius: 12,
                        showsPin: mapTracks == nil
                    )
                }
                .frame(height: mapHeight)
            } else {
                noGPSPlaceholder
            }
        }
    }

    private var snapshotSource: SessionMapSnapshotSource? {
        SessionMapSnapshotSource.sessionMap(
            mapTracks: mapTracks,
            trackStyle: trackStyle,
            startCoordinate: startCoordinate,
            mapFrame: mapFrame,
            startDistanceMeters: startMapDistanceMeters
        )
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
