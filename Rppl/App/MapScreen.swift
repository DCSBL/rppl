import MapKit
import RpplCore
import SwiftUI

/// The buttons of every full-screen map, in the navigation bar so they sit with the other bar buttons
/// (vertically under the status bar on iPhone Duo): map style, reset (back to the framed track or park,
/// north up), then my location. Each shows only when its action is given. Back is the navigation bar's
/// own. There is no compass: the map still turns with two fingers, and reset turns it back.
struct MapScreenToolbar: ToolbarContent {
    @Binding var usesSatellite: Bool
    var reset: (() -> Void)?
    var locate: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // The icon shows what a tap switches to.
            if usesSatellite {
                Button("Show standard map", systemImage: "map") { usesSatellite = false }
            } else {
                Button("Show satellite map", systemImage: "globe.europe.africa") { usesSatellite = true }
            }
            if let reset {
                Button("Reset map", systemImage: "arrow.counterclockwise", action: reset)
            }
            if let locate {
                Button("Center on my location", systemImage: "location", action: locate)
            }
        }
    }
}

/// Size of a full-screen map and the part of it that bars or a split view's sidebar cover, so a camera
/// can frame what matters in the part that stays visible. MapKit centers a camera in that part itself
/// (the covered part is the map's safe area), so the insets only set how far out a fit zooms.
nonisolated struct MapViewport: Equatable, Sendable {
    var size: CGSize = .zero
    var insets: MapViewInsets = .zero

    init() {}

    init(size: CGSize, safeArea: EdgeInsets, layoutDirection: LayoutDirection) {
        self.size = size
        let isRightToLeft = layoutDirection == .rightToLeft
        insets = MapViewInsets(
            top: Double(safeArea.top),
            left: Double(isRightToLeft ? safeArea.trailing : safeArea.leading),
            bottom: Double(safeArea.bottom),
            right: Double(isRightToLeft ? safeArea.leading : safeArea.trailing)
        )
    }

    /// Camera that shows `center` in the middle of the visible part.
    func camera(centeredOn center: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection = 0) -> MapCamera {
        MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 0)
    }

    /// Camera that fits `region` in the visible part, north up; nil until the map has a size.
    func camera(fitting region: MKCoordinateRegion) -> MapCamera? {
        let metersPerDegree = 111_320.0
        let frame = MapTrackFrame(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            headingDegrees: 0,
            spanWidthMeters: region.span.longitudeDelta * metersPerDegree * cos(region.center.latitude * .pi / 180),
            spanHeightMeters: region.span.latitudeDelta * metersPerDegree
        )
        guard let fit = MapTrackFitter.fit(
            frame: frame,
            viewWidth: Double(size.width),
            viewHeight: Double(size.height),
            insets: insets
        ) else { return nil }
        return MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: fit.centerLatitude, longitude: fit.centerLongitude),
            distance: fit.cameraDistanceMeters,
            heading: 0,
            pitch: 0
        )
    }
}

/// See `mapScreen(viewport:usesSatellite:reset:locate:)`.
private struct MapScreenLayout: ViewModifier {
    @Binding var viewport: MapViewport
    @Binding var usesSatellite: Bool
    let reset: (() -> Void)?
    let locate: (() -> Void)?
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var safeArea = EdgeInsets()
    /// Off screen (a detail pushed over the map), its safe area flips between two values every frame and each
    /// flip lays the map out again, which kept the app busy until it stopped responding. Measurements wait
    /// in `latestSafeArea` until the map is back on screen.
    @State private var isOnScreen = false
    @State private var latestSafeArea = SafeAreaBox()

    /// iPhone Duo: the bars stand in a column on the trailing side, under the status bar, and nothing covers
    /// the top or bottom of the map. Only that column and a sidebar on the other side count there.
    private var mapSafeArea: EdgeInsets {
        guard safeArea.trailing > safeArea.leading + 20 else { return safeArea }
        return EdgeInsets(top: 0, leading: safeArea.leading, bottom: 0, trailing: safeArea.trailing)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.isOnMapScreen, true)
            .background {
                // Inside the padding below: the whole map, with the covered part as its safe area.
                Color.clear.onGeometryChange(for: MapViewport.self) { proxy in
                    MapViewport(size: proxy.size, safeArea: proxy.safeAreaInsets, layoutDirection: layoutDirection)
                } action: { viewport = $0 }
            }
            .safeAreaPadding(mapSafeArea)
            .ignoresSafeArea()
            .toolbar {
                MapScreenToolbar(usesSatellite: $usesSatellite, reset: reset, locate: locate)
            }
            .background {
                Color.clear.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                    latestSafeArea.insets = insets
                    guard isOnScreen else { return }
                    safeArea = insets
                    WakeLog.debug(.ui, "map screen safe area top=\(Int(insets.top)) leading=\(Int(insets.leading)) bottom=\(Int(insets.bottom)) trailing=\(Int(insets.trailing))")
                }
            }
            .onAppear {
                isOnScreen = true
                safeArea = latestSafeArea.insets
            }
            .onDisappear { isOnScreen = false }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

/// Holds the last measured safe area without making the view depend on it.
private final class SafeAreaBox {
    var insets = EdgeInsets()
}

extension EnvironmentValues {
    /// Set by `mapScreen`: the map leaves out its compass (`mapScreenControls()`).
    @Entry var isOnMapScreen = false
}

extension View {
    /// Lays out a full-screen map: it draws to every edge, under the bars and a split view's sidebar,
    /// while the parts those cover stay its safe area. MapKit keeps its scale and legal text inside it
    /// and centers cameras there, and `viewport` tells a fit what part is visible. Adds the
    /// `MapScreenToolbar`. The map uses `mapScreenControls()`.
    func mapScreen(
        viewport: Binding<MapViewport> = .constant(MapViewport()),
        usesSatellite: Binding<Bool>,
        reset: (() -> Void)? = nil,
        locate: (() -> Void)? = nil
    ) -> some View {
        modifier(MapScreenLayout(viewport: viewport, usesSatellite: usesSatellite, reset: reset, locate: locate))
    }

    /// The map's own controls: the scale, and the compass only outside `mapScreen`. A full-screen map has
    /// no compass; it still turns with two fingers, and reset turns it north again.
    func mapScreenControls() -> some View {
        modifier(MapScreenControls())
    }
}

private struct MapScreenControls: ViewModifier {
    @Environment(\.isOnMapScreen) private var isOnMapScreen

    func body(content: Content) -> some View {
        if isOnMapScreen {
            content.mapControls {
                MapScaleView()
            }
        } else {
            content.mapControls {
                MapCompass()
                MapScaleView()
            }
        }
    }
}
