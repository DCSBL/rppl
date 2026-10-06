import RpplCore
import SwiftUI

/// Hidden debug screen (press-and-hold the logo on the About page): debug links on top, then the last 100 warnings/failures logged (kept across restarts) via `WakeLog`, across every category
/// (sync, transfer, water, …), newest first. Cheap throwaway list — this exists so a developer can
/// see *why* something silently failed (e.g. a water-temperature fetch) without attaching Console.app.
struct DebugLogView: View {
    @Environment(\.openURL) private var openURL
    @State private var entries: [WakeLog.Entry] = WakeLog.recentEntries()
    @State private var showMail = false

    var body: some View {
        List {
            Section {
                #if PARK_ARRIVAL_NOTIFICATIONS
                NavigationLink {
                    ParkArrivalDebugView()
                } label: {
                    Label("Debug park arrival", systemImage: "ladybug")
                }
                #endif
                NavigationLink {
                    ParkWaterTemperatureDebugView()
                } label: {
                    Label("Debug water temperature", systemImage: "ladybug")
                }
            }

            Section("Log") {
                logRows
            }
        }
        .navigationTitle("Debug")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export", systemImage: "square.and.arrow.up") { DebugLogShare.share() }
                    Button("Send to Rppl", systemImage: "envelope") { sendToRppl() }
                    Button("Clear", systemImage: "trash", role: .destructive) {
                        WakeLog.clearHistory()
                        entries = []
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel(Text("Debug log actions"))
            }
        }
        .sheet(isPresented: $showMail) {
            DebugLogMailComposer { showMail = false }
                .ignoresSafeArea()
        }
        .refreshable { entries = WakeLog.recentEntries() }
        .task { entries = WakeLog.recentEntries() }
    }

    @ViewBuilder
    private var logRows: some View {
        if entries.isEmpty {
            Text("No warnings or failures logged yet.")
                .foregroundStyle(Color.rpplMuted)
        } else {
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    private func sendToRppl() {
        if MailAvailability.canSend {
            showMail = true
        } else if let url = DebugLogShare.mailtoURL() {
            openURL(url)
        } else {
            DebugLogShare.share()
        }
    }

    @ViewBuilder
    private func row(_ entry: WakeLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.formatted)
                .font(.caption.monospaced())
                .foregroundStyle(entry.level == .error ? Color.red : Color.orange)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DebugLogView()
    }
}
