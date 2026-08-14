import SwiftUI
import RpplCore

struct LogbookView: View {
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var catalog = SessionCatalog()

    private var seasonYear: Int { LogbookFormatting.seasonYear() }
    private var season: SeasonSummary { catalog.seasonSummary(year: seasonYear) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    seasonCard
                    sessionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                catalog.reload(store: connectivity.store)
            }
            .onChange(of: connectivity.sessionsRevision) { _, _ in
                catalog.reload(store: connectivity.store)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Logbook")
                .font(.largeTitle.bold())
            Text("Cable park sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var seasonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("THIS SEASON", systemImage: "water.waves")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .labelStyle(.titleAndIcon)

            HStack(spacing: 0) {
                seasonMetric(
                    value: catalog.isLoading ? "—" : "\(season.sessionCount)",
                    label: "Sessions"
                )
                seasonDivider
                seasonMetric(
                    value: catalog.isLoading ? "—" : LogbookFormatting.distanceKilometers(season.totalDistanceMeters),
                    label: "Distance"
                )
                seasonDivider
                seasonMetric(
                    value: catalog.isLoading || season.topSpeedKmh <= 0
                        ? "—"
                        : LogbookFormatting.speedKilometersPerHour(season.topSpeedKmh),
                    label: "Top Speed"
                )
            }

            Divider()

            HStack {
                Text(catalog.isLoading ? "— total runs" : "\(season.totalRuns) total runs")
                Spacer()
                Text("Cable park · \(seasonYear)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var seasonDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 44)
    }

    private func seasonMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sessions")
                    .font(.title3.bold())
                Spacer()
                Text(catalog.isLoading ? "…" : "\(catalog.entries.count) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if catalog.isLoading && catalog.entries.isEmpty {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if catalog.entries.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "water.waves",
                    description: Text("Record on Apple Watch, then bring your iPhone nearby.")
                )
                .frame(minHeight: 160)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(catalog.entries) { entry in
                        SessionCard(entry: entry)
                    }
                }
            }
        }
    }
}

private struct SessionCard: View {
    let entry: SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.wakeboarding")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wakeboarding")
                        .font(.headline)
                }

                Spacer(minLength: 0)

                Text(LogbookFormatting.sessionDate(entry.manifest.startedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                statLabel("clock", value: durationText)
                statLabel("water.waves", value: distanceText)
                statLabel("mappin.and.ellipse", value: "Cable park")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var durationText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.duration(stats.totalDuration)
    }

    private var distanceText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.distanceKilometers(stats.totalDistanceMeters)
    }

    private func statLabel(_ symbol: String, value: String) -> some View {
        Label(value, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

#Preview {
    LogbookView()
}
