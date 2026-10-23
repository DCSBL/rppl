import MapKit
import SwiftUI

/// The second button of a full-screen map: "here" where you look for parks, "reset" (back to the fitted
/// frame) where you look at a session or a set.
enum MapScreenAction {
    case here(() -> Void)
    case reset(() -> Void)
}

/// The buttons of every full-screen map, in the navigation bar so they sit with the other bar buttons
/// (vertically under the status bar on iPhone Duo): map style, then here or reset. Back is the navigation
/// bar's own; the compass is the map's own control (`.mapControls`), placed by MapKit.
struct MapScreenToolbar: ToolbarContent {
    @Binding var usesSatellite: Bool
    let action: MapScreenAction

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // The icon shows what a tap switches to.
            if usesSatellite {
                Button("Show standard map", systemImage: "map") { usesSatellite = false }
            } else {
                Button("Show satellite map", systemImage: "globe.europe.africa") { usesSatellite = true }
            }
            switch action {
            case .here(let perform):
                Button("Center on my location", systemImage: "location", action: perform)
            case .reset(let perform):
                Button("Reset map", systemImage: "arrow.counterclockwise", action: perform)
            }
        }
    }
}

extension View {
    /// Lays out a full-screen map: it keeps to the safe area sideways, so the map's own framing (fit, reset,
    /// centering) sees only the part not covered by a split view's sidebar or the vertical bar of iPhone Duo;
    /// the background extension effect still draws it to the edges. Top and bottom it runs under the bars.
    func mapScreen() -> some View {
        ignoresSafeArea(edges: .vertical)
            .backgroundExtensionEffect()
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}
