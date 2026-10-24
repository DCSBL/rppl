import MapKit
import RpplCore
import SwiftUI

/// The buttons of every full-screen map, in the navigation bar so they sit with the other bar buttons
/// (vertically under the status bar on iPhone Duo): map style, reset (back to the framed track or park),
/// then my location. Each shows only when its action is given. Back is the navigation bar's own; the
/// compass is the map's own control (`.mapControls`), placed by MapKit inside the safe area.
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
/// can frame what matters in the part that stays visible.
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
        let shifted = MapTrackFitter.center(
            latitude: center.latitude,
            longitude: center.longitude,
            headingDegrees: heading,
            cameraDistanceMeters: distance,
            viewHeight: Double(size.height),
            insets: insets
        )
        return MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: shifted.latitude, longitude: shifted.longitude),
            distance: distance,
            heading: heading,
            pitch: 0
        )
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

/// See `mapScreen(viewport:)`.
private struct MapScreenLayout: ViewModifier {
    @Binding var viewport: MapViewport
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var safeArea = EdgeInsets()

    func body(content: Content) -> some View {
        content
            .background {
                // Inside the padding below: the whole map, with the covered part as its safe area.
                Color.clear.onGeometryChange(for: MapViewport.self) { proxy in
                    MapViewport(size: proxy.size, safeArea: proxy.safeAreaInsets, layoutDirection: layoutDirection)
                } action: { viewport = $0 }
            }
            .safeAreaPadding(safeArea)
            .ignoresSafeArea()
            .background {
                Color.clear.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

extension View {
    /// Lays out a full-screen map: it draws to every edge, under the bars and a split view's sidebar,
    /// while the parts those cover stay its safe area. MapKit keeps its compass, scale and legal text
    /// inside it, clear of the bar buttons; `viewport` tells a camera what part is visible.
    func mapScreen(viewport: Binding<MapViewport> = .constant(MapViewport())) -> some View {
        modifier(MapScreenLayout(viewport: viewport))
    }
}
