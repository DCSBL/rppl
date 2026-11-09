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
            ScrollView {
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
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .contentMargins(.horizontal, layout == .twoPane ? LogbookLayout.wideInset : LogbookLayout.horizontalInset, for: .scrollContent)
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
