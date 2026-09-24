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
    var rendering: SessionMapRendering = .flat
    var allowsInteraction: Bool = false
    /// Satellite toggle on interactive maps.
    var showsStyleToggle: Bool = false
    var preferredFrame: MapTrackFrame? = nil
    var layout: SessionMapLayout = .embedded
    /// Park cable outlines drawn as a thin line beneath the tracks.
    var cableOverlays: [[CLLocationCoordinate2D]] = []

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false
    @State private var orbitDegrees: Double = 0
    @State private var orbitTask: Task<Void, Never>?

    /// Camera degrees per orbit step in `flyover`.
    private static let orbitStepDegrees: Double = 8
    private static let orbitStepSeconds: Double = 1
    /// Direction chevrons drawn along a soloed set.
    private static let directionMarkerCount = 5
    /// Seconds of riding kept bright behind the replay head.
    private static let replayTrailSeconds: TimeInterval = 6

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

    /// Per-set tracks for the appearance layers. Set cards pass plain tracks instead.
    private var renderTracks: [SessionSetTrack] {
        if !rendering.setTracks.isEmpty { return rendering.setTracks }
        return tracks.enumerated().map { offset, samples in
            SessionSetTrack(setIndex: offset, setNumber: offset + 1, samples: samples)
        }
    }

    /// Requested appearance, downgraded when its data has not loaded yet.
    private var effectiveAppearance: SessionMapAppearance {
        let requested = rendering.appearance
        guard requested.needsSetTracks else { return requested }
        guard !renderTracks.isEmpty else { return .flat }
        if requested == .replay, rendering.timeline.isEmpty { return .sets }
        return requested
    }

    private var resolvedSpeedScale: TrackSpeedScale? {
        if let scale = rendering.speedScale { return scale }
        return TrackSpeedBands.scale(forTracks: renderTracks.map(\.samples))
    }

    private var mapStyle: MapStyle {
        if effectiveAppearance == .flyover {
            return .imagery(elevation: .realistic)
        }
        // `flat` stays the untouched baseline to compare the other looks against.
        if effectiveAppearance == .flat {
            return usesSatellite ? .hybrid : .standard
        }
        if usesSatellite {
            return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        }
        // Muted basemap with no POI pins: the track is the only saturated thing on screen.
        return .standard(
            elevation: .flat,
            emphasis: .muted,
            pointsOfInterest: .excludingAll,
            showsTraffic: false
        )
    }

    private var cameraPitch: Double {
        effectiveAppearance == .flyover ? 58 : 0
    }

    /// A pitched camera needs to sit further back to keep the whole track in frame.
    private var cameraDistanceMultiplier: Double {
        effectiveAppearance == .flyover ? 1.5 : 1
    }

    private var orbitsNow: Bool {
        rendering.orbits && effectiveAppearance == .flyover && !allowsInteraction
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
        .onAppear { syncOrbit() }
        .onChange(of: orbitSignature) { _, _ in syncOrbit() }
        .onDisappear {
            orbitTask?.cancel()
            orbitTask = nil
        }
    }

    // MARK: - Map content

    @MapContentBuilder
    private var mapContent: some MapContent {
        ForEach(Array(cableOverlays.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: item.element)
                .stroke(Color.rpplAccent, lineWidth: 1.5)
        }
        switch effectiveAppearance {
        case .flat:
            flatContent
        case .sets:
            setsContent(lineWidth: SessionTrackPalette.coreLineWidth)
        case .speed:
            speedContent
        case .solo:
            soloContent
        case .replay:
            replayContent
        case .flyover:
            setsContent(lineWidth: SessionTrackPalette.flyoverLineWidth)
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
    private func setsContent(lineWidth: CGFloat) -> some MapContent {
        let visible = renderTracks
        // Casings first, cores second: a later set must not paint over an earlier core.
        ForEach(Array(visible.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element.samples))
                .stroke(
                    SessionTrackPalette.casing,
                    style: SessionTrackPalette.strokeStyle(width: lineWidth + 3)
                )
        }
        ForEach(Array(visible.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element.samples))
                .stroke(
                    SessionTrackPalette.setColor(position: item.offset, of: visible.count),
                    style: SessionTrackPalette.strokeStyle(width: lineWidth)
                )
        }
        startAnnotation
    }

    @MapContentBuilder
    private var speedContent: some MapContent {
        let scale = resolvedSpeedScale
        let runs = speedRuns(scale: scale)
        ForEach(Array(runs.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element.coordinates))
                .stroke(
                    SessionTrackPalette.casing,
                    style: SessionTrackPalette.strokeStyle(width: SessionTrackPalette.casingLineWidth)
                )
        }
        ForEach(Array(runs.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element.coordinates))
                .stroke(
                    SessionTrackPalette.speedColor(
                        fraction: scale?.bandFraction(item.element.bandIndex) ?? 0.5
                    ),
                    style: SessionTrackPalette.strokeStyle(width: 4)
                )
        }
        startAnnotation
    }

    @MapContentBuilder
    private var soloContent: some MapContent {
        if let focused = focusedTrack {
            let visible = renderTracks
            let color = SessionTrackPalette.setColor(
                position: focusedPosition ?? 0,
                of: visible.count
            )
            ForEach(Array(visible.enumerated()), id: \.offset) { item in
                if item.element.setIndex != focused.setIndex {
                    MapPolyline(coordinates: coordinates(item.element.samples))
                        .stroke(
                            SessionTrackPalette.ghost,
                            style: SessionTrackPalette.strokeStyle(
                                width: SessionTrackPalette.ghostLineWidth
                            )
                        )
                }
            }
            MapPolyline(coordinates: coordinates(focused.samples))
                .stroke(
                    SessionTrackPalette.casing,
                    style: SessionTrackPalette.strokeStyle(
                        width: SessionTrackPalette.casingLineWidth
                    )
                )
            MapPolyline(coordinates: coordinates(focused.samples))
                .stroke(color, style: SessionTrackPalette.strokeStyle(width: 4))
            ForEach(directionMarkers(for: focused.samples)) { marker in
                Annotation("", coordinate: marker.coordinate) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(marker.bearing))
                        .padding(3)
                        .background(SessionTrackPalette.casing, in: Circle())
                }
                .annotationTitles(.hidden)
            }
            if let first = focused.samples.first {
                endpointAnnotation("Start", at: coordinate(first), symbol: "flag.fill", fill: color)
            }
            if let last = focused.samples.last {
                endpointAnnotation(
                    "Finish",
                    at: coordinate(last),
                    symbol: "flag.checkered",
                    fill: SessionTrackPalette.casing
                )
            }
        } else {
            setsContent(lineWidth: SessionTrackPalette.coreLineWidth)
        }
    }

    @MapContentBuilder
    private var replayContent: some MapContent {
        let timeline = rendering.timeline
        let progress = rendering.replayProgress
        let drawn = timeline.polylines(upToProgress: progress)
        let visible = renderTracks

        ForEach(Array(visible.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element.samples))
                .stroke(
                    SessionTrackPalette.ghost.opacity(0.5),
                    style: SessionTrackPalette.strokeStyle(
                        width: SessionTrackPalette.ghostLineWidth
                    )
                )
        }
        ForEach(Array(drawn.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element))
                .stroke(
                    SessionTrackPalette.casing,
                    style: SessionTrackPalette.strokeStyle(
                        width: SessionTrackPalette.casingLineWidth
                    )
                )
        }
        ForEach(Array(drawn.enumerated()), id: \.offset) { item in
            MapPolyline(coordinates: coordinates(item.element))
                .stroke(
                    SessionTrackPalette.setColor(position: item.offset, of: max(visible.count, 1)),
                    style: SessionTrackPalette.strokeStyle(width: 4)
                )
        }
        let trail = timeline.headTrail(
            upToProgress: progress,
            seconds: Self.replayTrailSeconds
        )
        if trail.count >= 2 {
            MapPolyline(coordinates: coordinates(trail))
                .stroke(
                    SessionTrackPalette.head,
                    style: SessionTrackPalette.strokeStyle(width: 5)
                )
        }
        if let head = timeline.point(atProgress: progress) {
            Annotation("", coordinate: coordinate(head.coordinate)) {
                replayHeadBadge(speedKmh: head.speedKmh)
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private var startAnnotation: some MapContent {
        if let start = startCoordinate {
            endpointAnnotation(
                "Start",
                at: start,
                symbol: "flag.fill",
                fill: SessionTrackPalette.setColor(position: 0, of: max(renderTracks.count, 1))
            )
        }
    }

    private func endpointAnnotation(
        _ title: LocalizedStringKey,
        at coordinate: CLLocationCoordinate2D,
        symbol: String,
        fill: Color
    ) -> some MapContent {
        Annotation(title, coordinate: coordinate) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(fill, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                }
        }
        .annotationTitles(.hidden)
    }

    private func replayHeadBadge(speedKmh: Double?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SessionTrackPalette.head)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().strokeBorder(SessionTrackPalette.casing, lineWidth: 1)
                }
            if let speedKmh {
                Text(LogbookFormatting.speedKilometersPerHour(speedKmh))
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(SessionTrackPalette.casing, in: Capsule())
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

    /// Only `solo` isolates a set; other looks must keep the whole-session framing.
    private var focusedTrack: SessionSetTrack? {
        guard effectiveAppearance == .solo, let soloSetIndex = rendering.soloSetIndex else {
            return nil
        }
        return renderTracks.first { $0.setIndex == soloSetIndex }
    }

    private var focusedPosition: Int? {
        guard let focused = focusedTrack else { return nil }
        return renderTracks.firstIndex { $0.setIndex == focused.setIndex }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        if let sessionMapData { return coordinate(sessionMapData.start) }
        guard let first = renderTracks.first?.samples.first else { return nil }
        return coordinate(first)
    }

    private func speedRuns(scale: TrackSpeedScale?) -> [TrackSpeedRun] {
        guard let scale else { return [] }
        return renderTracks.flatMap { TrackSpeedBands.runs(from: $0.samples, scale: scale) }
    }

    private func directionMarkers(for samples: [LocationSample]) -> [SessionMapDirectionMarker] {
        guard samples.count >= 4 else { return [] }
        let slots = min(Self.directionMarkerCount, samples.count / 3)
        guard slots >= 1 else { return [] }
        var markers: [SessionMapDirectionMarker] = []
        for slot in 0..<slots {
            let position = Double(slot) + 0.5
            let index = Int(position / Double(slots) * Double(samples.count - 2))
            guard index + 1 < samples.count,
                  let bearing = GeoBearing.degrees(from: samples[index], to: samples[index + 1])
            else {
                continue
            }
            markers.append(
                SessionMapDirectionMarker(
                    id: index,
                    coordinate: coordinate(samples[index]),
                    bearing: bearing
                )
            )
        }
        return markers
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

    /// Camera-relevant inputs only — replay progress must not refit mid-playback.
    private var dataSignature: String {
        var signature = "\(effectiveAppearance.rawValue)-\(focusedTrack?.setIndex ?? -1)"
        if let sessionMapData {
            signature += "-session-\(sessionMapData.heatmapTracks.count)-\(sessionMapData.start.latitude)"
        }
        let trackPoints = renderTracks.reduce(0) { $0 + $1.samples.count }
        signature += "-sets-\(renderTracks.count)-\(trackPoints)"
        return signature
    }

    private var orbitSignature: String {
        "\(orbitsNow)-\(fitted == nil)"
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
            distance: fit.cameraDistanceMeters * cameraDistanceMultiplier,
            heading: fit.headingDegrees + orbitDegrees,
            pitch: cameraPitch
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
                camera.heading - (fit.headingDegrees + orbitDegrees)
            )
        )
        let latDelta = abs(camera.centerCoordinate.latitude - fit.centerLatitude)
        let lonDelta = abs(camera.centerCoordinate.longitude - fit.centerLongitude)
        let expectedDistance = fit.cameraDistanceMeters * cameraDistanceMultiplier
        let distanceRatio = abs(camera.distance - expectedDistance) / max(expectedDistance, 1)
        let pitchDelta = abs(camera.pitch - cameraPitch)
        return headingDelta < 3
            && latDelta < 0.00012
            && lonDelta < 0.00012
            && distanceRatio < 0.1
            && pitchDelta < 6
    }

    // MARK: - Orbit

    private func syncOrbit() {
        orbitTask?.cancel()
        orbitTask = nil
        guard orbitsNow else {
            if orbitDegrees != 0 {
                orbitDegrees = 0
                applyFittedCamera(animated: true)
            }
            return
        }
        orbitTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.orbitStepSeconds))
                if Task.isCancelled { return }
                guard let fitted else { continue }
                orbitDegrees += Self.orbitStepDegrees
                withAnimation(.linear(duration: Self.orbitStepSeconds * 1.05)) {
                    position = .camera(camera(for: fitted))
                }
            }
        }
    }
}

private struct SessionMapDirectionMarker: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
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

    var body: some View {
        Group {
            if let sessionMapData {
                SessionMapView(
                    sessionMapData: sessionMapData,
                    rendering: rendering,
                    allowsInteraction: true,
                    showsStyleToggle: true,
                    preferredFrame: preferredFrame,
                    layout: .fullscreen,
                    cableOverlays: cableOverlays
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
