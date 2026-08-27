import SwiftUI
import MapKit
import RpplCore

struct SessionMapView: View {
    /// Per-ride solid tracks (ride cards).
    let tracks: [[LocationSample]]
    /// Session overview distilled tracks (averaged / heatmap).
    var sessionMapData: SessionMapTrackData? = nil
    var allowsInteraction: Bool = false
    /// Satellite toggle on interactive maps.
    var showsStyleToggle: Bool = false
    /// Track-style toggle (averaged / heatmap); session overview only.
    var showsTrackStyleToggle: Bool = true
    var preferredFrame: MapTrackFrame? = nil

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @AppStorage(AppSettingsKey.sessionMapTrackStyle) private var trackStyleRaw = SessionMapTrackStyle.averaged.rawValue
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false

    init(
        locations: [LocationSample],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        showsTrackStyleToggle: Bool = true,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.sessionMapData = nil
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.showsTrackStyleToggle = showsTrackStyleToggle
        self.preferredFrame = preferredFrame
    }

    init(
        tracks: [[LocationSample]],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        showsTrackStyleToggle: Bool = true,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.sessionMapData = nil
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.showsTrackStyleToggle = showsTrackStyleToggle
        self.preferredFrame = preferredFrame
    }

    init(
        sessionMapData: SessionMapTrackData,
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        showsTrackStyleToggle: Bool = true,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.showsTrackStyleToggle = showsTrackStyleToggle
        self.preferredFrame = preferredFrame
    }

    private var trackStyle: SessionMapTrackStyle {
        SessionMapTrackStyle(rawValue: trackStyleRaw) ?? .averaged
    }

    private var interactionModes: MapInteractionModes {
        allowsInteraction ? [.pan, .zoom, .pitch, .rotate] : []
    }

    private var mapStyle: MapStyle {
        usesSatellite ? .hybrid : .standard
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $position, interactionModes: interactionModes) {
                if let sessionMapData {
                    sessionMapContent(sessionMapData)
                } else {
                    rideMapContent
                }
            }
            .mapStyle(mapStyle)
            .allowsHitTesting(allowsInteraction)

            if showsStyleToggle || (showsTrackStyleToggle && sessionMapData != nil) {
                SessionMapControlCluster(
                    showsStyleToggle: showsStyleToggle,
                    showsTrackStyleToggle: showsTrackStyleToggle,
                    hasSessionData: sessionMapData != nil
                )
                .padding(10)
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsInteraction, showReset {
                resetButton
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updateFit(for: geo.size, forceApply: true)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        updateFit(for: newSize, forceApply: !showReset)
                    }
                    .onChange(of: dataSignature) { _, _ in
                        showReset = false
                        updateFit(for: geo.size, forceApply: true)
                    }
                    .onChange(of: preferredFrameSignature) { _, _ in
                        if fitCoordinates.count < 2, preferredFrame != nil {
                            showReset = false
                            updateFit(for: geo.size, forceApply: true)
                        }
                    }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            guard allowsInteraction else { return }
            position = .camera(context.camera)
            guard let fitted else { return }
            showReset = !Self.isNearFittedCamera(context.camera, fit: fitted)
        }
    }

    @MapContentBuilder
    private func sessionMapContent(_ data: SessionMapTrackData) -> some MapContent {
        switch trackStyle {
        case .averaged:
            if let segments = speedSegments(for: data) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.coordinates.map(\.clLocationCoordinate2D))
                        .stroke(segment.color, lineWidth: 3)
                }
            } else if data.averagedTrack.count >= 2 {
                MapPolyline(coordinates: data.averagedTrack.map(\.clLocationCoordinate2D))
                    .stroke(Color.rpplHighlight, lineWidth: 3)
            }
        case .heatmap:
            let opacity = heatmapLineOpacity(rideCount: data.heatmapTracks.count)
            ForEach(Array(data.heatmapTracks.enumerated()), id: \.offset) { _, track in
                if track.count >= 2 {
                    MapPolyline(coordinates: track.map(\.clLocationCoordinate2D))
                        .stroke(Color.rpplHighlight.opacity(opacity), lineWidth: 4)
                }
            }
        }
        Marker("Start", coordinate: data.start.clLocationCoordinate2D)
    }

    @MapContentBuilder
    private var rideMapContent: some MapContent {
        ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
            MapPolyline(coordinates: track.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            })
            .stroke(Color.rpplHighlight, lineWidth: 3)
        }
        if let first = tracks.first?.first {
            Marker("Start", coordinate: CLLocationCoordinate2D(
                latitude: first.latitude,
                longitude: first.longitude
            ))
        }
        if let last = tracks.last?.last, tracks.flatMap({ $0 }).count > 1 {
            Marker("End", coordinate: CLLocationCoordinate2D(
                latitude: last.latitude,
                longitude: last.longitude
            ))
        }
    }

    private var resetButton: some View {
        Button {
            applyFittedCamera(animated: true)
            showReset = false
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.rpplText)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("Reset map")
    }

    private var preferredFrameSignature: String {
        guard let preferredFrame else { return "nil" }
        return "\(preferredFrame.centerLatitude)-\(preferredFrame.centerLongitude)-\(preferredFrame.headingDegrees)-\(preferredFrame.spanWidthMeters)"
    }

    /// Excludes track style so toggling averaged / heatmap does not refit the camera.
    private var dataSignature: String {
        if let sessionMapData {
            return "session-\(sessionMapData.averagedTrack.count)-\(sessionMapData.heatmapTracks.count)-\(sessionMapData.start.latitude)"
        }
        let count = tracks.reduce(0) { $0 + $1.count }
        return "rides-\(tracks.count)-\(count)"
    }

    private var fitCoordinates: [(latitude: Double, longitude: Double)] {
        if let sessionMapData {
            return sessionMapData.allFitCoordinates.map {
                (latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        return MapTrackFitter.coordinates(fromTracks: tracks)
    }

    private func speedSegments(for data: SessionMapTrackData) -> [ColoredSpeedSegment]? {
        guard let speeds = data.averagedSpeedKmh else { return nil }
        guard let segments = SessionMapSpeedColor.segments(
            track: data.averagedTrack,
            speedsKmh: speeds
        ) else {
            return nil
        }
        return segments.map { segment in
            ColoredSpeedSegment(
                coordinates: segment.coordinates,
                color: Color(
                    red: segment.color.red,
                    green: segment.color.green,
                    blue: segment.color.blue
                )
            )
        }
    }

    private func heatmapLineOpacity(rideCount: Int) -> Double {
        min(0.35, 0.85 / Double(max(rideCount, 1)))
    }

    private func updateFit(for size: CGSize, forceApply: Bool) {
        let next: MapTrackFit?
        if let preferredFrame, fitCoordinates.count >= 2 || sessionMapData != nil {
            next = MapTrackFitter.fit(
                frame: preferredFrame,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height)
            )
        } else if fitCoordinates.count >= 2 {
            next = MapTrackFitter.fit(
                locations: fitCoordinates,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height)
            )
        } else if let preferredFrame {
            next = MapTrackFitter.fit(
                frame: preferredFrame,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height)
            )
        } else {
            next = nil
        }
        guard let next else {
            fitted = nil
            position = .automatic
            return
        }
        fitted = next
        if forceApply {
            applyFittedCamera(animated: false)
        }
    }

    private func applyFittedCamera(animated: Bool) {
        guard let fitted else { return }
        let camera = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(
                latitude: fitted.centerLatitude,
                longitude: fitted.centerLongitude
            ),
            distance: fitted.cameraDistanceMeters,
            heading: fitted.headingDegrees,
            pitch: 0
        )
        let next = MapCameraPosition.camera(camera)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                position = next
            }
        } else {
            position = next
        }
    }

    private static func isNearFittedCamera(_ camera: MapCamera, fit: MapTrackFit) -> Bool {
        let headingDelta = abs(
            MapTrackFitter.clampedHeadingDegrees(camera.heading - fit.headingDegrees)
        )
        let latDelta = abs(camera.centerCoordinate.latitude - fit.centerLatitude)
        let lonDelta = abs(camera.centerCoordinate.longitude - fit.centerLongitude)
        let distanceRatio = abs(camera.distance - fit.cameraDistanceMeters)
            / max(fit.cameraDistanceMeters, 1)
        let pitchDelta = abs(camera.pitch)
        return headingDelta < 3
            && latDelta < 0.00012
            && lonDelta < 0.00012
            && distanceRatio < 0.1
            && pitchDelta < 4
    }
}

private struct ColoredSpeedSegment {
    let coordinates: [MapCoordinate]
    let color: Color
}

private extension MapCoordinate {
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Satellite + session track-style toggles for inline maps (sibling layer above NavigationLink).
struct SessionMapControlCluster: View {
    var showsStyleToggle: Bool = false
    var showsTrackStyleToggle: Bool = false
    var hasSessionData: Bool = false

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @AppStorage(AppSettingsKey.sessionMapTrackStyle) private var trackStyleRaw = SessionMapTrackStyle.averaged.rawValue

    private var trackStyle: SessionMapTrackStyle {
        SessionMapTrackStyle(rawValue: trackStyleRaw) ?? .averaged
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsStyleToggle {
                Button {
                    usesSatellite.toggle()
                } label: {
                    Image(systemName: usesSatellite ? "map" : "globe.europe.africa.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.rpplText)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    usesSatellite
                        ? String(localized: "Show standard map")
                        : String(localized: "Show satellite map")
                )
            }
            if showsTrackStyleToggle, hasSessionData {
                Button {
                    trackStyleRaw = trackStyle == .averaged
                        ? SessionMapTrackStyle.heatmap.rawValue
                        : SessionMapTrackStyle.averaged.rawValue
                } label: {
                    Image(systemName: trackStyle == .averaged
                        ? "point.topleft.down.curvedto.point.bottomright.up"
                        : "square.3.layers.3d")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.rpplText)
                        .frame(width: 36, height: 36)
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
    }
}

/// Full-screen interactive track map (pan / zoom / pitch / rotate + style toggle).
struct SessionMapFullscreenView: View {
    let tracks: [[LocationSample]]
    let sessionMapData: SessionMapTrackData?
    let title: String
    var preferredFrame: MapTrackFrame? = nil

    init(
        locations: [LocationSample],
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.sessionMapData = nil
        self.title = title
        self.preferredFrame = preferredFrame
    }

    init(
        tracks: [[LocationSample]],
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.sessionMapData = nil
        self.title = title
        self.preferredFrame = preferredFrame
    }

    init(
        sessionMapData: SessionMapTrackData,
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.title = title
        self.preferredFrame = preferredFrame
    }

    var body: some View {
        Group {
            if let sessionMapData {
                SessionMapView(
                    sessionMapData: sessionMapData,
                    allowsInteraction: true,
                    showsStyleToggle: true,
                    preferredFrame: preferredFrame
                )
            } else {
                SessionMapView(
                    tracks: tracks,
                    allowsInteraction: true,
                    showsStyleToggle: true,
                    preferredFrame: preferredFrame
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.rpplBackground)
        .tint(Color.rpplAccent)
        .accessibilityLabel(title)
    }
}
