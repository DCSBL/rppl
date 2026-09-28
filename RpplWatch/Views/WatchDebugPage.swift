import SwiftUI
import WatchKit
import RpplCore

/// Debug-only: drive detection state and preview a smaller watch's screen size without a real
/// session or a second device. Gated by `AppReleaseChannel.allowsDebugTools` at the call site.
struct WatchDebugPage: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Simulate")
                    .font(.headline)
                ForEach(DetectionSimulationMode.allCases, id: \.self) { mode in
                    Button(mode.buttonTitle) {
                        session.applyDetectionSimulation(mode)
                    }
                    .buttonStyle(.bordered)
                    .tint(session.detectionSimulationMode == mode ? .accentColor : .gray)
                    // `cycleDetectionSimulation` guards the same way; product pause owns detection
                    // state (`product_pause`/`product_resume`) while paused.
                    .disabled(session.isProductPaused)
                }

                Divider()

                Text("code=\(session.detectionCode) last=\(session.lastConfidentCode)")
                    .font(.caption2)
                Text("paused=\(session.isProductPaused ? "yes" : "no")")
                    .font(.caption2)

                Divider()

                Text("Screen size")
                    .font(.headline)
                ForEach(DebugScreenSize.allCases, id: \.self) { size in
                    Button(size.label) {
                        session.debugScreenSize = size
                    }
                    .buttonStyle(.bordered)
                    .tint(session.debugScreenSize == size ? .accentColor : .gray)
                }

                let bounds = WKInterfaceDevice.current().screenBounds
                Text("actual=\(Int(bounds.width))x\(Int(bounds.height))pt")
                    .font(.caption2)

                Divider()

                Text("On stop")
                    .font(.headline)
                Button(session.debugDiscardOnStop ? "Discard on stop: ON" : "Discard on stop: OFF") {
                    session.debugDiscardOnStop.toggle()
                }
                .buttonStyle(.bordered)
                .tint(session.debugDiscardOnStop ? .red : .gray)
                Text("No HealthKit save, no on-disk package, no phone transfer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
