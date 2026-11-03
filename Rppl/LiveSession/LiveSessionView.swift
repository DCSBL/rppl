import RpplCore
import SwiftUI

/// The running session: time, set, and one big "Next set" button.
struct LiveSessionView: View {
    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = LiveSessionController.shared
    @State private var confirmStop = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                if let live = controller.session {
                    content(live)
                } else {
                    ContentUnavailableView("No session running", systemImage: "clock")
                }
            }
            .navigationTitle("Session running")
            .navigationBarTitleDisplayMode(.inline)
            .rpplBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onChange(of: controller.session == nil) { _, ended in if ended { dismiss() } }
            .alert("Stop session?", isPresented: $confirmStop, presenting: controller.session) { live in
                Button("Stop session", role: .destructive) { stop() }
                if live.isDiscardable(at: .now) {
                    Button("Discard session", role: .destructive) { controller.discard() }
                }
                Button("Keep going", role: .cancel) {}
            } message: { live in
                Text(stopMessage(live))
            }
            .alert("Could not save session", isPresented: Binding(
                get: { controller.errorText != nil }, set: { if !$0 { controller.errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorText ?? "")
            }
        }
    }

    private func content(_ live: LiveSession) -> some View {
        VStack(spacing: RpplDesign.tileSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
                    InfoTileGrid {
                        InfoTile("Session", metric: .duration) { LiveTimer(since: live.startedAt) }
                        if live.mode == .setsAndTime {
                            InfoTile("Set", metric: .sets) {
                                MetricValue("\(live.setCount)")
                            }
                        }
                    }
                    if live.mode == .setsAndTime {
                        InfoTile("Since start of set", metric: .duration) {
                            if let start = live.currentSetStart {
                                LiveTimer(since: start)
                            } else {
                                Text("Tap First set when the first set starts.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.rpplMuted)
                            }
                        }
                    }
                    LiveConditionsTiles(park: controller.park)
                    Text(subtitle(live))
                        .font(.footnote)
                        .foregroundStyle(Color.rpplMuted)
                }
                .padding(RpplDesign.tileSpacing)
            }
            VStack(spacing: 10) {
                if live.mode == .setsAndTime {
                    Button { controller.nextSet() } label: {
                        Text(live.setCount == 0 ? "First set" : "Next set").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.extraLarge)
                }
                Button(role: .destructive) { confirmStop = true } label: {
                    Text("Stop session").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
                .disabled(isSaving)
            }
            .padding([.horizontal, .bottom], RpplDesign.tileSpacing)
        }
    }

    private func subtitle(_ live: LiveSession) -> String {
        let started = live.startedAt.formatted(date: .omitted, time: .shortened)
        guard let place = controller.park?.compactName ?? live.spotName else {
            return String(localized: "Tracked on iPhone, started \(started)")
        }
        return String(localized: "\(place) · tracked on iPhone, started \(started)")
    }

    private func stopMessage(_ live: LiveSession) -> String {
        let elapsed = LogbookFormatting.duration(Date.now.timeIntervalSince(live.startedAt))
        if live.mode == .timeOnly { return String(localized: "You kept time for \(elapsed). Then it goes into your logbook.") }
        return String(localized: "You tracked \(LogbookFormatting.setCount(live.setCount)) in \(elapsed). Then it goes into your logbook.")
    }

    private func stop() {
        isSaving = true
        Task {
            let id = await controller.finish()
            isSaving = false
            if let id { onSaved(id) }
        }
    }
}

/// A system-driven count-up: no per-second updates from the app.
struct LiveTimer: View {
    let since: Date

    var body: some View {
        Text(since, style: .timer)
            .font(.title.bold().monospacedDigit())
            .foregroundStyle(Color.rpplText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
