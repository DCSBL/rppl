import SwiftUI
import MapKit
import RpplCore

enum LogbookSessionDetailSource: Equatable {
    case store(sessionId: String)
    /// Bundled Share export — viewed in memory only; not written to the phone store.
    case bundledExample
}

struct LogbookSessionDetailView: View {
    let source: LogbookSessionDetailSource
    var store: SessionFileStore?

    private static let sessionMapPointBudget = 800
    private static let rideMapPointBudget = 200
    private static let exampleFileName = "FBDC7D8C-8FEA-47B6-911B-00E94A8A496C"

    @State private var manifest: SessionManifest?
    @State private var sessionStats: SessionStats?
    @State private var mapTracks: [[LocationSample]] = []
    @State private var allLocations: [LocationSample] = []
    @State private var mapFrame: MapTrackFrame?
    @State private var tracksLoading = false
    @State private var cityName: String?
    @State private var loadPhase: LoadPhase = .loading
    @State private var loadTask: Task<Void, Never>?
    @State private var tracksTask: Task<Void, Never>?
    @State private var errorText: String?
    @State private var showExportError = false
    @State private var exportErrorText: String?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var showExportExplainer = false
    @AppStorage(AppSettingsKey.didUnderstandExport) private var didUnderstandExport = false

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed
    }

    init(sessionId: String, store: SessionFileStore) {
        self.source = .store(sessionId: sessionId)
        self.store = store
    }

    init(source: LogbookSessionDetailSource) {
        self.source = source
        self.store = nil
    }

    private var allowsExport: Bool {
        if case .store = source { return true }
        return false
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
        .onDisappear {
            cancelLoad()
            cancelExport()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if allowsExport {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else if isExporting {
                        ProgressView()
                    } else if loadPhase == .ready {
                        Button("Export") {
                            requestExport()
                        }
                    }
                }
            }
        }
        .alert(
            "Export Session?",
            isPresented: $showExportExplainer
        ) {
            Button("Understood") {
                didUnderstandExport = true
                startExport()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Exports the full session file: raw sensor data, nothing filtered or anonymized.")
        }
        .alert(
            "Could Not Export",
            isPresented: $showExportError,
            presenting: exportErrorText
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var navigationTitle: String {
        if case .bundledExample = source {
            return ActivityCodes.localizedTitle(for: manifest?.activityCode ?? "Example session")
        }
        guard let manifest else { return String(localized: "Session") }
        return LogbookFormatting.sessionDate(manifest.startedAt)
    }

    private var displayedMaxSpeedKmh: Double? {
        guard let stats = sessionStats else { return nil }
        return stats.maxSpeedKmh
            ?? SessionLocationHelpers.peakSpeedKmh(rides: stats.rides, locations: allLocations)
    }

    @ViewBuilder
    private var sessionMap: some View {
        if mapTracks.isEmpty, mapFrame == nil {
            mapPlaceholder(
                tracksLoading
                    ? "Loading GPS…"
                    : (sessionStats?.rides.isEmpty == false ? "No ride GPS" : "No GPS track")
            )
        } else {
            SessionMapView(
                tracks: mapTracks,
                allowsInteraction: true,
                showsStyleToggle: true,
                preferredFrame: mapFrame
            )
                .frame(height: 300)
                .clipShape(.rect(cornerRadius: LogbookLayout.cardCornerRadius))
                .containerShape(.rect(cornerRadius: LogbookLayout.cardCornerRadius))
                .overlay(alignment: .center) {
                    if tracksLoading, mapTracks.isEmpty {
                        ProgressView()
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
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
                        Text(cityName ?? "-")
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
                        displayedMaxSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                        label: "Max speed"
                    )
                    statTile(
                        stats.averageSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                        label: "Avg speed"
                    )
                    statTile("\(stats.rideCount)", label: "Rides")
                    statTile("\(stats.totalLapCount)", label: "Laps")
                    statTile(
                        "\(Int((stats.ridingInactiveRatio * 100).rounded()))% · "
                            + LogbookFormatting.duration(stats.ridingDuration),
                        label: "Riding"
                    )
                    statTile(
                        LogbookFormatting.duration(stats.inactiveDuration),
                        label: "Inactive"
                    )
                    if stats.waterTemperatureAvailable {
                        statTile(
                            stats.averageWaterTemperatureCelsius.map(LogbookFormatting.waterTemperature)
                                ?? TemperatureFormat.placeholder,
                            label: "Water temperature"
                        )
                    }
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
            .foregroundStyle(Color.rpplText)
            .logbookCardChrome()
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
        .logbookNestedBackground(Color.rpplFill)
    }

    private func mapPlaceholder(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.rpplMuted)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color.rpplFill, in: .rect(cornerRadius: LogbookLayout.cardCornerRadius))
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
        tracksTask?.cancel()
        tracksTask = nil
    }

    private func loadSession() async {
        let source = source
        let store = store

        do {
            switch source {
            case .store(let sessionId):
                guard let store else {
                    throw SessionStoreError.ioFailure("Session store missing")
                }
                let summary = try await StoreIO.runOffMain {
                    try SessionLoader.loadSummary(store: store, sessionId: sessionId)
                }
                try Task.checkCancellation()
                manifest = summary.manifest
                sessionStats = summary.stats
                mapFrame = summary.mapFrame
                cityName = summary.cityName
                if cityName == nil {
                    let peek = try await StoreIO.runOffMain {
                        try store.peekLocationSamples(sessionId: sessionId)
                    }
                    cityName = await SessionCityResolver.shared.cityName(
                        sessionId: sessionId,
                        locations: peek
                    )
                    if let cityName {
                        try? await StoreIO.runOffMain {
                            try store.updateDerivedCityName(cityName, sessionId: sessionId)
                        }
                    }
                } else if let cityName {
                    SessionCityResolver.shared.remember(sessionId: sessionId, cityName: cityName)
                }
                loadPhase = .ready
                loadTask = nil
                tracksLoading = true
                tracksTask = Task(priority: .utility) {
                    await loadTracks(store: store, sessionId: sessionId, rides: summary.stats.rides)
                }

            case .bundledExample:
                let bundle = try await StoreIO.runOffMain {
                    try Self.loadBundledExample()
                }
                try Task.checkCancellation()
                applyFullBundle(bundle)
                loadPhase = .ready
                loadTask = nil
            }
        } catch is CancellationError {
            loadTask = nil
        } catch {
            errorText = error.localizedDescription
            loadPhase = .failed
            loadTask = nil
            WakeLog.error(.store, "LogbookSessionDetail load: \(error.localizedDescription)")
        }
    }

    private func loadTracks(
        store: SessionFileStore,
        sessionId: String,
        rides: [RideSegmentStats]
    ) async {
        do {
            let locations = try await StoreIO.runOffMain {
                try store.readLocationSamples(sessionId: sessionId)
            }
            try Task.checkCancellation()
            let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
            let rideTracks = RideLocationFilter.tracks(from: sortedLocations, rides: rides)
            let perTrackBudget = max(32, Self.sessionMapPointBudget / max(rideTracks.count, 1))
            let mapPoints = rideTracks.map {
                SessionLocationHelpers.downsample($0, maxCount: perTrackBudget)
            }
            allLocations = sortedLocations
            mapTracks = mapPoints
            tracksLoading = false
            tracksTask = nil
        } catch is CancellationError {
            tracksTask = nil
            tracksLoading = false
        } catch {
            tracksLoading = false
            tracksTask = nil
            WakeLog.error(.store, "LogbookSessionDetail tracks: \(error.localizedDescription)")
        }
    }

    private func applyFullBundle(_ bundle: SessionLoadBundle) {
        let sortedLocations = bundle.locations.sorted { $0.timestamp < $1.timestamp }
        let rideTracks = RideLocationFilter.tracks(from: sortedLocations, rides: bundle.stats.rides)
        let perTrackBudget = max(32, Self.sessionMapPointBudget / max(rideTracks.count, 1))
        let mapPoints = rideTracks.map {
            SessionLocationHelpers.downsample($0, maxCount: perTrackBudget)
        }
        manifest = bundle.manifest
        sessionStats = bundle.stats
        allLocations = sortedLocations
        mapTracks = mapPoints
        mapFrame = bundle.mapFrame
        cityName = bundle.cityName
    }

    private static func loadBundledExample() throws -> SessionLoadBundle {
        guard let url = Bundle.main.url(
            forResource: exampleFileName,
            withExtension: "json",
            subdirectory: "Exports"
        ) ?? Bundle.main.url(forResource: exampleFileName, withExtension: "json") else {
            throw SessionStoreError.ioFailure("Bundled example session missing")
        }
        WakeLog.debug(.ui, "example session load (ephemeral, timeline → now)")
        return try SessionLoader.loadExample(packageURL: url, now: Date())
    }

    private func requestExport() {
        guard allowsExport, exportTask == nil, !isExporting, loadPhase == .ready else { return }
        if didUnderstandExport {
            startExport()
        } else {
            showExportExplainer = true
        }
    }

    private func startExport() {
        guard allowsExport, exportTask == nil, !isExporting, loadPhase == .ready else { return }
        showExportError = false
        exportErrorText = nil
        isExporting = true
        exportTask = Task(priority: .utility) {
            await prepareExport()
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
    }

    private func prepareExport() async {
        guard case .store(let sessionId) = source, let store else {
            presentExportFailure(
                String(localized: "Session store missing. Try again from the logbook.")
            )
            return
        }
        WakeLog.debug(.ui, "export session \(sessionId.prefix(8))…")
        let resolvedCity = cityName

        do {
            let url = try await StoreIO.runOffMain {
                let package = try store.buildTransferPackage(sessionId: sessionId)
                try Task.checkCancellation()
                let fileName = SessionShareExport.fileName(
                    startedAt: package.manifest.startedAt,
                    locationName: package.derived?.cityName ?? resolvedCity
                )
                let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try SessionShareExport.encode(package).write(to: exportURL, options: [.atomic])
                return exportURL
            }
            try Task.checkCancellation()
            exportURL = url
            finishExportTask()
            WakeLog.debug(.ui, "export OK \(sessionId.prefix(8))… \(url.lastPathComponent)")
        } catch is CancellationError {
            finishExportTask()
        } catch {
            presentExportFailure(Self.userFacingMessage(for: error))
            WakeLog.error(.store, "export: \(error.localizedDescription)")
        }
    }

    private func finishExportTask() {
        isExporting = false
        exportTask = nil
    }

    private func presentExportFailure(_ message: String) {
        finishExportTask()
        exportErrorText = message
        // Present after toolbar ProgressView → Export swap so SwiftUI does not drop the alert.
        Task { @MainActor in
            showExportError = true
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return String(localized: "Something went wrong while preparing the export.")
        }
        return description
    }
}

private struct RideDetailCard: View {
    let ride: RideSegmentStats
    let locations: [LocationSample]

    private var maxSpeedKmh: Double? {
        SessionLocationHelpers.peakSpeedKmh(for: ride, locations: locations)
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
                    .logbookNestedClip()
            } else {
                Text("No GPS track for this ride")
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .logbookNestedBackground(Color.rpplFill)
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
                    maxSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                    label: "Max speed"
                )
                rideStatTile(
                    averageSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                    label: "Avg speed"
                )
            }

            Text(
                LogbookFormatting.sessionTimeRange(start: ride.startedAt, end: ride.endedAt)
            )
            .font(.caption)
            .foregroundStyle(Color.rpplMuted)
        }
        .logbookCardChrome()
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
        .logbookNestedBackground(Color.rpplFill)
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
