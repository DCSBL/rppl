import SwiftUI
import Charts
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

    private static let setMapPointBudget = 200
    private static let exampleFileName = "FBDC7D8C-8FEA-47B6-911B-00E94A8A496C"

    @State private var manifest: SessionManifest?
    @State private var showsMissingCaloriesInfo = false
    @State private var sessionStats: SessionStats?
    @State private var setTracks: [SessionSetTrack] = []
    @State private var soloSetIndex: Int?
    @State private var sessionMapTrackData: SessionMapTrackData?
    @State private var allLocations: [LocationSample] = []
    @State private var mapFrame: MapTrackFrame?
    @State private var parks: [Park] = []
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
                    parkLink
                    sessionStatsCard
                    setsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(RpplBackdrop())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.rpplAccent)
        .onAppear { startLoadIfNeeded() }
        .task { parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot) }
        .onDisappear {
            cancelLoad()
            cancelExport()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if allowsExport, loadPhase == .ready {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button {
                            requestExport()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Export"))
                    }
                }
            }
        }
        .alert(
            "Export session?",
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
            "Could not export",
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
            ?? SessionLocationHelpers.peakSpeedKmh(sets: stats.sets, locations: allLocations)
    }

    @ViewBuilder
    private var sessionMap: some View {
        if sessionMapTrackData == nil, mapFrame == nil {
            mapPlaceholder(
                tracksLoading
                    ? "Loading GPS…"
                    : (sessionStats?.sets.isEmpty == false ? "No set GPS" : "No GPS track")
            )
        } else if let sessionMapTrackData {
            ZStack(alignment: .topLeading) {
                SessionMapView(
                    sessionMapData: sessionMapTrackData,
                    rendering: sessionRendering,
                    allowsInteraction: false,
                    preferredFrame: mapFrame,
                    cableOverlays: cableOverlays
                )
                .allowsHitTesting(false)

                NavigationLink {
                    SessionMapFullscreenView(
                        sessionMapData: sessionMapTrackData,
                        rendering: sessionRendering,
                        title: navigationTitle,
                        preferredFrame: mapFrame,
                        cableOverlays: cableOverlays
                    )
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                SessionMapControlCluster(
                    showsStyleToggle: true,
                    layout: .embedded
                )
                .padding(10)

                setSelectionMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: LogbookLayout.cardCornerRadius))
            .containerShape(.rect(cornerRadius: LogbookLayout.cardCornerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(String(localized: "Session map"))
            .accessibilityHint(String(localized: "Shows full-screen map"))
            .overlay(alignment: .center) {
                if tracksLoading, !sessionMapTrackData.hasRenderableTrack {
                    ProgressView()
                        .padding(12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        } else {
            mapPlaceholder("No GPS track")
        }
    }

    /// Manual park pick: stored as `manual`, so auto-matching never overrides it.
    private var parkSelection: Binding<String?> {
        Binding(
            get: { manifest?.parkId },
            set: { newId in
                guard let store, let sessionId = manifest?.sessionId else { return }
                let park = parks.first { $0.id == newId }
                Task {
                    try? await StoreIO.runOffMain {
                        try store.setManualPark(park, sessionId: sessionId)
                    }
                    manifest = try? store.readManifest(sessionId: sessionId)
                    cityName = park?.name
                    PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
                    if park == nil {
                        let peek = try? store.peekLocationSamples(sessionId: sessionId)
                        cityName = await SessionCityResolver.shared.cityName(
                            sessionId: sessionId,
                            locations: peek ?? []
                        )
                        if let cityName {
                            try? store.updateDerivedCityName(cityName, sessionId: sessionId)
                        }
                    }
                }
            }
        )
    }

    /// Park this session's track sits in, matched on the derived map frame center.
    private var matchedPark: Park? {
        if let parkId = manifest?.parkId { return parks.first { $0.id == parkId } }
        if manifest?.parkIdSource == SessionParkSource.manual { return nil }
        guard let mapFrame else { return nil }
        let center = ParkCoordinate(lat: mapFrame.centerLatitude, lon: mapFrame.centerLongitude)
        return ParkListing.nearest(to: center, in: parks)
    }

    private var cableOverlays: [[CLLocationCoordinate2D]] {
        (matchedPark?.cables ?? []).compactMap { cable in
            var coordinates = (cable.points ?? []).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            guard coordinates.count >= 2 else { return nil }
            if cable.direction?.isLoop == true, let first = coordinates.first { coordinates.append(first) }
            return coordinates
        }
    }

    @ViewBuilder
    private var parkLink: some View {
        if let park = matchedPark {
            NavigationLink {
                ParkDetailContainer(park: park)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: MetricKind.park.systemImage)
                        .foregroundStyle(MetricKind.park.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(park.name)
                            .font(.headline)
                            .foregroundStyle(Color.rpplText)
                        Text("View park")
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.rpplMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rpplTileChrome()
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionRendering: SessionMapRendering {
        SessionMapRendering(setTracks: setTracks, soloSetIndex: soloSetIndex)
    }

    /// Native menu over the map: the session's own sets are the only options.
    @ViewBuilder
    private var setSelectionMenu: some View {
        if setTracks.count > 1 {
            Menu {
                Picker("Set", selection: $soloSetIndex) {
                    Text("All sets").tag(Int?.none)
                    ForEach(setTracks, id: \.setIndex) { track in
                        Text("Set \(track.setNumber)").tag(Int?.some(track.setIndex))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedSetTitle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rpplText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Set")
        }
    }

    private var selectedSetTitle: String {
        guard let index = soloSetIndex,
              let track = setTracks.first(where: { $0.setIndex == index })
        else {
            return String(localized: "All sets")
        }
        return String(localized: "Set \(track.setNumber)")
    }

    @ViewBuilder
    private var sessionStatsCard: some View {
        if let stats = sessionStats {
            VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
                if let manifest {
                    sessionInfoTile(manifest: manifest, stats: stats)
                    setsTile(stats, start: manifest.startedAt, end: manifest.endedAt ?? stats.endedAt)
                }

                InfoTileGrid {
                    speedTile(stats)
                    ridingTile(stats)
                    distanceTile(stats)
                    if stats.waterTemperatureAvailable {
                        InfoTile("Water temperature", metric: .water) {
                            MetricValue(
                                stats.averageWaterTemperatureCelsius.map(LogbookFormatting.waterTemperature)
                                    ?? TemperatureFormat.placeholder
                            )
                        }
                    }
                    if let weather = manifest?.weather {
                        InfoTile("Air temperature", metric: .air) {
                            MetricValue(LogbookFormatting.airTemperature(weather.temperatureCelsius))
                            StatChip(
                                metric: .humidity,
                                value: LogbookFormatting.humidityPercent(weather.humidityPercent),
                                caption: "Humidity"
                            )
                        }
                    }
                    energyTile(stats)
                }
            }
        }
    }

    private func sessionInfoTile(manifest: SessionManifest, stats: SessionStats) -> some View {
        InfoTile("Session", metric: .duration) {
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
                Menu {
                    Picker("Park", selection: parkSelection) {
                        Text("No park").tag(String?.none)
                        ForEach(parks) { park in
                            Text(park.name).tag(String?.some(park.id))
                        }
                    }
                } label: {
                    Text(cityName ?? "-")
                }
            }
        }
        .foregroundStyle(Color.rpplText)
    }

    private func speedTile(_ stats: SessionStats) -> some View {
        InfoTile("Max speed", metric: .speed) {
            MetricValue(displayedMaxSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-")
            if let max = displayedMaxSpeedKmh, let average = stats.averageSpeedKmh, max > 0 {
                Gauge(value: MetricDisplay.fraction(average, of: max)) {
                    Text("Avg speed")
                }
                .gaugeStyle(.rpplBar(tint: MetricKind.speed.tint))
                .accessibilityHidden(true)
            }
            StatChip(
                metric: .speed,
                value: stats.averageSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                caption: "Avg speed"
            )
        }
    }

    private func ridingTile(_ stats: SessionStats) -> some View {
        InfoTile("Riding", metric: .riding) {
            Gauge(value: MetricDisplay.fraction(stats.ridingInactiveRatio, of: 1)) {
                Text("Riding")
            } currentValueLabel: {
                Text(LogbookFormatting.percent(stats.ridingInactiveRatio))
            }
            .gaugeStyle(.rpplRing(tint: MetricKind.riding.tint, lineWidth: 9))
            .frame(maxWidth: 96)
            .frame(maxWidth: .infinity)

            StatChip(
                metric: .riding,
                value: LogbookFormatting.compactDuration(stats.ridingDuration),
                caption: "Riding"
            )
            StatChip(
                metric: .inactive,
                value: LogbookFormatting.compactDuration(stats.inactiveDuration),
                caption: "Inactive"
            )
        }
    }

    /// Full width: every set on the session timeline at its real start and length.
    private func setsTile(_ stats: SessionStats, start: Date, end: Date) -> some View {
        InfoTile("Sets", metric: .sets) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                MetricValue("\(stats.setCount)")
                StatChip(metric: .laps, value: "\(stats.totalLapCount)", caption: "Laps")
                Spacer(minLength: 0)
            }
            if !stats.sets.isEmpty, end > start {
                TimelineBar(
                    spans: stats.sets.map {
                        MetricDisplay.span(from: $0.startedAt, to: $0.endedAt, inRangeFrom: start, to: end)
                    },
                    tint: MetricKind.sets.tint
                )
                HStack {
                    Text(start.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text(end.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(RpplDesign.secondaryText)
            }
        }
    }

    private func distanceTile(_ stats: SessionStats) -> some View {
        InfoTile("Distance", metric: .distance) {
            MetricValue(LogbookFormatting.distanceKilometers(stats.totalDistanceMeters))
            StatChip(
                metric: .duration,
                value: LogbookFormatting.compactDuration(stats.totalDuration),
                caption: "Duration"
            )
        }
    }

    @ViewBuilder
    private func energyTile(_ stats: SessionStats) -> some View {
        if let total = stats.totalEnergyKilocalories {
            InfoTile("Total calories", metric: .energy) {
                MetricValue(LogbookFormatting.kilocalories(total))
                if let active = stats.activeEnergyKilocalories {
                    StatChip(
                        metric: .energy,
                        value: LogbookFormatting.kilocalories(active),
                        caption: "Active calories"
                    )
                }
            }
        } else {
            InfoTile("Calories", metric: .energy) {
                missingCaloriesValue
            }
        }
    }

    @ViewBuilder
    private var setsSection: some View {
        if let stats = sessionStats {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sets")
                    .font(.title3.bold())
                    .foregroundStyle(Color.rpplText)

                if stats.sets.isEmpty {
                    Text("No sets detected.")
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                } else {
                    if stats.sets.count > 1 {
                        SetDurationChart(sets: stats.sets)
                    }
                    ForEach(stats.sets) { set in
                        SetDetailCard(
                            set: set,
                            locations: SessionLocationHelpers.downsample(
                                SessionLocationHelpers.locations(for: set, in: allLocations),
                                maxCount: Self.setMapPointBudget
                            )
                        )
                    }
                }
            }
        }
    }

    private var missingCaloriesValue: some View {
        HStack(spacing: 6) {
            MetricValue("-")
            Button {
                showsMissingCaloriesInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(RpplDesign.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About missing calories")
            .popover(isPresented: $showsMissingCaloriesInfo) {
                Text("No heart rate or calories recorded. The watch was likely worn over clothing or a wetsuit.")
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: 260)
                    .presentationCompactAdaptation(.popover)
            }
        }
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
                sessionMapTrackData = summary.mapTracks
                let linkedPark = try? await StoreIO.runOffMain {
                    try store.linkPark(
                        sessionId: sessionId,
                        center: summary.mapFrame.map {
                            ParkCoordinate(lat: $0.centerLatitude, lon: $0.centerLongitude)
                        },
                        parks: ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
                    )
                }
                if let linkedPark {
                    manifest = (try? store.readManifest(sessionId: sessionId)) ?? summary.manifest
                    cityName = linkedPark.name
                    PhoneWatchViewSync.pushViewUpdate(store: store, sessionId: sessionId)
                } else {
                    cityName = summary.cityName
                }
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
                    await loadTracks(store: store, sessionId: sessionId, sets: summary.stats.sets)
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
        sets: [SetSegmentStats]
    ) async {
        do {
            let locations = try await StoreIO.runOffMain {
                try store.readLocationSamples(sessionId: sessionId)
            }
            try Task.checkCancellation()
            let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
            allLocations = sortedLocations
            applyTrackLayers(locations: sortedLocations, sets: sets)
            if sessionMapTrackData == nil {
                sessionMapTrackData = SessionMapTrackBuilder.build(
                    locations: sortedLocations,
                    sets: sets
                )
            }
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
        manifest = bundle.manifest
        sessionStats = bundle.stats
        allLocations = sortedLocations
        mapFrame = bundle.mapFrame
        sessionMapTrackData = SessionMapTrackBuilder.build(
            locations: sortedLocations,
            sets: bundle.stats.sets
        )
        cityName = bundle.cityName
        applyTrackLayers(locations: sortedLocations, sets: bundle.stats.sets)
    }

    /// Per-set GPS for the set menu; drops a selection whose set no longer exists.
    private func applyTrackLayers(locations: [LocationSample], sets: [SetSegmentStats]) {
        let tracks = SessionSetTrackBuilder.tracks(locations: locations, sets: sets)
        setTracks = tracks
        if let index = soloSetIndex, !tracks.contains(where: { $0.setIndex == index }) {
            soloSetIndex = nil
        }
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
        if let exportURL {
            presentShareSheet(for: exportURL)
            return
        }
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
        exportURL = nil
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
            presentShareSheet(for: url)
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

    private func presentShareSheet(for url: URL) {
        // Present after toolbar ProgressView → icon swap so the share sheet is not dropped.
        Task { @MainActor in
            ActivitySharePresenter.present(items: [url])
        }
    }

    private func presentExportFailure(_ message: String) {
        finishExportTask()
        exportErrorText = message
        // Present after toolbar ProgressView → icon swap so SwiftUI does not drop the alert.
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

private struct SetDetailCard: View {
    let set: SetSegmentStats
    let locations: [LocationSample]
    var rendering: SessionMapRendering = .flat

    private var maxSpeedKmh: Double? {
        SessionLocationHelpers.peakSpeedKmh(for: set, locations: locations)
    }

    private var averageSpeedKmh: Double? {
        SessionLocationHelpers.averageSpeedKmh(for: set)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Set \(set.index)")
                } icon: {
                    Image(systemName: MetricKind.sets.systemImage)
                        .foregroundStyle(MetricKind.sets.tint)
                }
                .foregroundStyle(Color.rpplText)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

                if !set.highlights.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(set.highlights, id: \.rawValue) { highlight in
                            ParkChip(
                                text: LogbookFormatting.setHighlightLabel(highlight),
                                systemImage: highlight.badgeIcon,
                                tint: highlight.badgeTint,
                                fill: highlight.badgeTint.opacity(0.14)
                            )
                        }
                    }
                    .accessibilityLabel(LogbookFormatting.joinedSetHighlights(set.highlights))
                }
            }

            if locations.count >= 2 {
                ZStack {
                    SessionMapView(locations: locations, rendering: rendering)
                        .allowsHitTesting(false)

                    NavigationLink {
                        SessionMapFullscreenView(
                            locations: locations,
                            rendering: rendering,
                            title: String(localized: "Set \(set.index)")
                        )
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 168)
                .logbookNestedClip()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(String(localized: "Set \(set.index)"))
                .accessibilityHint(String(localized: "Shows full-screen map"))
            } else {
                Text("No GPS track for this set")
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .logbookNestedBackground(Color.rpplFill)
            }

            FlowLayout(spacing: 16) {
                StatChip(metric: .duration, value: LogbookFormatting.compactDuration(set.duration), caption: "Duration")
                StatChip(metric: .distance, value: LogbookFormatting.distanceKilometers(set.distanceMeters), caption: "Distance")
                StatChip(metric: .laps, value: "\(set.lapCount)", caption: "Laps")
                StatChip(
                    metric: .speed,
                    value: maxSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                    caption: "Max speed"
                )
                StatChip(
                    metric: .speed,
                    value: averageSpeedKmh.map(LogbookFormatting.speedKilometersPerHour) ?? "-",
                    caption: "Avg speed"
                )
            }

            Text(
                LogbookFormatting.sessionTimeRange(start: set.startedAt, end: set.endedAt)
            )
            .font(.caption)
            .foregroundStyle(RpplDesign.secondaryText)
        }
        .rpplTileChrome()
    }
}

/// One bar per set, height = minutes. One color: highlight badges live on the set cards.
private struct SetDurationChart: View {
    let sets: [SetSegmentStats]

    var body: some View {
        InfoTile("Duration", metric: .duration) {
            Chart(sets) { set in
                BarMark(
                    x: .value("Set", String(set.index)),
                    y: .value("Duration", set.duration / 60)
                )
                .foregroundStyle(MetricKind.sets.tint)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(verbatim: Duration.seconds(minutes * 60).formatted(
                                .units(allowed: [.minutes], width: .narrow)
                            ))
                        }
                    }
                }
            }
            .frame(height: 140)
        }
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
