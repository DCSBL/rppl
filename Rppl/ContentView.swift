import SwiftUI
import MapKit
import RpplCore

struct ContentView: View {
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var permissions = PermissionsModel()
    @State private var manifests: [SessionManifest] = []
    @State private var sessionSizes: [String: Int64] = [:]
    @State private var syncedTotalBytes: Int64 = 0
    @State private var selected: SessionManifest?
    @State private var isReloadingSessions = false
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Sync") {
                    SyncStatusIndicator(
                        state: connectivity.syncState,
                        footnote: connectivity.status
                    )
                    LabeledContent("Synced data", value: ByteSizeFormat.string(syncedTotalBytes))
                    Text(connectivity.wcDebugSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Refresh sync status") {
                        WakeLog.debug(.ui, "tap Refresh sync status")
                        connectivity.refreshSyncState()
                    }
                }

                Section("Permissions") {
                    LabeledContent("Health", value: permissions.healthStatus)
                    LabeledContent("Location", value: permissions.locationStatus)
                    LabeledContent("Motion", value: permissions.motionStatus)
                    Button("Request permissions") {
                        WakeLog.debug(.ui, "tap Request permissions")
                        Task { await permissions.requestAll() }
                    }
                    if let err = permissions.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Section("Sessions") {
                    if isReloadingSessions && manifests.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading sessions…")
                                .foregroundStyle(.secondary)
                        }
                    } else if manifests.isEmpty {
                        Text("No sessions yet. Record on Apple Watch, then bring phone nearby.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manifests, id: \.sessionId) { manifest in
                        NavigationLink(value: manifest.sessionId) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manifest.startedAt.formatted(date: .abbreviated, time: .shortened))
                                Text("\(manifest.sessionId.prefix(8))… · \(manifest.transferState.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let size = sessionSizes[manifest.sessionId] {
                                    Text(ByteSizeFormat.string(size))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                WakeLog.debug(.ui, "swipe delete \(manifest.sessionId.prefix(8))…")
                                pendingDeleteSessionId = manifest.sessionId
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rppl")
            .navigationDestination(for: String.self) { sessionId in
                SessionDetailView(sessionId: sessionId, store: connectivity.store)
            }
            .confirmationDialog(
                "Delete Session?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let sessionId = pendingDeleteSessionId {
                        deleteSession(sessionId)
                    }
                    pendingDeleteSessionId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteSessionId = nil
                }
            } message: {
                Text("This permanently removes the session from this iPhone. This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reload") {
                        WakeLog.debug(.ui, "tap Reload sessions")
                        reload()
                    }
                    .disabled(isReloadingSessions)
                }
            }
            .onAppear {
                WakeLog.debug(.lifecycle, "Phone ContentView onAppear")
                permissions.refresh()
                connectivity.refreshSyncState()
                reload()
            }
            .onChange(of: connectivity.sessionsRevision) { _, _ in
                WakeLog.debug(.ui, "sessionsRevision changed — reload")
                reload()
            }
        }
    }

    private func deleteSession(_ sessionId: String) {
        WakeLog.debug(.ui, "confirm delete \(sessionId.prefix(8))…")
        do {
            try connectivity.store.deleteSession(sessionId: sessionId)
            WakeLog.debug(.store, "deleted session \(sessionId.prefix(8))…")
            reload()
        } catch {
            WakeLog.error(.store, "delete session: \(error.localizedDescription)")
        }
    }

    private func reload() {
        isReloadingSessions = true
        Task(priority: .userInitiated) {
            let store = connectivity.store
            do {
                let ids = try store.listSessionIDs()
                let loaded = try ids.compactMap { try store.readManifest(sessionId: $0) }
                    .sorted { $0.startedAt > $1.startedAt }
                var sizes: [String: Int64] = [:]
                for id in ids {
                    sizes[id] = (try? store.sessionByteSize(sessionId: id)) ?? 0
                }
                let total = try store.totalStoredByteSize()
                await MainActor.run {
                    manifests = loaded
                    sessionSizes = sizes
                    syncedTotalBytes = total
                    isReloadingSessions = false
                    WakeLog.debug(
                        .ui,
                        "reload sessions count=\(loaded.count) synced=\(ByteSizeFormat.string(total))"
                    )
                }
            } catch {
                await MainActor.run {
                    manifests = []
                    sessionSizes = [:]
                    syncedTotalBytes = 0
                    isReloadingSessions = false
                    WakeLog.error(.store, "reload sessions: \(error.localizedDescription)")
                }
            }
        }
    }
}

private enum SessionDetailLoadPhase: Equatable {
    case manifest
    case labels
    case locations
    case ready
    case cancelled
}

struct SessionDetailView: View {
    let sessionId: String
    let store: SessionFileStore

    private static let mapPointBudget = 800

    @State private var manifest: SessionManifest?
    @State private var labels: [LabelEvent] = []
    @State private var assumptions: [AssumptionEvent] = []
    /// Downsampled for MapKit; full count lives in `locationCount`.
    @State private var mapLocations: [LocationSample] = []
    @State private var locationCount = 0
    @State private var storedByteSize: Int64 = 0
    @State private var loadPhase: SessionDetailLoadPhase = .manifest
    @State private var loadTask: Task<Void, Never>?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var errorText: String?

    private var isLoading: Bool {
        switch loadPhase {
        case .manifest, .labels, .locations: return true
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
                        Text("Map loads after GPS…")
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

            Section("Legacy labels (\(labels.count))") {
                if loadPhase == .labels {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading labels…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if labels.isEmpty {
                    Text("No legacy labels in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(labels) { label in
                    VStack(alignment: .leading) {
                        Text(label.code).font(.headline)
                        Text(label.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                        if let gps = label.gps {
                            Text(String(format: "%.5f, %.5f", gps.latitude, gps.longitude))
                                .font(.caption2)
                                .monospaced()
                        }
                        if let water = label.waterSubmersionState {
                            Text("water: \(water)").font(.caption2)
                        }
                        if let temp = label.waterTemperatureCelsius {
                            Text(String(format: "waterTemp: %.1f°C", temp)).font(.caption2)
                        }
                        if let activity = label.motionActivity {
                            Text("activity: \(activity)").font(.caption2)
                        }
                    }
                }
            }

            Section("Assumptions (\(assumptions.count))") {
                if assumptions.isEmpty && loadPhase != .labels && loadPhase != .manifest {
                    Text("No auto assumptions in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(assumptions) { assumption in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assumption.code).font(.headline)
                        Text(assumption.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                        Text(assumption.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Samples") {
                LabeledContent(
                    "GPS points",
                    value: loadPhase == .locations || loadPhase == .labels || loadPhase == .manifest
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
        case .labels: return "Loading labels…"
        case .locations: return "Loading GPS…"
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
        labels = []
        assumptions = []
        mapLocations = []
        locationCount = 0
        // Keep manifest if already loaded; otherwise clear for a full restart.
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
            loadPhase = .labels

            let labelBundle = try await Self.runStoreIO {
                let labels = try store.readLabels(sessionId: sessionId)
                try Task.checkCancellation()
                let assumptions = try store.readAssumptions(sessionId: sessionId)
                return (labels, assumptions)
            }
            try Task.checkCancellation()
            labels = labelBundle.0
            assumptions = labelBundle.1
            loadPhase = .locations

            let locationBundle = try await Self.runStoreIO {
                let locations = try store.readLocationSamples(sessionId: sessionId)
                try Task.checkCancellation()
                let mapPoints = Self.downsample(locations, maxCount: Self.mapPointBudget)
                let size = try store.sessionByteSize(sessionId: sessionId)
                return (locations.count, mapPoints, size)
            }
            try Task.checkCancellation()
            locationCount = locationBundle.0
            mapLocations = locationBundle.1
            storedByteSize = locationBundle.2
            loadPhase = .ready
            loadTask = nil
            WakeLog.debug(
                .ui,
                "SessionDetail loaded labels=\(labels.count) assumptions=\(assumptions.count) gps=\(locationCount) size=\(ByteSizeFormat.string(storedByteSize))"
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
                // Compact JSON — pretty-print of 50Hz motion makes huge files slower.
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

    /// Runs store I/O off the main actor; cancels with the enclosing task (unlike `Task.detached`).
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

    /// Evenly pick up to `maxCount` samples so MapKit stays responsive.
    private static func downsample(_ locations: [LocationSample], maxCount: Int) -> [LocationSample] {
        guard maxCount > 1, locations.count > maxCount else { return locations }
        let lastIndex = locations.count - 1
        let step = Double(lastIndex) / Double(maxCount - 1)
        var result: [LocationSample] = []
        result.reserveCapacity(maxCount)
        for i in 0..<maxCount {
            let index = min(lastIndex, Int((Double(i) * step).rounded()))
            result.append(locations[index])
        }
        return result
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

#Preview {
    ContentView()
}
