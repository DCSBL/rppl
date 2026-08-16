import SwiftUI
import RpplCore

struct SessionControlsPage: View {
    @Bindable var session: WatchSessionController

    var body: some View {
        VStack(spacing: 8) {
            if session.isStopping {
                ProgressView("Stopping…")
                    .progressViewStyle(.circular)
            } else {
                Button("Stop", role: .destructive) {
                    WakeLog.debug(.ui, "tap Stop session")
                    Task { await session.stopSession() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Button("Pause") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .foregroundStyle(.secondary)

            Button("Water Lock") {
                WakeLog.debug(.ui, "tap Water Lock")
                session.enableWaterLock()
            }
            .buttonStyle(.bordered)
            .disabled(session.isStopping)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 4)
    }
}
