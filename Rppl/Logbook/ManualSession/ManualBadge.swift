import SwiftUI

/// Marks a session typed in by hand rather than recorded.
struct ManualBadge: View {
    var body: some View {
        ParkChip(text: String(localized: "Manual"), systemImage: "pencil", tint: Color.rpplMuted)
    }
}
