import SwiftUI
import MapKit
import RpplCore

struct SessionMapView: View {
    let tracks: [[LocationSample]]
    var allowsInteraction: Bool = false
    /// Style toggle on interactive maps (session card, fullscreen); not ride thumbnails.
    var showsStyleToggle: Bool = false
    /// Device-agnostic frame from `derived/view.json` for first paint before tracks load.
    var preferredFrame: MapTrackFrame? = nil

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false

    init(
        locations: [LocationSample],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
    }

    init(
        tracks: [[LocationSample]],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
        self.preferredFrame = preferredFrame
    }

    private var interactionModes: MapInteractionModes {
        allowsInteraction ? [.pan, .zoom, .pitch, .rotate] : []
    }

    private var mapStyle: MapStyle {
        usesSatellite ? .hybrid : .standard
    }

    var body: some View {
        GeometryReader { geo in
            Map(position: $position, interactionModes: interactionModes) {
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
            .mapStyle(mapStyle)
            .onMapCameraChange(frequency: .onEnd) { context in
                guard allowsInteraction, let fitted else { return }
                showReset = !Self.isNearFittedCamera(context.camera, fit: fitted)
            }
            .overlay(alignment: .topLeading) {
                if showsStyleToggle {
                    mapStyleToggle
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if allowsInteraction, showReset {
                    Button {
                        applyFittedCamera(animated: true)
                        showReset = false
                    } label: {
                        Text("Reset")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.rpplText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Reset map")
                }
            }
            .onAppear {
                updateFit(for: geo.size, forceApply: true)
            }
            .onChange(of: geo.size) { _, newSize in
                updateFit(for: newSize, forceApply: !showReset)
            }
            .onChange(of: trackSignature) { _, _ in
                showReset = false
                updateFit(for: geo.size, forceApply: true)
            }
            .onChange(of: preferredFrameSignature) { _, _ in
                if tracks.isEmpty {
                    showReset = false
                    updateFit(for: geo.size, forceApply: true)
                }
            }
        }
    }

    private var preferredFrameSignature: String {
        guard let preferredFrame else { return "nil" }
        return "\(preferredFrame.centerLatitude)-\(preferredFrame.centerLongitude)-\(preferredFrame.headingDegrees)-\(preferredFrame.spanWidthMeters)"
    }

    private var trackSignature: String {
        let count = tracks.reduce(0) { $0 + $1.count }
        let first = tracks.first?.first
        let last = tracks.last?.last
        return "\(tracks.count)-\(count)-\(first?.latitude ?? 0)-\(last?.longitude ?? 0)"
    }

    private var mapStyleToggle: some View {
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
        .padding(10)
        .accessibilityLabel(
            usesSatellite
                ? String(localized: "Show standard map")
                : String(localized: "Show satellite map")
        )
    }

    private func updateFit(for size: CGSize, forceApply: Bool) {
        let coords = MapTrackFitter.coordinates(fromTracks: tracks)
        let next: MapTrackFit?
        if coords.count >= 2 {
            next = MapTrackFitter.fit(
                locations: coords,
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

/// Full-screen interactive track map (pan / zoom / pitch / rotate + style toggle).
/// System Back dismisses when pushed on a `NavigationStack`.
struct SessionMapFullscreenView: View {
    let tracks: [[LocationSample]]
    let title: String
    var preferredFrame: MapTrackFrame? = nil

    init(
        locations: [LocationSample],
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.title = title
        self.preferredFrame = preferredFrame
    }

    init(
        tracks: [[LocationSample]],
        title: String,
        preferredFrame: MapTrackFrame? = nil
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.title = title
        self.preferredFrame = preferredFrame
    }

    var body: some View {
        SessionMapView(
            tracks: tracks,
            allowsInteraction: true,
            showsStyleToggle: true,
            preferredFrame: preferredFrame
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.rpplBackground)
        .tint(Color.rpplAccent)
        .accessibilityLabel(title)
    }
}
