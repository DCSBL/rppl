import SwiftUI
import RpplCore

struct SessionControlsPage: View {
    @Bindable var session: WatchSessionController
    @State private var showStopConfirmation = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            if session.isStopping {
                ProgressView(session.statusText)
                    .progressViewStyle(.circular)
            } else {
                Button("Stop", role: .destructive) {
                    WakeLog.debug(.ui, "tap Stop session")
                    presentStopFlow()
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
        .confirmationDialog(
            "End Session?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                WakeLog.debug(.ui, "confirm Stop session")
                Task { await session.stopSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops recording and queues transfer to iPhone.")
        }
        .confirmationDialog(
            "Discard Session?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                WakeLog.debug(.ui, "confirm Discard tiny session")
                Task { await session.discardSession() }
            }
            Button("Keep") {
                WakeLog.debug(.ui, "confirm Keep tiny session (transfer)")
                Task { await session.stopSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Under 30 seconds and no rides. Discard deletes it here. Keep transfers to iPhone.")
        }
    }

    private func presentStopFlow() {
        let duration = session.computeElapsed(at: Date())
        if TinySessionPolicy.shouldOfferDiscard(duration: duration, rideCount: session.rideCount) {
            WakeLog.debug(.ui, "tiny session — offer discard duration=\(Int(duration))s rides=\(session.rideCount)")
            showDiscardConfirmation = true
        } else {
            showStopConfirmation = true
        }
    }
}
