import SwiftUI
import MapKit
import RpplCore

struct SessionMapView: View {
    let tracks: [[LocationSample]]
    var allowsInteraction: Bool = false
    /// Style toggle only on the session map card — not ride maps.
    var showsStyleToggle: Bool = false

    @AppStorage(MapBaseStyleSetting.usesSatelliteKey) private var usesSatellite = false
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted: MapTrackFit?
    @State private var showReset = false

    init(
        locations: [LocationSample],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false
    ) {
        self.tracks = locations.count >= 2 ? [locations] : []
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
    }

    init(
        tracks: [[LocationSample]],
        allowsInteraction: Bool = false,
        showsStyleToggle: Bool = false
    ) {
        self.tracks = tracks.filter { $0.count >= 2 }
        self.allowsInteraction = allowsInteraction
        self.showsStyleToggle = showsStyleToggle
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
        }
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
        guard let next = MapTrackFitter.fit(
            locations: coords,
            viewWidth: Double(size.width),
            viewHeight: Double(size.height)
        ) else {
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
