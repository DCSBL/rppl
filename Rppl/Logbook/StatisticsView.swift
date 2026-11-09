import SwiftUI
import RpplCore

/// The Statistics tab: the season totals and the per-session charts (distance and duration, laps,
/// calories, water and air). The catalog is the Logbook's; this view only reads it.
struct StatisticsView: View {
    let catalog: SessionCatalog

    @Environment(\.showAppSettings) private var showAppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var windowWidth: CGFloat = 0

    private var layout: WindowLayout {
        WindowLayout.resolve(width: Double(windowWidth), textSize: dynamicTypeSize.windowTextSize)
    }

    var body: some View {
        NavigationStack {
            // A List, like the Logbook, so both tabs get the same margins next to the Duo bars.
            List {
                // One row, so everything exists at once (a List builds rows lazily, offscreen ones included).
                VStack(spacing: RpplDesign.tileSpacing) {
                    SeasonTotalsCard(season: catalog.season, isLoading: catalog.isLoading)
                    if catalog.season.showsCharts {
                        SeasonCharts(season: catalog.season)
                    } else if !catalog.isLoading {
                        ContentUnavailableView {
                            Label("Not enough sessions yet", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text("Charts appear once you have a few sessions in your logbook.")
                        }
                        .foregroundStyle(Color.rpplMuted)
                        .accessibilityIdentifier("statistics-empty")
                    }
                }
                .readableWidth()
                .listRowInsets(LogbookLayout.rowInsets(top: 4, bottom: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, layout == .twoPane ? LogbookLayout.wideInset : LogbookLayout.horizontalInset, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .background(RpplBackdrop())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: showAppSettings)
                }
            }
            .tint(Color.rpplAccent)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
    }
}

#Preview {
    StatisticsView(catalog: SessionCatalog())
}
