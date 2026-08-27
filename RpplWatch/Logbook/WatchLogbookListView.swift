import SwiftUI
import RpplCore

enum WatchLogbookFormatting {
    static func sessionDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func sessionTimeRange(start: Date, end: Date?) -> String {
        let startText = start.formatted(.dateTime.hour().minute())
        guard let end else { return startText }
        return "\(startText) – \(end.formatted(.dateTime.hour().minute()))"
    }
}

struct WatchLogbookListView: View {
    @State private var catalog = WatchSessionCatalog()
    @Bindable private var viewSync = WatchViewSyncService.shared
    @Bindable private var transfer = WatchTransferService.shared
    @State private var showExampleSession = false

    var body: some View {
        _ = viewSync.catalogRevision
        _ = transfer.syncStatusRevision
        return List {
            if catalog.isLoading, catalog.entries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading sessions…")
                    Spacer()
                }
            } else if catalog.entries.isEmpty {
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "book")
                } description: {
                    Text("Record a park day on Apple Watch. Or browse the example session.")
                } actions: {
                    Button("Show example session") {
                        showExampleSession = true
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.rpplIdleAccent)
                }
            } else {
                ForEach(catalog.entries) { entry in
                    NavigationLink {
                        WatchSessionDetailView(sessionId: entry.manifest.sessionId)
                    } label: {
                        WatchSessionRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Logbook")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showExampleSession) {
            WatchSessionDetailView(source: .bundledExample)
        }
        .onAppear {
            catalog.reload()
            viewSync.requestViewSyncIfReachable()
        }
        .onChange(of: viewSync.catalogRevision) { _, _ in
            catalog.reload()
        }
        .onChange(of: transfer.syncStatusRevision) { _, _ in
            catalog.reload()
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .preferredColorScheme(.dark)
    }
}

private struct WatchSessionRow: View {
    let entry: WatchSessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !entry.isSynced {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
                Text(WatchLogbookFormatting.sessionDate(entry.manifest.startedAt))
                    .font(.headline)
                    .foregroundStyle(Color.rpplIdlePrimary)
            }

            Text(WatchLogbookFormatting.sessionTimeRange(
                start: entry.manifest.startedAt,
                end: entry.manifest.endedAt ?? entry.stats.endedAt
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(SessionFormatters.elapsed(entry.stats.totalDuration))
                Text("·")
                Text(SessionFormatters.distance(entry.stats.totalDistanceMeters))
                Text("·")
                Text("\(entry.stats.rideCount) rides")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let cityName = entry.cityName, !cityName.isEmpty {
                Text(cityName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        WatchLogbookListView()
    }
}
