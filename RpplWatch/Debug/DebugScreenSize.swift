import CoreGraphics
import SwiftUI

/// Debug-only: force the app's root view into a smaller watch's point size so layout can be
/// sanity-checked on real hardware without owning that model. `size` values are approximate
/// published point sizes — cross-check against the live `WKInterfaceDevice.screenBounds` readout
/// on the Debug page.
enum DebugScreenSize: String, CaseIterable, Sendable {
    case actual
    case mm41
    case mm45

    var size: CGSize? {
        switch self {
        case .actual: return nil
        case .mm41: return CGSize(width: 176, height: 215)
        case .mm45: return CGSize(width: 198, height: 242)
        }
    }

    var label: String {
        switch self {
        case .actual: return String(localized: "Actual")
        case .mm41: return String(localized: "41mm")
        case .mm45: return String(localized: "45mm")
        }
    }
}

/// Clips the root view to `size` when set, so layout can be checked against a smaller watch's
/// point size while physically running on a bigger-screen device.
struct DebugScreenSizeOverride: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            content
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            content
        }
    }
}
