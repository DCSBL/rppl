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

            if session.isProductPaused {
                Button("Resume") {
                    WakeLog.debug(.ui, "tap Resume session")
                    session.resumeSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(session.isStopping)
            } else {
                Button("Pause") {
                    WakeLog.debug(.ui, "tap Pause session")
                    Task { await session.pauseSession() }
                }
                .buttonStyle(.bordered)
                .disabled(session.isStopping)
            }

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
