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
        VStack(spacing: 6) {
            if session.isStopping {
                ProgressView(session.statusText)
                    .progressViewStyle(.circular)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        controlTile(
                            "Stop", systemImage: "xmark", tint: .red,
                            disabled: false
                        ) {
                            WakeLog.debug(.ui, "tap Stop session")
                            presentStopFlow()
                        }
                        pauseResumeTile
                    }
                    waterLockTile
                }
            }

            if let worst = session.recordingIssues.first {
                Text(RecordingIssueText.label(for: worst.code))
                    .font(.caption2)
                    .foregroundStyle(worst.severity == .critical ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Grid cell that fills the available width and height: tinted capsule with a symbol, label underneath. No scrolling.
    private func controlTile(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(0.25), in: Capsule())
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var pauseResumeTile: some View {
        if session.isProductPaused {
            controlTile("Resume", systemImage: "play.fill", tint: .green, disabled: session.isStopping) {
                WakeLog.debug(.ui, "tap Resume session")
                session.resumeSession()
            }
        } else {
            controlTile(
                "Pause", systemImage: "pause.fill", tint: .yellow,
                disabled: session.isStopping || session.isPausing
            ) {
                WakeLog.debug(.ui, "tap Pause session")
                Task { await session.pauseSession() }
            }
        }
    }

    private var waterLockTile: some View {
        controlTile(
            "Water",
            systemImage: session.isWaterLockEnabled ? "drop.fill" : "drop",
            tint: .blue,
            disabled: session.isStopping || session.isWaterLockEnabled || !session.canEnableWaterLock
        ) {
            WakeLog.debug(.ui, "tap Enable Water Lock")
            Task { await session.enableWaterLock() }
        }
        .accessibilityLabel(
            session.isWaterLockEnabled
                ? String(localized: "Disable Water Lock")
                : String(localized: "Enable Water Lock")
        )
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
