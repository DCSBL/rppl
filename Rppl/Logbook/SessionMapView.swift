import SwiftUI
import MapKit
import RpplCore

/// Which set the map isolates. Nothing selected draws every set flat, as before.
struct SessionMapRendering {
    /// Per-set GPS paired with set numbers.
    var setTracks: [SessionSetTrack] = []
    /// `SessionSetTrack.setIndex` to isolate; nil shows every set.
    var soloSetIndex: Int?

    static let flat = SessionMapRendering()
}

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
    var rendering: SessionMapRendering = .flat
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
        rendering: SessionMapRendering = .flat,
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.sessionMapData = nil
        self.rendering = rendering
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    init(
        tracks: [[LocationSample]],
        rendering: SessionMapRendering = .flat,
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.sessionMapData = nil
        self.rendering = rendering
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    init(
        sessionMapData: SessionMapTrackData,
        rendering: SessionMapRendering = .flat,
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil,
        layout: SessionMapLayout = .embedded
    ) {
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.rendering = rendering
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
        self.layout = layout
    }

    private var interactionModes: MapInteractionModes {
        allowsInteraction ? [.pan, .zoom, .pitch, .rotate] : []
    }

    /// Per-set tracks for solo. Set cards pass plain tracks instead.
    private var renderTracks: [SessionSetTrack] {
        if !rendering.setTracks.isEmpty { return rendering.setTracks }
        return tracks.enumerated().map { offset, samples in
            SessionSetTrack(setIndex: offset, setNumber: offset + 1, samples: samples)
        }
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
            showReset = !isNearFittedCamera(context.camera, fit: fitted)
        }
    }

    // MARK: - Map content

    @MapContentBuilder
    private var mapContent: some MapContent {
        if focusedTrack != nil {
            soloContent
        } else {
            flatContent
        }
    }

    @MapContentBuilder
    private var flatContent: some MapContent {
        if let sessionMapData {
            let opacity = heatmapLineOpacity(setCount: sessionMapData.heatmapTracks.count)
            ForEach(Array(sessionMapData.heatmapTracks.enumerated()), id: \.offset) { item in
                if item.element.count >= 2 {
                    MapPolyline(coordinates: coordinates(item.element))
                        .stroke(Color.rpplHighlight.opacity(opacity), lineWidth: 4)
                }
            }
            Marker("Start", coordinate: coordinate(sessionMapData.start))
        } else {
            ForEach(Array(tracks.enumerated()), id: \.offset) { item in
                MapPolyline(coordinates: coordinates(item.element))
                    .stroke(Color.rpplHighlight, lineWidth: 3)
            }
            if let first = tracks.first?.first {
                Marker("Start", coordinate: coordinate(first))
            }
            if let last = tracks.last?.last, tracks.flatMap({ $0 }).count > 1 {
                Marker("End", coordinate: coordinate(last))
            }
        }
    }

    @MapContentBuilder
    private var soloContent: some MapContent {
        if let focused = focusedTrack {
            ForEach(renderTracks.filter { $0.setIndex != focused.setIndex }, id: \.setIndex) { track in
                MapPolyline(coordinates: coordinates(track.samples))
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 2)
            }
            MapPolyline(coordinates: coordinates(focused.samples))
                .stroke(Color.rpplHighlight, lineWidth: 4)
            if let first = focused.samples.first {
                endpointAnnotation("Start", at: coordinate(first), symbol: "play.fill")
            }
            if let last = focused.samples.last {
                endpointAnnotation("End", at: coordinate(last), symbol: "stop.fill")
            }
        }
    }

    private func endpointAnnotation(
        _ title: LocalizedStringKey,
        at coordinate: CLLocationCoordinate2D,
        symbol: String
    ) -> some MapContent {
        Annotation(title, coordinate: coordinate) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.rpplHighlight, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                }
        }
        .annotationTitles(.hidden)
    }

    @ViewBuilder
    private var interactiveMap: some View {
        let map = Map(position: $position, interactionModes: interactionModes) {
            mapContent
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

    // MARK: - Track helpers

    private var focusedTrack: SessionSetTrack? {
        guard let soloSetIndex = rendering.soloSetIndex else { return nil }
        return renderTracks.first { $0.setIndex == soloSetIndex }
    }

    private func coordinates(_ samples: [LocationSample]) -> [CLLocationCoordinate2D] {
        samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func coordinates(_ points: [MapCoordinate]) -> [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func coordinate(_ sample: LocationSample) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
    }

    private func coordinate(_ point: MapCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    // MARK: - Camera

    private var preferredFrameSignature: String {
        guard let preferredFrame else { return "nil" }
        return "\(preferredFrame.centerLatitude)-\(preferredFrame.centerLongitude)-\(preferredFrame.headingDegrees)-\(preferredFrame.spanWidthMeters)"
    }

    private var dataSignature: String {
        var signature = "solo-\(focusedTrack?.setIndex ?? -1)"
        if let sessionMapData {
            signature += "-session-\(sessionMapData.heatmapTracks.count)-\(sessionMapData.start.latitude)"
        }
        let trackPoints = renderTracks.reduce(0) { $0 + $1.samples.count }
        signature += "-sets-\(renderTracks.count)-\(trackPoints)"
        return signature
    }

    private var fitCoordinates: [(latitude: Double, longitude: Double)] {
        if let focused = focusedTrack, focused.samples.count >= 2 {
            return focused.samples.map { (latitude: $0.latitude, longitude: $0.longitude) }
        }
        if let sessionMapData {
            return sessionMapData.allFitCoordinates.map {
                (latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        if !renderTracks.isEmpty {
            return MapTrackFitter.coordinates(fromTracks: renderTracks.map(\.samples))
        }
        return MapTrackFitter.coordinates(fromTracks: tracks)
    }

    /// A soloed set gets its own frame; the persisted session frame would zoom back out.
    private var prefersPersistedFrame: Bool {
        focusedTrack == nil
    }

    private func heatmapLineOpacity(setCount: Int) -> Double {
        min(0.35, 0.85 / Double(max(setCount, 1)))
    }

    private func updateFit(for size: CGSize, forceApply: Bool) {
        let next: MapTrackFit?
        let frame = prefersPersistedFrame ? preferredFrame : nil
        if let frame, fitCoordinates.count >= 2 || sessionMapData != nil {
            next = MapTrackFitter.fit(
                frame: frame,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height)
            )
        } else if fitCoordinates.count >= 2 {
            next = MapTrackFitter.fit(
                locations: fitCoordinates,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height)
            )
        } else if let frame {
            next = MapTrackFitter.fit(
                frame: frame,
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

    private func camera(for fit: MapTrackFit) -> MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(
                latitude: fit.centerLatitude,
                longitude: fit.centerLongitude
            ),
            distance: fit.cameraDistanceMeters,
            heading: fit.headingDegrees,
            pitch: 0
        )
    }

    private func applyFittedCamera(animated: Bool) {
        guard let fitted else { return }
        let next = MapCameraPosition.camera(camera(for: fitted))
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                position = next
            }
        } else {
            position = next
        }
    }

    private func isNearFittedCamera(_ camera: MapCamera, fit: MapTrackFit) -> Bool {
        let headingDelta = abs(
            MapTrackFitter.clampedHeadingDegrees(
                camera.heading - fit.headingDegrees
            )
        )
        let latDelta = abs(camera.centerCoordinate.latitude - fit.centerLatitude)
        let lonDelta = abs(camera.centerCoordinate.longitude - fit.centerLongitude)
        let expectedDistance = fit.cameraDistanceMeters
        let distanceRatio = abs(camera.distance - expectedDistance) / max(expectedDistance, 1)
        let pitchDelta = abs(camera.pitch)
        return headingDelta < 3
            && latDelta < 0.00012
            && lonDelta < 0.00012
            && distanceRatio < 0.1
            && pitchDelta < 6
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
    let rendering: SessionMapRendering
    let title: String
    var preferredFrame: MapTrackFrame? = nil

    init(
        locations: [LocationSample],
        rendering: SessionMapRendering = .flat,
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.sessionMapData = nil
        self.rendering = rendering
        self.title = title
        self.preferredFrame = preferredFrame
    }

    init(
        tracks: [[LocationSample]],
        rendering: SessionMapRendering = .flat,
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.sessionMapData = nil
        self.rendering = rendering
        self.title = title
        self.preferredFrame = preferredFrame
    }

    init(
        sessionMapData: SessionMapTrackData,
        rendering: SessionMapRendering = .flat,
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.rendering = rendering
        self.title = title
        self.preferredFrame = preferredFrame
    }

    var body: some View {
        Group {
            if let sessionMapData {
                SessionMapView(
                    sessionMapData: sessionMapData,
                    rendering: rendering,
                    allowsInteraction: true,
                    showsStyleToggle: true,
                    preferredFrame: preferredFrame,
                    layout: .fullscreen
                )
            } else {
                SessionMapView(
                    tracks: tracks,
                    rendering: rendering,
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
