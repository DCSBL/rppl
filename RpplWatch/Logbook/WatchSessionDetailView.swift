import SwiftUI
import MapKit
import RpplCore

enum WatchSessionDetailSource: Equatable {
    case store(sessionId: String)
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
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var loadPhase: LoadPhase = .loading
    @State private var errorText: String?

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed
    }

    init(sessionId: String) {
        self.source = .store(sessionId: sessionId)
    }

    init(source: WatchSessionDetailSource) {
        self.source = source
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: StartMapCoordinate.self) { coordinate in
            SessionStartMapFullscreenView(
                coordinate: coordinate.coordinate,
                distanceMeters: 500
            )
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .navigation)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var detailContent: some View {
        SessionMapStripView(startCoordinate: startCoordinate, mapFrame: mapFrame)

        if let cityName, !cityName.isEmpty {
            Text(cityName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let stats {
            Text(WatchLogbookFormatting.sessionTimeRange(
                start: manifest?.startedAt ?? stats.startedAt,
                end: manifest?.endedAt ?? stats.endedAt
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(SessionFormatters.elapsed(stats.totalDuration))
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.rpplIdlePrimary)

            HStack(alignment: .top, spacing: 12) {
                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(stats.totalDistanceMeters)
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionMetricRow(
                    label: "Rides",
                    value: "\(stats.rideCount)"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SessionMetricRow(
                label: "Laps",
                value: "\(stats.totalLapCount)"
            )

            if let maxSpeed = stats.maxSpeedKmh ?? stats.topSpeedKmh {
                SessionMetricRow(
                    label: "Max speed",
                    value: String(format: "%.1f km/h", maxSpeed)
                )
            }

            if let lastRide = stats.rides.last {
                Divider()
                    .padding(.vertical, 2)

                Text("Last ride")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SessionMetricRow(
                    label: "Duration",
                    value: SessionFormatters.segmentDuration(lastRide.duration)
                )
                SessionMetricRow(
                    label: "Distance",
                    value: SessionFormatters.distance(lastRide.distanceMeters)
                )
                SessionMetricRow(
                    label: "Laps",
                    value: "\(lastRide.lapCount)"
                )
            } else {
                Divider()
                    .padding(.vertical, 2)
                Text("No rides yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navigationTitle: String {
        if case .bundledExample = source {
            return String(localized: "Example session")
        }
        guard let manifest else { return String(localized: "Session") }
        return WatchLogbookFormatting.sessionDate(manifest.startedAt)
    }

    private func load() async {
        do {
            switch source {
            case .store(let sessionId):
                let summary = try await StoreIO.runOffMain {
                    try SessionLoader.loadStoredSummary(store: Self.store, sessionId: sessionId)
                }
                manifest = summary.manifest
                stats = summary.stats
                cityName = summary.cityName
                mapFrame = summary.mapFrame

                let peek = try? await StoreIO.runOffMain {
                    try Self.store.peekLocationSamples(sessionId: sessionId, limit: 1)
                }
                if let first = peek?.first {
                    startCoordinate = CLLocationCoordinate2D(
                        latitude: first.latitude,
                        longitude: first.longitude
                    )
                }
                loadPhase = .ready

            case .bundledExample:
                let bundle = try await StoreIO.runOffMain {
                    try Self.loadBundledExample()
                }
                manifest = bundle.manifest
                stats = bundle.stats
                cityName = bundle.cityName
                mapFrame = bundle.mapFrame
                if let first = bundle.locations.first {
                    startCoordinate = CLLocationCoordinate2D(
                        latitude: first.latitude,
                        longitude: first.longitude
                    )
                }
                loadPhase = .ready
            }
        } catch {
            errorText = error.localizedDescription
            loadPhase = .failed
            WakeLog.error(.store, "WatchSessionDetail load: \(error.localizedDescription)")
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
