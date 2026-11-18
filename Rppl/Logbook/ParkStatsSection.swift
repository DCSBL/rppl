import RpplCore
import SwiftUI

/// The Parks section of the Statistics tab: what the rider did (You) or what the app knows (All).
/// The catalog totals are computed by `ParkStore`; this view only reads them.
struct ParkStatsSection: View {
    let sessions: [SessionEntry]

    private enum Scope: Hashable {
        case you, all
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var store = ParkStore.shared
    @State private var scope = Scope.you
    /// nil = all time.
    @State private var year: Int?
    @State private var rides: [Ride] = []
    @State private var showRidden = false

    /// A session with the cables it rode, matched against the park data as it is now.
    private struct Ride: Sendable {
        var date: Date
        var parkId: String
        var cableIndices: Set<Int>
    }

    /// Changes when sessions or park data change, so a park traced later is matched again.
    private struct RideKey: Equatable {
        var sessions: Int
        var parks: Int
        var stats: ParkStats
    }

    private var years: [Int] {
        Set(sessions.map { Calendar.current.component(.year, from: $0.manifest.startedAt) }).sorted(by: >)
    }

    private var visitedCount: Int {
        ParkStats.visitedParkCount(
            sessions: sessions.map { ($0.manifest.startedAt, $0.manifest.parkId) },
            year: year
        )
    }

    private var riddenCables: RiddenCables {
        RiddenCables(
            rides: rides.map { ($0.date, $0.parkId, $0.cableIndices) },
            parks: store.entries.map(\.park),
            year: year
        )
    }

    nonisolated private static func rides(sessions: [SessionEntry], parks: [Park]) -> [Ride] {
        let catalog = Dictionary(parks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return sessions.compactMap { entry in
            guard let parkId = entry.manifest.parkId, let cables = catalog[parkId]?.cables else { return nil }
            let indices = CableMatcher.riddenCableIndices(
                manual: entry.manifest.manual, tracks: entry.ridingTracks, cables: cables
            )
            return indices.isEmpty ? nil : Ride(date: entry.manifest.startedAt, parkId: parkId, cableIndices: indices)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
            header
            switch scope {
            case .you: you
            case .all: all
            }
        }
        .task(id: RideKey(sessions: sessions.count, parks: store.entries.count, stats: store.stats)) {
            let input = sessions
            let parks = store.entries.map(\.park)
            rides = await Task.detached(priority: .utility) { Self.rides(sessions: input, parks: parks) }.value
        }
        .navigationDestination(isPresented: $showRidden) {
            RiddenCablesView(ridden: riddenCables, parks: store.entries.map(\.park))
        }
    }

    private var header: some View {
        AdaptiveStack(rowAlignment: .center, spacing: 8) {
            Text("Parks")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(RpplDesign.headerColor)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if scope == .you, !years.isEmpty {
                yearMenu
            }
            Picker("Parks", selection: $scope) {
                Text("You").tag(Scope.you)
                Text("All").tag(Scope.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }

    private var yearMenu: some View {
        Menu {
            Picker("Year", selection: $year) {
                Text("All time").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
        } label: {
            Text(year.map { String($0) } ?? String(localized: "All time"))
                .font(.subheadline)
        }
    }

    private var you: some View {
        let ridden = riddenCables
        return VStack(spacing: RpplDesign.tileSpacing) {
            InfoTileGrid {
                InfoTile("Parks visited") {
                    MetricValue(String(visitedCount), size: .large)
                }
                InfoTile("Cables ridden") {
                    MetricValue(String(ridden.count), size: .large)
                }
            }
            if ridden.count > 0 {
                Button { showRidden = true } label: {
                    InfoTile("Cables ridden by type") {
                        AdaptiveStack(spacing: 12) {
                            typeCount(ridden.counterClockwise, label: "CCW", symbol: "arrow.counterclockwise")
                            typeCount(ridden.clockwise, label: "CW", symbol: "arrow.clockwise")
                            typeCount(ridden.twoPointZero, label: "2.0", symbol: "arrow.left.and.right")
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var all: some View {
        let stats = store.stats
        return VStack(spacing: RpplDesign.tileSpacing) {
            InfoTileGrid {
                InfoTile("Parks in Rppl") {
                    MetricValue(String(stats.parkCount), size: .large)
                }
                InfoTile("Cable recorded") {
                    MetricValue(DistanceFormat.kilometers(stats.totalLengthM, fixedFraction: 1), size: .large)
                }
            }
            InfoTile("Cables in Rppl") {
                AdaptiveStack(spacing: 12) {
                    typeCount(stats.counterClockwise, label: "CCW", symbol: "arrow.counterclockwise")
                    typeCount(stats.clockwise, label: "CW", symbol: "arrow.clockwise")
                    typeCount(stats.twoPointZero, label: "2.0", symbol: "arrow.left.and.right")
                }
                Text("All cables in the app, not just the ones you used.")
                    .font(.footnote)
                    .foregroundStyle(RpplDesign.secondaryText)
            }
        }
    }

    private func typeCount(_ count: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            MetricValue(String(count), size: .total)
            Label {
                Text(verbatim: label)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.subheadline)
            .foregroundStyle(RpplDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
