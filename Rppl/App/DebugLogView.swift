import RpplCore
import SwiftUI
import UIKit

/// Hidden debug screen (press-and-hold the logo on the About page): debug links on top, then the last 100 warnings/failures logged (kept across restarts) via `WakeLog`, across every category
/// (sync, transfer, water, …), newest first. Cheap throwaway list — this exists so a developer can
/// see *why* something silently failed (e.g. a water-temperature fetch) without attaching Console.app.
struct DebugLogView: View {
    @Environment(\.openURL) private var openURL
    @State private var entries: [WakeLog.Entry] = WakeLog.recentEntries()
    @State private var showMail = false
    @AppStorage(AppSettingsKey.debugSetCharts) private var setChartsEnabled = false
    @AppStorage(AppSettingsKey.debugSetFlags) private var setFlagsEnabled = false
    @AppStorage(AppSettingsKey.debugParkNoCableGeoFilter) private var noCableGeoFilterEnabled = false

    var body: some View {
        List {
            Section {
                Toggle("Set charts", isOn: $setChartsEnabled)
                    .tint(Color.rpplAccent)
            } footer: {
                Text("Speed, altitude and g-force charts under each set in the logbook.")
            }

            Section {
                Toggle("Set flags", isOn: $setFlagsEnabled)
                    .tint(Color.rpplAccent)
            } footer: {
                Text("Show and edit set flags in the logbook. Saved flags are kept when this is off.")
            }

            Section {
                Toggle("No cable geo filter", isOn: $noCableGeoFilterEnabled)
                    .tint(Color.rpplAccent)
            } footer: {
                Text("Adds a filter to the Parks list and map for parks without cable coordinates.")
            }

            Section {
                Button {
                    ParkShare.shareAll(ParkStore.shared.entries)
                } label: {
                    Label("Share all park info", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("One multi-document YAML file with every park as the app uses it, including edited and custom parks.")
            }

            Section {
                NavigationLink {
                    ParkWaterTemperatureDebugView()
                } label: {
                    Label("Debug water temperature", systemImage: "ladybug")
                }
            }

            Section {
                ForEach(DeepLinkCatalog.entries, id: \.url) { entry in
                    deepLinkRow(entry)
                }
            } header: {
                Text(verbatim: "Deep links")
            } footer: {
                Text(verbatim: "Tap to open, hold to copy. Links with <…> need a real id first.")
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

    private func deepLinkRow(_ entry: DeepLinkCatalog.Entry) -> some View {
        Button {
            if let url = URL(string: entry.url), !entry.url.contains("<") { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.url).font(.footnote.monospaced())
                Text(verbatim: entry.summary).font(.caption).foregroundStyle(Color.rpplMuted)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.url
            } label: {
                Label { Text(verbatim: "Copy") } icon: { Image(systemName: "doc.on.doc") }
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
