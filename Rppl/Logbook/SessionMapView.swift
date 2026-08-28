import SwiftUI
import MapKit
import RpplCore

enum SessionMapLayout {
    case embedded
    case fullscreen

    var controlPadding: EdgeInsets {
        switch self {
        case .embedded:
            EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        case .fullscreen:
            EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        }
    }

    var buttonSize: CGFloat {
        switch self {
        case .embedded: 36
        case .fullscreen: 44
        }
    }

    var resetPadding: EdgeInsets {
        switch self {
        case .embedded:
            EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        case .fullscreen:
            EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 16)
        }
    }

    /// Keeps MapKit attribution ("Maps Legal") out of home-indicator / corner radius.
    var attributionSafeAreaPadding: EdgeInsets {
        switch self {
        case .embedded:
            EdgeInsets()
        case .fullscreen:
            EdgeInsets(top: 0, leading: 8, bottom: 12, trailing: 0)
        }
    }
}

struct SessionMapView: View {
    /// Per-ride solid tracks (ride cards).
    let tracks: [[LocationSample]]
    /// Session overview heatmap tracks.
    var sessionMapData: SessionMapTrackData? = nil
    var allowsInteraction: Bool = false
    /// Satellite toggle on interactive maps.
    var showsStyleToggle: Bool = false
    var preferredFrame: MapTrackFrame? = nil
    var layout: SessionMapLayout = .embedded

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false

    init(
        locations: [LocationSample],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.sessionMapData = nil
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    init(
        tracks: [[LocationSample]],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.sessionMapData = nil
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    init(
        sessionMapData: SessionMapTrackData,
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    private var interactionModes: MapInteractionModes {
        allowsInteraction ? [.pan, .zoom, .pitch, .rotate] : []
    }

    private var mapStyle: MapStyle {
        usesSatellite ? .hybrid : .standard
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            interactiveMap

            if showsStyleToggle {
                SessionMapControlCluster(
                    showsStyleToggle: true,
                    layout: layout
                )
                .padding(layout.controlPadding)
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsInteraction, showReset {
                resetButton
                    .padding(layout.resetPadding)
                    .safeAreaPadding(.bottom, layout == .fullscreen ? 4 : 0)
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
        let opacity = heatmapLineOpacity(setCount: data.heatmapTracks.count)
        ForEach(Array(data.heatmapTracks.enumerated()), id: \.offset) { _, track in
            if track.count >= 2 {
                MapPolyline(coordinates: track.map(\.clLocationCoordinate2D))
                    .stroke(Color.rpplHighlight.opacity(opacity), lineWidth: 4)
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

    @ViewBuilder
    private var interactiveMap: some View {
        let map = Map(position: $position, interactionModes: interactionModes) {
            if let sessionMapData {
                sessionMapContent(sessionMapData)
            } else {
                rideMapContent
            }
        }
        .mapStyle(mapStyle)

        if allowsInteraction {
            map
                .mapControls {
                    MapPitchToggle()
                    MapCompass()
                }
                .safeAreaPadding(layout.attributionSafeAreaPadding)
        } else {
            map
                .allowsHitTesting(false)
        }
    }

    private var resetButton: some View {
        Button {
            applyFittedCamera(animated: true)
            showReset = false
        } label: {
            SessionMapCircleButtonLabel(
                systemName: "arrow.counterclockwise",
                size: layout.buttonSize
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset map")
    }

    private var preferredFrameSignature: String {
        guard let preferredFrame else { return "nil" }
        return "\(preferredFrame.centerLatitude)-\(preferredFrame.centerLongitude)-\(preferredFrame.headingDegrees)-\(preferredFrame.spanWidthMeters)"
    }

    private var dataSignature: String {
        if let sessionMapData {
            return "session-\(sessionMapData.heatmapTracks.count)-\(sessionMapData.start.latitude)"
        }
        let count = tracks.reduce(0) { $0 + $1.count }
        return "sets-\(tracks.count)-\(count)"
    }

    private var fitCoordinates: [(latitude: Double, longitude: Double)] {
        if let sessionMapData {
            return sessionMapData.allFitCoordinates.map {
                (latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        return MapTrackFitter.coordinates(fromTracks: tracks)
    }

    private func heatmapLineOpacity(setCount: Int) -> Double {
        min(0.35, 0.85 / Double(max(setCount, 1)))
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

private extension MapCoordinate {
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct SessionMapCircleButtonLabel: View {
    let systemName: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.rpplText)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
    }
}

/// Satellite toggle for inline maps (sibling layer above NavigationLink).
struct SessionMapControlCluster: View {
    var showsStyleToggle: Bool = false
    var layout: SessionMapLayout = .embedded

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false

    var body: some View {
        Group {
            switch layout {
            case .embedded:
                HStack(spacing: 8) {
                    controlButtons
                }
            case .fullscreen:
                VStack(alignment: .leading, spacing: 10) {
                    controlButtons
                }
            }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        if showsStyleToggle {
            Button {
                usesSatellite.toggle()
            } label: {
                SessionMapCircleButtonLabel(
                    systemName: usesSatellite ? "map" : "globe.europe.africa.fill",
                    size: layout.buttonSize
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                usesSatellite
                    ? String(localized: "Show standard map")
                    : String(localized: "Show satellite map")
            )
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
                    preferredFrame: preferredFrame,
                    layout: .fullscreen
                )
            } else {
                SessionMapView(
                    tracks: tracks,
                    allowsInteraction: true,
                    showsStyleToggle: true,
                    preferredFrame: preferredFrame,
                    layout: .fullscreen
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.rpplBackground)
        .tint(Color.rpplAccent)
        .accessibilityLabel(title)
    }
}
