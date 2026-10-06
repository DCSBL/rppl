import SwiftUI
import RpplCore

struct SessionControlsPage: View {
    @Bindable var session: WatchSessionController
    @State private var showStopConfirmation = false
    @State private var showDiscardConfirmation = false
    /// Frozen when Stop is tapped so the dialog does not change while it is open.
    @State private var offersDebugDiscard = false

    var body: some View {
        // Always On: keep every control visible and full-brightness (stable layout; don’t remove).
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
                .disabled(session.isStopping || session.isPausing)
            }

            waterLockButton

            if let worst = session.recordingIssues.first {
                Text(RecordingIssueText.label(for: worst.code))
                    .font(.caption2)
                    .foregroundStyle(worst.severity == .critical ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 4)
        .task {
            session.refreshWaterLockState()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                session.refreshWaterLockState()
            }
        }
        .confirmationDialog(
            "End session?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("End session", role: .destructive) {
                WakeLog.debug(.ui, "confirm Stop session")
                Task { await session.stopSession() }
            }
            if WatchDebugTools.isEnabled, offersDebugDiscard {
                Button("Stop and discard data", role: .destructive) {
                    WakeLog.debug(.ui, "debug: confirm Stop and discard data")
                    Task { await session.discardSession() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops recording and queues transfer to iPhone.")
        }
        .confirmationDialog(
            "Discard session?",
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
            Text("Under 30 seconds and no sets. Discard deletes it here. Keep transfers to iPhone.")
        }
    }

    @ViewBuilder
    private var waterLockButton: some View {
        let label = Label {
            Text(
                session.isWaterLockEnabled
                    ? String(localized: "Disable Water Lock")
                    : String(localized: "Enable Water Lock")
            )
        } icon: {
            Image(systemName: session.isWaterLockEnabled ? "drop.fill" : "drop")
        }

        Group {
            if session.isWaterLockEnabled {
                Button {
                    WakeLog.debug(.ui, "tap Water Lock (locked)")
                } label: {
                    label
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            } else {
                Button {
                    WakeLog.debug(.ui, "tap Enable Water Lock")
                    Task { await session.enableWaterLock() }
                } label: {
                    label
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(session.isStopping || session.isWaterLockEnabled || !session.canEnableWaterLock)
        .accessibilityHint(
            session.isWaterLockEnabled
                ? String(localized: "Turn Digital Crown to unlock")
                : String(localized: "Locks the screen to prevent accidental taps")
        )
    }

    private func presentStopFlow() {
        let duration = session.computeElapsed(at: Date())
        offersDebugDiscard = TinySessionPolicy.shouldOfferDebugDiscard(duration: duration)
        if TinySessionPolicy.shouldOfferDiscard(duration: duration, setCount: session.setCount) {
            WakeLog.debug(.ui, "tiny session — offer discard duration=\(Int(duration))s sets=\(session.setCount)")
            showDiscardConfirmation = true
        } else {
            showStopConfirmation = true
        }
    }
}
