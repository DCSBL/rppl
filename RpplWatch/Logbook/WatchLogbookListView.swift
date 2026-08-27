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

    /// Locale date plus time span, e.g. `20-10-2026 · 14:14 – 15:15`.
    static func sessionDateTimeLine(start: Date, end: Date?) -> String {
        let dateText = start.formatted(.dateTime.day().month().year())
        return "\(dateText) · \(sessionTimeRange(start: start, end: end))"
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
                        WatchSessionDetailView(entry: entry)
                    } label: {
                        WatchSessionRow(entry: entry)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
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
        HStack(alignment: .top, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            if let mapSource = rowMapSource {
                SessionMapSnapshotView(
                    source: mapSource,
                    size: CGSize(width: 56, height: 56),
                    cornerRadius: 10,
                    showsPin: true
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var rowMapSource: SessionMapSnapshotSource? {
        guard WatchDisplayLayout.showsSessionOverviewStartMap else { return nil }
        if let mapFrame = entry.mapFrame {
            return .frame(mapFrame)
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        WatchLogbookListView()
    }
}
