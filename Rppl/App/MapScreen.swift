import MapKit
import SwiftUI

/// The second button of a full-screen map: "here" where you look for parks, "reset" (back to the fitted
/// frame) where you look at a session or a set.
enum MapScreenAction {
    case here(() -> Void)
    case reset(() -> Void)
}

/// The buttons of every full-screen map, in the navigation bar so they sit with the other bar buttons
/// (vertically under the status bar on iPhone Duo): map style, here or reset, then the compass.
/// Back is the navigation bar's own. The compass needs `.mapScope(scope)` on a view around both the map
/// and this toolbar, and the map built with the same `scope`.
struct MapScreenToolbar: ToolbarContent {
    @Binding var usesSatellite: Bool
    let action: MapScreenAction
    let scope: Namespace.ID

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
            MapCompass(scope: scope)
        }
    }
}
