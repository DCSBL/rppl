import SwiftUI
import MapKit
import RpplCore

struct LogbookSessionDetailView: View {
    let sessionId: String
    let store: SessionFileStore

    private static let sessionMapPointBudget = 800
    private static let rideMapPointBudget = 200

    @State private var manifest: SessionManifest?
    @State private var sessionStats: SessionStats?
    @State private var mapTracks: [[LocationSample]] = []
    @State private var allLocations: [LocationSample] = []
    @State private var topSpeedKmh: Double?
    @State private var cityName: String?
    @State private var loadPhase: LoadPhase = .loading
    @State private var loadTask: Task<Void, Never>?
    @State private var errorText: String?

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch loadPhase {
                case .loading:
                    ProgressView("Loading session…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                case .failed:
                    ContentUnavailableView(
                        "Could not load session",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText ?? String(localized: "Try again later."))
                    )
                    .frame(minHeight: 240)
                case .ready:
                    sessionMap
                    sessionStatsCard
                    ridesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.rpplBackground)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.rpplAccent)
        .onAppear { startLoadIfNeeded() }
        .onDisappear { cancelLoad() }
    }

    private var navigationTitle: String {
        guard let manifest else { return String(localized: "Session") }
        return LogbookFormatting.sessionDate(manifest.startedAt)
    }

    @ViewBuilder
    private var sessionMap: some View {
        if mapTracks.isEmpty {
            mapPlaceholder(sessionStats?.rides.isEmpty == false ? "No ride GPS" : "No GPS track")
        } else {
            SessionMapView(tracks: mapTracks, allowsInteraction: true)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var sessionStatsCard: some View {
        if let stats = sessionStats {
            VStack(alignment: .leading, spacing: 16) {
                Text("Session")
                    .font(.headline)
                    .foregroundStyle(Color.rpplText)

                if let manifest {
                    LabeledContent("Time") {
                        Text(
                            LogbookFormatting.sessionTimeRange(
                                start: manifest.startedAt,
                                end: manifest.endedAt ?? stats.endedAt
                            )
                        )
                        .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Location") {
                        Text(cityName ?? "—")
                    }
                }

                statsGrid {
                    statTile(
                        LogbookFormatting.duration(stats.totalDuration),
                        label: "Duration"
                    )
                    statTile(
                        LogbookFormatting.distanceKilometers(stats.totalDistanceMeters),
                        label: "Distance"
                    )
                    statTile(
                        topSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "—",
                        label: "Top speed"
                    )
                    statTile("\(stats.rideCount)", label: "Rides")
                    statTile("\(stats.totalLapCount)", label: "Laps")
                    statTile(
                        "\(Int((stats.ridingPausedRatio * 100).rounded()))% · "
                            + LogbookFormatting.duration(stats.ridingDuration),
                        label: "Riding"
                    )
                    statTile(
                        LogbookFormatting.duration(stats.pausedDuration),
                        label: "Paused"
                    )
                    if let calories = stats.activeEnergyKilocalories {
                        statTile(
                            LogbookFormatting.kilocalories(calories),
                            label: "Active calories"
                        )
                    }
                    if let total = stats.totalEnergyKilocalories {
                        statTile(
                            LogbookFormatting.kilocalories(total),
                            label: "Total calories"
                        )
                    }
                }
            }
            .padding(16)
            .foregroundStyle(Color.rpplText)
            .background(Color.rpplCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var ridesSection: some View {
        if let stats = sessionStats {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rides")
                    .font(.title3.bold())
                    .foregroundStyle(Color.rpplText)

                if stats.rides.isEmpty {
                    Text("No rides detected.")
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                } else {
                    ForEach(stats.rides) { ride in
                        RideDetailCard(
                            ride: ride,
                            locations: SessionLocationHelpers.downsample(
                                SessionLocationHelpers.locations(for: ride, in: allLocations),
                                maxCount: Self.rideMapPointBudget
                            )
                        )
                    }
                }
            }
        }
    }

    private func statsGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            content()
        }
    }

    private func statTile(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.rpplFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func mapPlaceholder(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.rpplMuted)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color.rpplFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func startLoadIfNeeded() {
        guard loadTask == nil, loadPhase != .ready else { return }
        loadPhase = .loading
        loadTask = Task(priority: .userInitiated) {
            await loadSession()
        }
    }

    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func loadSession() async {
        let store = store
        let sessionId = sessionId

        do {
            let loadedManifest = try await runStoreIO {
                try store.readManifest(sessionId: sessionId)
            }
            try Task.checkCancellation()

            let detections = try await runStoreIO {
                try store.readDetections(sessionId: sessionId)
            }
            try Task.checkCancellation()

            let locations = try await runStoreIO {
                try store.readLocationSamples(sessionId: sessionId)
            }
            try Task.checkCancellation()

            let health = try await runStoreIO {
                try store.readHealthSamples(sessionId: sessionId)
            }
            try Task.checkCancellation()

            let stats = SessionStatsBuilder.build(
                manifest: loadedManifest,
                detections: detections,
                locations: locations,
                health: health
            )
            let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
            let rideTracks = RideLocationFilter.tracks(from: sortedLocations, rides: stats.rides)
            let perTrackBudget = max(32, Self.sessionMapPointBudget / max(rideTracks.count, 1))
            let mapPoints = rideTracks.map {
                SessionLocationHelpers.downsample($0, maxCount: perTrackBudget)
            }

            manifest = loadedManifest
            sessionStats = stats
            allLocations = sortedLocations
            mapTracks = mapPoints
            topSpeedKmh = stats.topSpeedKmh
                ?? SessionLocationHelpers.sustainedSpeedKmh(
                    rides: stats.rides,
                    locations: sortedLocations
                )
            cityName = await SessionCityResolver.shared.cityName(
                sessionId: sessionId,
                locations: sortedLocations
            )
            loadPhase = .ready
            loadTask = nil
        } catch is CancellationError {
            loadTask = nil
        } catch {
            errorText = error.localizedDescription
            loadPhase = .failed
            loadTask = nil
            WakeLog.error(.store, "LogbookSessionDetail load: \(error.localizedDescription)")
        }
    }

    private func runStoreIO<T: Sendable>(
        _ work: @Sendable @escaping () throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try work()
            }
            guard let value = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return value
        }
    }
}

private struct RideDetailCard: View {
    let ride: RideSegmentStats
    let locations: [LocationSample]

    private var topSpeedKmh: Double? {
        ride.sustainedSpeedKmh ?? SessionLocationHelpers.sustainedSpeedKmh(from: locations)
    }

    private var averageSpeedKmh: Double? {
        SessionLocationHelpers.averageSpeedKmh(for: ride)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                (
                    Text("Ride \(ride.index)")
                        .foregroundStyle(Color.rpplText)
                    + (ride.highlights.isEmpty
                        ? Text("")
                        : Text(" - \(LogbookFormatting.joinedRideHighlights(ride.highlights))")
                            .foregroundStyle(Color.rpplMuted))
                )
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            }

            if locations.count >= 2 {
                SessionMapView(locations: locations)
                    .frame(height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("No GPS track for this ride")
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.rpplFill, in: RoundedRectangle(cornerRadius: 12))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 8
            ) {
                rideStatTile(
                    LogbookFormatting.duration(ride.duration),
                    label: "Duration"
                )
                rideStatTile(
                    LogbookFormatting.distanceKilometers(ride.distanceMeters),
                    label: "Distance"
                )
                rideStatTile("\(ride.lapCount)", label: "Laps")
                rideStatTile(
                    topSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "—",
                    label: "Top speed"
                )
                rideStatTile(
                    averageSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "—",
                    label: "Avg speed"
                )
            }

            Text(
                LogbookFormatting.sessionTimeRange(start: ride.startedAt, end: ride.endedAt)
            )
            .font(.caption)
            .foregroundStyle(Color.rpplMuted)
        }
        .padding(16)
        .background(Color.rpplCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rideStatTile(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.rpplFill, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NavigationStack {
        LogbookSessionDetailView(
            sessionId: "preview",
            store: SessionFileStore(rootURL: FileManager.default.temporaryDirectory)
        )
    }
}
