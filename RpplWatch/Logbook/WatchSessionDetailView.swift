import SwiftUI
import MapKit
import RpplCore

enum WatchSessionDetailSource: Equatable {
    case entry(WatchSessionEntry)
    case bundledExample
}

struct WatchSessionDetailView: View {
    let source: WatchSessionDetailSource

    private static let exampleFileName = "FBDC7D8C-8FEA-47B6-911B-00E94A8A496C"
    private static let store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)

    @State private var manifest: SessionManifest?
    @State private var stats: SessionStats?
    @State private var cityName: String?
    @State private var mapFrame: MapTrackFrame?
    @State private var mapTracks: SessionMapTrackData?
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var loadPhase: LoadPhase
    @State private var errorText: String?

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed
    }

    init(entry: WatchSessionEntry) {
        source = .entry(entry)
        _manifest = State(initialValue: entry.manifest)
        _stats = State(initialValue: entry.stats)
        _cityName = State(initialValue: entry.cityName)
        _mapFrame = State(initialValue: entry.mapFrame)
        _mapTracks = State(initialValue: entry.mapTracks)
        _loadPhase = State(initialValue: .ready)
    }

    init(source: WatchSessionDetailSource) {
        self.source = source
        switch source {
        case .entry(let entry):
            _manifest = State(initialValue: entry.manifest)
            _stats = State(initialValue: entry.stats)
            _cityName = State(initialValue: entry.cityName)
            _mapFrame = State(initialValue: entry.mapFrame)
            _mapTracks = State(initialValue: entry.mapTracks)
            _loadPhase = State(initialValue: .ready)
        case .bundledExample:
            _loadPhase = State(initialValue: .loading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch loadPhase {
                case .loading:
                    ProgressView("Loading session…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .failed:
                    ContentUnavailableView(
                        "Could not load session",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText ?? String(localized: "Try again later."))
                    )
                    .frame(minHeight: 120)
                case .ready:
                    detailContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .preferredColorScheme(.dark)
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private var detailContent: some View {
        WatchSessionMapPreview(
            mapTracks: mapTracks,
            startCoordinate: startCoordinate,
            mapFrame: mapFrame,
            cityName: cityName
        )

        if let stats {
            Text(WatchLogbookFormatting.sessionDateTimeLine(
                start: manifest?.startedAt ?? stats.startedAt,
                end: manifest?.endedAt ?? stats.endedAt
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(SessionFormatters.elapsed(stats.totalDuration))
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.rpplIdlePrimary)

            SessionMetricRow(
                label: "Distance",
                value: SessionFormatters.distance(stats.totalDistanceMeters)
            )
            SessionMetricRow(
                label: "Rides",
                value: "\(stats.rideCount)"
            )
            SessionMetricRow(
                label: "Laps",
                value: "\(stats.totalLapCount)"
            )

            if let maxSpeed = stats.maxSpeedKmh ?? stats.topSpeedKmh {
                SessionMetricRow(
                    label: "Max speed",
                    value: SessionFormatters.averageSpeed(maxSpeed)
                )
            }

            Divider()
                .padding(.vertical, 4)

            WatchRideListSection(rides: stats.rides, emptyMessage: "No rides detected.")
        }
    }

    private var navigationTitle: String {
        if case .bundledExample = source {
            return String(localized: "Example session")
        }
        guard let manifest else { return String(localized: "Session") }
        return WatchLogbookFormatting.sessionDate(manifest.startedAt)
    }

    private func loadIfNeeded() async {
        switch source {
        case .entry(let entry):
            await loadMapDataIfNeeded(sessionId: entry.manifest.sessionId, stats: entry.stats)
        case .bundledExample:
            await loadExample()
        }
    }

    private func loadMapDataIfNeeded(sessionId: String, stats: SessionStats) async {
        if mapTracks == nil {
            if let derived = try? await StoreIO.runOffMain {
                try Self.store.readDerivedView(sessionId: sessionId)
            }, let tracks = derived.mapTracks {
                mapTracks = tracks
                mapFrame = derived.mapFrame
            }
        }

        if mapTracks == nil, Self.store.hasRawStreams(sessionId: sessionId) {
            let built = try? await StoreIO.runOffMain {
                let locations = try Self.store.readLocationSamples(sessionId: sessionId)
                return SessionMapTrackBuilder.build(locations: locations, rides: stats.rides)
            }
            if let built {
                mapTracks = built
            }
        }

        if startCoordinate == nil {
            if let mapTracks {
                startCoordinate = CLLocationCoordinate2D(
                    latitude: mapTracks.start.latitude,
                    longitude: mapTracks.start.longitude
                )
            } else if Self.store.hasRawStreams(sessionId: sessionId) {
                let peek = try? await StoreIO.runOffMain {
                    try Self.store.peekLocationSamples(sessionId: sessionId, limit: 1)
                }
                if let first = peek?.first {
                    startCoordinate = CLLocationCoordinate2D(
                        latitude: first.latitude,
                        longitude: first.longitude
                    )
                }
            }
        }
    }

    private func loadExample() async {
        guard loadPhase == .loading else { return }
        do {
            let bundle = try await StoreIO.runOffMain {
                try Self.loadBundledExample()
            }
            manifest = bundle.manifest
            stats = bundle.stats
            cityName = bundle.cityName
            mapFrame = bundle.mapFrame
            mapTracks = SessionMapTrackBuilder.build(
                locations: bundle.locations,
                rides: bundle.stats.rides
            )
            if let mapTracks {
                startCoordinate = CLLocationCoordinate2D(
                    latitude: mapTracks.start.latitude,
                    longitude: mapTracks.start.longitude
                )
            } else if let first = bundle.locations.first {
                startCoordinate = CLLocationCoordinate2D(
                    latitude: first.latitude,
                    longitude: first.longitude
                )
            }
            loadPhase = .ready
        } catch {
            errorText = error.localizedDescription
            loadPhase = .failed
            WakeLog.error(.store, "WatchSessionDetail example load: \(error.localizedDescription)")
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
        return try SessionLoader.loadExample(packageURL: url)
    }
}
