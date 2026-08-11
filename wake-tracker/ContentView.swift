import SwiftUI
import MapKit
import WakeTrackerCore

struct ContentView: View {
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var permissions = PermissionsModel()
    @State private var manifests: [SessionManifest] = []
    @State private var selected: SessionManifest?

    var body: some View {
        NavigationStack {
            List {
                Section("Sync") {
                    SyncStatusIndicator(
                        state: connectivity.syncState,
                        footnote: connectivity.status
                    )
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
                    if manifests.isEmpty {
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
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wake Tracker")
            .navigationDestination(for: String.self) { sessionId in
                SessionDetailView(sessionId: sessionId, store: connectivity.store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reload") {
                        WakeLog.debug(.ui, "tap Reload sessions")
                        reload()
                    }
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

    private func reload() {
        do {
            let ids = try connectivity.store.listSessionIDs()
            manifests = try ids.compactMap { try connectivity.store.readManifest(sessionId: $0) }
                .sorted { $0.startedAt > $1.startedAt }
            WakeLog.debug(.ui, "reload sessions count=\(manifests.count)")
        } catch {
            manifests = []
            WakeLog.error(.store, "reload sessions: \(error.localizedDescription)")
        }
    }
}

struct SessionDetailView: View {
    let sessionId: String
    let store: SessionFileStore

    @State private var manifest: SessionManifest?
    @State private var labels: [LabelEvent] = []
    @State private var locations: [LocationSample] = []
    @State private var exportURL: URL?
    @State private var errorText: String?

    var body: some View {
        List {
            if let manifest {
                Section("Manifest") {
                    LabeledContent("Tester", value: String(manifest.testerId.prefix(8)) + "…")
                    LabeledContent("Watch", value: manifest.watchModel)
                    LabeledContent("OS", value: manifest.systemVersion)
                    LabeledContent("Schema", value: "\(manifest.schemaVersion)")
                    if let ended = manifest.endedAt {
                        LabeledContent("Ended", value: ended.formatted())
                    }
                }
            }

            Section("Map") {
                SessionMapView(locations: locations)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }

            Section("Labels (\(labels.count))") {
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

            Section("Samples") {
                LabeledContent("GPS points", value: "\(locations.count)")
            }

            Section {
                ShareLink(item: exportFile()) {
                    Label("Export session JSON", systemImage: "square.and.arrow.up")
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }
        }
        .navigationTitle("Session")
        .onAppear {
            WakeLog.debug(.ui, "SessionDetail onAppear \(sessionId.prefix(8))…")
            load()
        }
    }

    private func load() {
        do {
            manifest = try store.readManifest(sessionId: sessionId)
            labels = try store.readLabels(sessionId: sessionId)
            locations = try store.readLocationSamples(sessionId: sessionId)
            WakeLog.debug(
                .ui,
                "SessionDetail loaded labels=\(labels.count) gps=\(locations.count)"
            )
        } catch {
            errorText = error.localizedDescription
            WakeLog.error(.store, "SessionDetail load: \(error.localizedDescription)")
        }
    }

    private func exportFile() -> URL {
        if let exportURL { return exportURL }
        WakeLog.debug(.ui, "export session \(sessionId.prefix(8))…")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sessionId).json")
        do {
            let package = try store.buildTransferPackage(sessionId: sessionId)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(package).write(to: url, options: [.atomic])
            exportURL = url
            WakeLog.debug(.ui, "export OK \(sessionId.prefix(8))…")
            return url
        } catch {
            errorText = error.localizedDescription
            WakeLog.error(.store, "export: \(error.localizedDescription)")
            return url
        }
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
