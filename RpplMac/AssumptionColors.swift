import SwiftUI
import RpplCore

enum AssumptionColors {
    static func color(for code: String) -> Color {
        switch code {
        case LabelCodes.waiting:
            return .gray
        case LabelCodes.riding:
            return .blue
        case LabelCodes.swimming:
            return .teal
        case LabelCodes.walking:
            return .orange
        default:
            return .purple
        }
    }
}
