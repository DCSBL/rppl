import SwiftUI
import MapKit
import RpplCore

private enum SessionDetailLoadPhase: Equatable {
    case manifest
    case detections
    case locations
    case stats
    case ready
    case cancelled
}

struct SessionDetailView: View {
    let sessionId: String
    let store: SessionFileStore

    private static let mapPointBudget = 800

    @State private var manifest: SessionManifest?
    @State private var detections: [DetectionEvent] = []
    /// Downsampled for MapKit; full count lives in `locationCount`.
    @State private var mapLocations: [LocationSample] = []
    @State private var locationCount = 0
    @State private var sessionStats: SessionStats?
    @State private var storedByteSize: Int64 = 0
    @State private var loadPhase: SessionDetailLoadPhase = .manifest
    @State private var loadTask: Task<Void, Never>?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var errorText: String?

    private var isLoading: Bool {
        switch loadPhase {
        case .manifest, .detections, .locations, .stats: return true
        case .ready, .cancelled: return false
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(loadStatusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            cancelLoad()
                        }
                    }
                }
            } else if loadPhase == .cancelled {
                Section {
                    HStack(spacing: 10) {
                        Text(errorText == nil ? "Load cancelled" : "Load failed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") {
                            retryLoad()
                        }
                    }
                }
            }

            if let manifest {
                Section("Manifest") {
                    LabeledContent("Tester", value: String(manifest.testerId.prefix(8)) + "…")
                    LabeledContent("Watch", value: manifest.watchModel)
                    LabeledContent("OS", value: manifest.systemVersion)
                    LabeledContent("Schema", value: "\(manifest.schemaVersion)")
                    LabeledContent("Size", value: ByteSizeFormat.string(storedByteSize))
                    LabeledContent("Started", value: manifest.startedAt.formatted())
                    if let ended = manifest.endedAt {
                        LabeledContent("Ended", value: ended.formatted())
                    }
                    LabeledContent("Transfer", value: manifest.transferState.rawValue)
                }
            }

            if let stats = sessionStats {
                Section("Summary") {
                    LabeledContent("Duration", value: Self.formatDuration(stats.totalDuration))
                    LabeledContent("Distance", value: DistanceFormat.meters(stats.totalDistanceMeters))
                    LabeledContent(
                        "Calories",
                        value: stats.activeEnergyKilocalories.map { String(format: "%.0f kcal", $0) } ?? "—"
                    )
                    LabeledContent("Rides", value: "\(stats.rideCount)")
                    LabeledContent(
                        "Riding",
                        value: "\(Int((stats.ridingPausedRatio * 100).rounded()))% · "
                            + Self.formatDuration(stats.ridingDuration)
                    )
                    LabeledContent("Paused", value: Self.formatDuration(stats.pausedDuration))
                }

                Section("Rides (\(stats.rides.count))") {
                    if stats.rides.isEmpty {
                        Text("No rides detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(stats.rides) { ride in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ride \(ride.index)")
                                .font(.headline)
                            Text(DistanceFormat.meters(ride.distanceMeters))
                                .font(.caption)
                            Text(Self.formatDuration(ride.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Map") {
                if mapLocations.isEmpty {
                    if loadPhase == .locations {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading GPS track…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                    } else if loadPhase == .ready || loadPhase == .cancelled {
                        Text("No GPS points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        Text("Map loads after detections")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                } else {
                    SessionMapView(locations: mapLocations)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Detections (\(detections.count))") {
                if loadPhase == .detections {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading detections…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if detections.isEmpty {
                    Text("No detections in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(detections) { detection in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detection.code).font(.headline)
                        Text(detection.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                        Text(detection.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if detection.supersedesId != nil {
                            Text("revision")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section("Samples") {
                LabeledContent(
                    "GPS points",
                    value: loadPhase == .locations || loadPhase == .detections || loadPhase == .manifest
                        ? "…"
                        : "\(locationCount)"
                )
                if locationCount > mapLocations.count, !mapLocations.isEmpty {
                    Text("Map shows \(mapLocations.count) of \(locationCount) points")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                } else if isExporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing export…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            cancelExport()
                        }
                    }
                } else {
                    Button {
                        startExport()
                    } label: {
                        Label("Export session JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(manifest == nil)
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle(String(sessionId.prefix(8)) + "…")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            WakeLog.debug(.ui, "SessionDetail onAppear \(sessionId.prefix(8))…")
            startLoadIfNeeded()
        }
        .onDisappear {
            cancelLoad()
            cancelExport()
        }
    }

    private var loadStatusText: String {
        switch loadPhase {
        case .manifest: return "Loading manifest…"
        case .detections: return "Loading detections…"
        case .locations: return "Loading GPS…"
        case .stats: return "Computing stats…"
        case .ready: return "Ready"
        case .cancelled: return "Cancelled"
        }
    }

    private func startLoadIfNeeded() {
        guard loadTask == nil else { return }
        guard loadPhase != .ready, loadPhase != .cancelled else { return }
        beginLoad()
    }

    private func retryLoad() {
        cancelLoad()
        errorText = nil
        detections = []
        mapLocations = []
        locationCount = 0
        sessionStats = nil
        beginLoad()
    }

    private func beginLoad() {
        loadPhase = .manifest
        storedByteSize = 0
        loadTask = Task(priority: .userInitiated) {
            await loadSession()
        }
    }

    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        if loadPhase != .ready {
            loadPhase = .cancelled
            WakeLog.debug(.ui, "SessionDetail load cancelled \(sessionId.prefix(8))…")
        }
    }

    private func loadSession() async {
        let store = store
        let sessionId = sessionId

        do {
            loadPhase = .manifest
            let loadedManifest = try await Self.runStoreIO {
                try store.readManifest(sessionId: sessionId)
            }
            try Task.checkCancellation()
            manifest = loadedManifest
            loadPhase = .detections

            let loadedDetections = try await Self.runStoreIO {
                try store.readDetections(sessionId: sessionId)
            }
            try Task.checkCancellation()
            detections = loadedDetections
            loadPhase = .locations

            let locationBundle = try await Self.runStoreIO {
                let locations = try store.readLocationSamples(sessionId: sessionId)
                try Task.checkCancellation()
                let mapPoints = SessionLocationHelpers.downsample(locations, maxCount: Self.mapPointBudget)
                let size = try store.sessionByteSize(sessionId: sessionId)
                return (locations, locations.count, mapPoints, size)
            }
            try Task.checkCancellation()
            locationCount = locationBundle.1
            mapLocations = locationBundle.2
            storedByteSize = locationBundle.3
            loadPhase = .stats

            let stats = try await Self.runStoreIO {
                let health = try store.readHealthSamples(sessionId: sessionId)
                return SessionStatsBuilder.build(
                    manifest: loadedManifest,
                    detections: loadedDetections,
                    locations: locationBundle.0,
                    health: health
                )
            }
            try Task.checkCancellation()
            sessionStats = stats
            loadPhase = .ready
            loadTask = nil
            WakeLog.debug(
                .ui,
                "SessionDetail loaded detections=\(detections.count) gps=\(locationCount) "
                    + "rides=\(stats.rideCount) size=\(ByteSizeFormat.string(storedByteSize))"
            )
        } catch is CancellationError {
            if loadPhase != .ready {
                loadPhase = .cancelled
            }
            loadTask = nil
        } catch {
            errorText = error.localizedDescription
            loadPhase = .cancelled
            loadTask = nil
            WakeLog.error(.store, "SessionDetail load: \(error.localizedDescription)")
        }
    }

    private func startExport() {
        guard exportTask == nil, !isExporting else { return }
        isExporting = true
        errorText = nil
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
        let store = store
        let sessionId = sessionId
        WakeLog.debug(.ui, "export session \(sessionId.prefix(8))…")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sessionId).json")

        do {
            try await Self.runStoreIO {
                let package = try store.buildTransferPackage(sessionId: sessionId)
                try Task.checkCancellation()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(package).write(to: url, options: [.atomic])
            }
            try Task.checkCancellation()
            exportURL = url
            isExporting = false
            exportTask = nil
            WakeLog.debug(.ui, "export OK \(sessionId.prefix(8))…")
        } catch is CancellationError {
            isExporting = false
            exportTask = nil
            WakeLog.debug(.ui, "export cancelled \(sessionId.prefix(8))…")
        } catch {
            errorText = error.localizedDescription
            isExporting = false
            exportTask = nil
            WakeLog.error(.store, "export: \(error.localizedDescription)")
        }
    }

    private static func runStoreIO<T: Sendable>(
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

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SessionMapView: View {
    let locations: [LocationSample]

    var body: some View {
        Map {
            if locations.count >= 2 {
                MapPolyline(coordinates: locations.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(.blue, lineWidth: 3)
            }
            if let first = locations.first {
                Marker("Start", coordinate: CLLocationCoordinate2D(
                    latitude: first.latitude,
                    longitude: first.longitude
                ))
            }
            if let last = locations.last, locations.count > 1 {
                Marker("End", coordinate: CLLocationCoordinate2D(
                    latitude: last.latitude,
                    longitude: last.longitude
                ))
            }
        }
    }
}
