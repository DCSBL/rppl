import SwiftUI

/// Always On / reduced-luminance chrome (HIG). Dim secondary; keep primary; stable layout.
enum AlwaysOnLuminance {
    /// Opacity for labels, status, and other secondary chrome when luminance is reduced.
    static let secondaryChromeOpacity: Double = 0.45
    /// Mild dim for supporting metric values (not the primary hero number).
    static let supportingMetricOpacity: Double = 0.7
}

extension View {
    /// Dim secondary chrome under Always On; no-op when luminance is full.
    func alwaysOnSecondaryChrome(_ isLuminanceReduced: Bool) -> some View {
        opacity(isLuminanceReduced ? AlwaysOnLuminance.secondaryChromeOpacity : 1)
    }

    /// Mild dim for supporting metrics; primary hero stays at full opacity.
    func alwaysOnSupportingMetric(_ isLuminanceReduced: Bool) -> some View {
        opacity(isLuminanceReduced ? AlwaysOnLuminance.supportingMetricOpacity : 1)
    }
}
