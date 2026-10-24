import MapKit
import RpplCore
import SwiftUI

/// The buttons of every full-screen map, in the navigation bar so they sit with the other bar buttons
/// (vertically under the status bar on iPhone Duo): map style, reset (back to the framed track or park),
/// then my location. Each shows only when its action is given. Back is the navigation bar's own. The
/// compass is a bar item only for the bar layouts of `MapCompassLayout` (`compassScope` set by `mapScreen`).
struct MapScreenToolbar: ToolbarContent {
    @Binding var usesSatellite: Bool
    var reset: (() -> Void)?
    var locate: (() -> Void)?
    var compassScope: Namespace.ID?
    var compassLayout: MapCompassLayout = .floatingCorner

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
            if let compassScope, compassLayout == .barGroup {
                MapCompass(scope: compassScope)
            }
        }
        if let compassScope, compassLayout == .barItem {
            // Its own round control without glass, shown once the map turns.
            ToolbarItem(placement: .topBarTrailing) {
                MapCompass(scope: compassScope)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if let compassScope, compassLayout == .barItemGlass {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                MapCompass(scope: compassScope)
            }
        }
        if let compassScope, compassLayout == .barLeading {
            ToolbarItem(placement: .topBarLeading) {
                MapCompass(scope: compassScope)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if let compassScope, compassLayout == .barBottom {
            ToolbarItem(placement: .bottomBar) {
                MapCompass(scope: compassScope)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

/// Where a full-screen map puts its compass. The Debug screen picks one (TestFlight and debug builds only;
/// the App Store build always uses `defaultLayout`), so the layouts can be compared on a real iPhone Duo.
enum MapCompassLayout: String, CaseIterable, Identifiable {
    /// Floats on the map in the top trailing corner of the uncovered area, clear of the bar column.
    case floatingCorner
    /// Floats in the top trailing corner of the window; nothing else aligns to it, bars can cover it.
    case floatingWindowCorner
    /// Floats in the top leading corner of the uncovered area.
    case floatingLeading
    /// MapKit's own placement (`.mapControls`), inside the safe area, clear of the bar buttons.
    case mapKitDefault
    /// A bar item without glass under the map buttons (#556).
    case barItem
    /// A bar item in its own glass capsule under the map buttons, as in Photos.
    case barItemGlass
    /// Inside the capsule of the map buttons.
    case barGroup
    /// Experimental: a bar item on the leading side.
    case barLeading
    /// Experimental: a bottom bar item.
    case barBottom
    /// No compass. The map still rotates with two fingers, and reset points it north again.
    case hidden

    static let defaultLayout = MapCompassLayout.floatingCorner

    var id: String { rawValue }

    /// The layout in effect for a stored value: debug builds and TestFlight honor it.
    static func resolved(_ storedValue: String) -> MapCompassLayout {
        guard AppReleaseChannel.allowsDebugTools else { return defaultLayout }
        return MapCompassLayout(rawValue: storedValue) ?? defaultLayout
    }

    /// Whether the map itself places the compass (nothing for `mapScreen` to draw or add to the bars).
    var isPlacedByMapKit: Bool { self == .mapKitDefault }

    /// Where a floating compass sits in the map, nil for the other layouts.
    var floatingAlignment: Alignment? {
        switch self {
        case .floatingCorner, .floatingWindowCorner: .topTrailing
        case .floatingLeading: .topLeading
        default: nil
        }
    }

    var title: String {
        switch self {
        case .floatingCorner: "Floating, top corner (now)"
        case .floatingWindowCorner: "Floating, window corner"
        case .floatingLeading: "Floating, top leading"
        case .mapKitDefault: "MapKit default"
        case .barItem: "Bar item, no glass (#556)"
        case .barItemGlass: "Bar item, own glass"
        case .barGroup: "Bar item, in the buttons"
        case .barLeading: "Bar item, leading (experimental)"
        case .barBottom: "Bottom bar item (experimental)"
        case .hidden: "No compass, rotate only"
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

/// See `mapScreen(viewport:usesSatellite:reset:locate:)`.
private struct MapScreenLayout: ViewModifier {
    @Binding var viewport: MapViewport
    @Binding var usesSatellite: Bool
    let reset: (() -> Void)?
    let locate: (() -> Void)?
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(AppSettingsKey.debugMapCompassLayout) private var storedCompassLayout = MapCompassLayout.defaultLayout.rawValue
    @Namespace private var scope
    @State private var safeArea = EdgeInsets()

    /// Space between the compass and the bars or the window edge.
    private static let compassMargin: CGFloat = 12

    private var compassLayout: MapCompassLayout { .resolved(storedCompassLayout) }

    /// iPhone Duo: the bars stand in a column on the trailing side, under the status bar, and nothing covers
    /// the top or bottom of the map. Only that column and a sidebar on the other side count there.
    private var mapSafeArea: EdgeInsets {
        guard safeArea.trailing > safeArea.leading + 20 else { return safeArea }
        return EdgeInsets(top: 0, leading: safeArea.leading, bottom: 0, trailing: safeArea.trailing)
    }

    /// Distance from the window edge on the compass's side.
    private func compassInset(_ alignment: Alignment) -> CGFloat {
        switch compassLayout {
        case .floatingWindowCorner: Self.compassMargin
        case .floatingLeading: safeArea.leading + Self.compassMargin
        default: mapSafeArea.trailing + Self.compassMargin
        }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.mapScreenScope, scope)
            .background {
                // Inside the padding below: the whole map, with the covered part as its safe area.
                Color.clear.onGeometryChange(for: MapViewport.self) { proxy in
                    MapViewport(size: proxy.size, safeArea: proxy.safeAreaInsets, layoutDirection: layoutDirection)
                } action: { viewport = $0 }
            }
            .safeAreaPadding(mapSafeArea)
            .ignoresSafeArea()
            // Floating layouts: a bar item put a band across the top on iPhone Duo, and MapKit's own
            // placement sat under the buttons.
            .overlay(alignment: compassLayout.floatingAlignment ?? .topTrailing) {
                if let alignment = compassLayout.floatingAlignment {
                    MapCompass(scope: scope)
                        .padding(.top, mapSafeArea.top + Self.compassMargin)
                        .padding(alignment == .topLeading ? .leading : .trailing, compassInset(alignment))
                        .ignoresSafeArea()
                }
            }
            .toolbar {
                MapScreenToolbar(
                    usesSatellite: $usesSatellite,
                    reset: reset,
                    locate: locate,
                    compassScope: scope,
                    compassLayout: compassLayout
                )
            }
            .mapScope(scope)
            .background {
                Color.clear.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                    safeArea = insets
                    WakeLog.debug(.ui, "map screen safe area top=\(Int(insets.top)) leading=\(Int(insets.leading)) bottom=\(Int(insets.bottom)) trailing=\(Int(insets.trailing))")
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

extension EnvironmentValues {
    /// Set by `mapScreen`: the map passes it to `Map(scope:)` so the floating compass follows it.
    @Entry var mapScreenScope: Namespace.ID? = nil
}

extension View {
    /// Lays out a full-screen map: it draws to every edge, under the bars and a split view's sidebar,
    /// while the parts those cover stay its safe area. MapKit keeps its scale and legal text inside it,
    /// the compass floats in its top trailing corner, and `viewport` tells a camera what part is visible.
    /// Adds the `MapScreenToolbar`.
    /// The map passes `mapScreenScope` to `Map(scope:)` and uses `mapScreenControls(scope:)`.
    func mapScreen(
        viewport: Binding<MapViewport> = .constant(MapViewport()),
        usesSatellite: Binding<Bool>,
        reset: (() -> Void)? = nil,
        locate: (() -> Void)? = nil
    ) -> some View {
        modifier(MapScreenLayout(viewport: viewport, usesSatellite: usesSatellite, reset: reset, locate: locate))
    }

    /// The map's own controls: the scale, and the compass only for `MapCompassLayout.mapKitDefault`.
    func mapScreenControls(scope: Namespace.ID?) -> some View {
        modifier(MapScreenControls(placesCompass: scope == nil))
    }
}

private struct MapScreenControls: ViewModifier {
    /// A map outside `mapScreen` keeps MapKit's compass.
    let placesCompass: Bool
    @AppStorage(AppSettingsKey.debugMapCompassLayout) private var storedCompassLayout = MapCompassLayout.defaultLayout.rawValue

    func body(content: Content) -> some View {
        if placesCompass || MapCompassLayout.resolved(storedCompassLayout).isPlacedByMapKit {
            content.mapControls {
                MapCompass()
                MapScaleView()
            }
        } else {
            content.mapControls {
                MapScaleView()
            }
        }
    }
}
