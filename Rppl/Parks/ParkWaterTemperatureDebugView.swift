import RpplCore
import SwiftUI

/// Debug-tools-only screen for the water-temperature feature: every park's configured source and
/// cache/backoff state, plus a manual "Fetch now" that bypasses the setting toggle, cache and
/// backoff — so a developer can tell "the fetch itself is broken" apart from "the setting is off"
/// or "still inside the 4h cache window".
struct ParkWaterTemperatureDebugView: View {
    @State private var provider = ParkWaterTemperatureProvider.shared
    @State private var store = ParkStore.shared
    @State private var statuses: [String: ParkWaterTemperatureDebugStatus] = [:]
    @State private var refreshingParkIDs: Set<String> = []

    private var parks: [Park] {
        store.entries.map(\.park).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(parks) { park in
                    parkRow(park)
                }
            } footer: {
                Text("\"Fetch now\" always hits the network, even with the setting off or a value already cached.")
            }
        }
        .navigationTitle("Water Temperature Debug")
        .task { refreshSnapshots() }
        .refreshable { refreshSnapshots() }
    }

    private func refreshSnapshots() {
        if store.entries.isEmpty { store.reload() }
        for park in parks {
            statuses[park.id] = provider.debugSnapshot(for: park)
        }
    }

    @ViewBuilder
    private func parkRow(_ park: Park) -> some View {
        let status = statuses[park.id]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(park.name)
                        .font(.body.weight(.semibold))
                    if let source = park.waterTemperature {
                        Text("\(source.provider) · \(source.stationId)")
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    } else {
                        Text("No source configured")
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Task { await refresh(park) }
                } label: {
                    if refreshingParkIDs.contains(park.id) {
                        ProgressView()
                    } else {
                        Text("Fetch now")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(refreshingParkIDs.contains(park.id) || park.waterTemperature == nil)
            }
            if let reading = status?.reading {
                Text("\(TemperatureFormat.celsius(reading.celsius)) · \(reading.stationName), \(reading.providerName)")
                    .font(.caption)
                    .foregroundStyle(Color.rpplText)
            }
            if let status {
                Text(status.statusText)
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
            }
        }
        .padding(.vertical, 2)
    }

    private func refresh(_ park: Park) async {
        refreshingParkIDs.insert(park.id)
        statuses[park.id] = await provider.debugRefresh(for: park)
        refreshingParkIDs.remove(park.id)
    }
}

#Preview {
    NavigationStack {
        ParkWaterTemperatureDebugView()
    }
}
