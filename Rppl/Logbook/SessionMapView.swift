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
}

struct SessionMapView: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.mapScreenScope) private var mapScreenScope
    @ScaledMetric(relativeTo: .caption2) private var endpointSize: CGFloat = 20
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
    /// Park cable outlines drawn as a thin line beneath the tracks.
    var cableOverlays: [[CLLocationCoordinate2D]] = []
    /// Set on a full-screen map: style and reset live in the navigation bar (`MapScreenToolbar`).
    var usesBarButtons = false
    /// Bumped by the bar's reset button: back to the fitted frame.
    var resetToken = 0
    /// The blue dot, once location access is on; nil hides it.
    var userLocation: CLLocationCoordinate2D?
    /// Bumped by the bar's location button: centers on `userLocation`.
    var locateToken = 0

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false
    /// The whole map and, full screen, the part bars and a sidebar cover (see `mapScreen`).
    @State private var viewport = MapViewport()
    @State private var lastCamera: MapCamera?

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
        layout: SessionMapLayout = .embedded,
        cableOverlays: [[CLLocationCoordinate2D]] = []
    ) {
        self.cableOverlays = cableOverlays
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

            if showsStyleToggle, !usesBarButtons {
                SessionMapControlCluster(
                    showsStyleToggle: true,
                    layout: layout
                )
                .padding(layout.controlPadding)
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsInteraction, showReset, !usesBarButtons {
                resetButton
                    .padding(layout.resetPadding)
                    .safeAreaPadding(.bottom, layout == .fullscreen ? 4 : 0)
            }
        }
        .background {
            GeometryReader { geo in
                // Embedded in a card the safe area is not the map's business: only full screen frames around it.
                let measured = MapViewport(
                    size: geo.size,
                    safeArea: layout == .fullscreen ? geo.safeAreaInsets : EdgeInsets(),
                    layoutDirection: layoutDirection
                )
                Color.clear
                    .onAppear {
                        updateFit(for: measured, forceApply: true)
                    }
                    .onChange(of: measured) { _, next in
                        updateFit(for: next, forceApply: !showReset)
                    }
                    .onChange(of: dataSignature) { _, _ in
                        showReset = false
                        updateFit(for: measured, forceApply: true)
                    }
                    .onChange(of: preferredFrameSignature) { _, _ in
                        if fitCoordinates.count < 2, preferredFrame != nil {
                            showReset = false
                            updateFit(for: measured, forceApply: true)
                        }
                    }
            }
        }
        .onChange(of: resetToken) { _, _ in
            applyFittedCamera(animated: true)
            showReset = false
        }
        .onChange(of: locateToken) { _, _ in
            guard let userLocation else { return }
            // Keeps the zoom and turn the map has now, like the location button in Maps.
            let distance = lastCamera?.distance ?? fitted?.cameraDistanceMeters ?? 1_000
            let heading = lastCamera?.heading ?? 0
            withRpplAnimation(.easeInOut(duration: 0.25)) {
                position = .camera(viewport.camera(centeredOn: userLocation, distance: distance, heading: heading))
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            lastCamera = context.camera
            guard allowsInteraction else { return }
            // Do not write `position` back here: it interrupts pan inertia and
            // swallows the next swipe. The Map binding already tracks the camera.
            guard let fitted else { return }
            showReset = !isNearFittedCamera(context.camera, fit: fitted)
        }
    }

    // MARK: - Map content

    @MapContentBuilder
    private var mapContent: some MapContent {
        ForEach(Array(cableOverlays.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: item.element)
                .stroke(
                    Color.rpplAccent,
                    style: StrokeStyle(lineWidth: 1.5, dash: differentiateWithoutColor ? [4, 3] : [])
                )
        }
        if focusedTrack != nil {
            soloContent
        } else {
            flatContent
        }
        if userLocation != nil {
            UserAnnotation()
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
                .font(.system(size: endpointSize * 0.45, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: endpointSize, height: endpointSize)
                .background(Color.rpplHighlight, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                }
        }
        .annotationTitles(.hidden)
    }

    @ViewBuilder
    private var interactiveMap: some View {
        let map = Map(position: $position, interactionModes: interactionModes, scope: mapScreenScope) {
            mapContent
        }
        .mapStyle(mapStyle)

        // No 3D button: tilting stays a two-finger gesture.
        if allowsInteraction {
            map
                .mapScreenControls(scope: mapScreenScope)
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

    private func updateFit(for measured: MapViewport, forceApply: Bool) {
        viewport = measured
        let size = measured.size
        let next: MapTrackFit?
        let frame = prefersPersistedFrame ? preferredFrame : nil
        if let frame, fitCoordinates.count >= 2 || sessionMapData != nil {
            next = MapTrackFitter.fit(
                frame: frame,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height),
                insets: measured.insets
            )
        } else if fitCoordinates.count >= 2 {
            next = MapTrackFitter.fit(
                locations: fitCoordinates,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height),
                insets: measured.insets
            )
        } else if let frame {
            next = MapTrackFitter.fit(
                frame: frame,
                viewWidth: Double(size.width),
                viewHeight: Double(size.height),
                insets: measured.insets
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
            withRpplAnimation(.easeInOut(duration: 0.25)) {
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
    var cableOverlays: [[CLLocationCoordinate2D]] = []

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
        preferredFrame: MapTrackFrame? = nil,
        cableOverlays: [[CLLocationCoordinate2D]] = []
    ) {
        self.cableOverlays = cableOverlays
        self.tracks = []
        self.sessionMapData = sessionMapData
        self.rendering = rendering
        self.title = title
        self.preferredFrame = preferredFrame
    }

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var resetToken = 0
    @State private var locateToken = 0
    @State private var location = ParksLocationProvider()
    @State private var pendingLocate = false

    private var userLocation: CLLocationCoordinate2D? {
        guard location.availability == .available, let coordinate = location.coordinate else { return nil }
        return CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
    }

    /// Only once location access is on: this map never asks for it.
    private var locateAction: (() -> Void)? {
        guard location.availability == .available else { return nil }
        return locate
    }

    var body: some View {
        Group {
            if let sessionMapData {
                SessionMapView(
                    sessionMapData: sessionMapData,
                    rendering: rendering,
                    allowsInteraction: true,
                    preferredFrame: preferredFrame,
                    layout: .fullscreen,
                    cableOverlays: cableOverlays
                )
                .barButtons(resetToken: resetToken, locateToken: locateToken, userLocation: userLocation)
            } else {
                SessionMapView(
                    tracks: tracks,
                    rendering: rendering,
                    allowsInteraction: true,
                    preferredFrame: preferredFrame,
                    layout: .fullscreen
                )
                .barButtons(resetToken: resetToken, locateToken: locateToken, userLocation: userLocation)
            }
        }
        .mapScreen(usesSatellite: $usesSatellite, reset: { resetToken += 1 }, locate: locateAction)
        .background(DisableNavigationSwipeBack())
        // Only the map and the bar buttons: no title band over the map.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .onAppear { location.refresh() }
        .onChange(of: location.coordinate) { _, coordinate in
            guard pendingLocate, coordinate != nil else { return }
            pendingLocate = false
            locateToken += 1
        }
        .background(Color.rpplBackground)
        .tint(Color.rpplAccent)
        .accessibilityLabel(title)
    }

    /// Waits for a first fix when there is none yet.
    private func locate() {
        if location.coordinate != nil {
            locateToken += 1
        } else {
            pendingLocate = true
            location.refresh()
        }
    }
}

private extension SessionMapView {
    func barButtons(resetToken: Int, locateToken: Int, userLocation: CLLocationCoordinate2D?) -> SessionMapView {
        var copy = self
        copy.usesBarButtons = true
        copy.resetToken = resetToken
        copy.locateToken = locateToken
        copy.userLocation = userLocation
        return copy
    }
}

/// Turns off the interactive swipe-back gestures while visible so repeated map
/// swipes never pop the screen. The back button still works.
private struct DisableNavigationSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setSwipeBack(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setSwipeBack(enabled: true)
        }

        private func setSwipeBack(enabled: Bool) {
            guard let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = enabled
            nav.interactiveContentPopGestureRecognizer?.isEnabled = enabled
        }
    }
}
