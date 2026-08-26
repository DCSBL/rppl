import SwiftUI
import RpplCore

/// Multi-select picker for iCloud Drive session packages not yet on this phone.
struct ICloudSessionImportView: View {
    let summaries: [RemoteSessionSummary]
    var onImport: (Set<String>) -> Void
    var onCancel: () -> Void

    @State private var selected: Set<String> = []

    private var allSelected: Bool {
        !summaries.isEmpty && selected.count == summaries.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if summaries.isEmpty {
                    ContentUnavailableView {
                        Label("No sessions to import", systemImage: "icloud")
                    } description: {
                        Text("Every park day in iCloud Drive is already in this iPhone logbook.")
                    }
                    .foregroundStyle(Color.rpplText)
                } else {
                    List {
                        Section {
                            Button {
                                if allSelected {
                                    selected.removeAll()
                                } else {
                                    selected = Set(summaries.map(\.sessionId))
                                }
                            } label: {
                                Text(allSelected ? "Deselect All" : "Select All")
                                    .font(.body.weight(.semibold))
                            }
                            .tint(Color.rpplAccent)
                        }

                        Section {
                            ForEach(summaries) { summary in
                                Button {
                                    toggle(summary.sessionId)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(
                                            systemName: selected.contains(summary.sessionId)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .foregroundStyle(
                                            selected.contains(summary.sessionId)
                                                ? Color.rpplAccent
                                                : Color.rpplMuted
                                        )
                                        .font(.title3)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(summary.cityName ?? "-")
                                                .font(.headline)
                                                .foregroundStyle(Color.rpplText)
                                            Text(dateLine(summary))
                                                .font(.subheadline)
                                                .foregroundStyle(Color.rpplMuted)
                                            Text(statsLine(summary))
                                                .font(.caption)
                                                .foregroundStyle(Color.rpplMuted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text(
                                "These park days are in your iCloud Drive. Choose which to add to this iPhone logbook."
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.rpplBackground)
            .navigationTitle("Import from iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(summaries.isEmpty ? "Done" : "Not Now") { onCancel() }
                }
                if !summaries.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            onImport(selected)
                        }
                        .disabled(selected.isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
            .tint(Color.rpplAccent)
            .onAppear {
                selected = Set(summaries.map(\.sessionId))
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func dateLine(_ summary: RemoteSessionSummary) -> String {
        if summary.startedAt == Date.distantPast {
            return String(localized: "Date unknown")
        }
        return summary.startedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func statsLine(_ summary: RemoteSessionSummary) -> String {
        let rides = LogbookFormatting.rideCount(summary.rideCount)
        let duration = LogbookFormatting.duration(summary.totalDuration)
        return "\(rides) · \(duration)"
    }
}
