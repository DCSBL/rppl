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

    private var years: [Int] {
        Set(sessions.map { Calendar.current.component(.year, from: $0.manifest.startedAt) }).sorted(by: >)
    }

    private var visitedCount: Int {
        ParkStats.visitedParkCount(
            sessions: sessions.map { ($0.manifest.startedAt, $0.manifest.parkId) },
            year: year
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
            header
            switch scope {
            case .you: you
            case .all: all
            }
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
        InfoTile("Parks visited") {
            MetricValue(String(visitedCount), size: .large)
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
