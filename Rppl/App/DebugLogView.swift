import RpplCore
import SwiftUI

/// Debug-tools-only screen: the last warnings/failures logged via `WakeLog`, across every category
/// (sync, transfer, water, …), newest first. Cheap throwaway list — this exists so a developer can
/// see *why* something silently failed (e.g. a water-temperature fetch) without attaching Console.app.
struct DebugLogView: View {
    @State private var entries: [WakeLog.Entry] = WakeLog.recentEntries()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No warnings or failures logged yet.")
                    .foregroundStyle(Color.rpplMuted)
            } else {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
        .navigationTitle("Debug Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") {
                    WakeLog.clearHistory()
                    entries = []
                }
                .disabled(entries.isEmpty)
            }
        }
        .refreshable { entries = WakeLog.recentEntries() }
        .task { entries = WakeLog.recentEntries() }
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
