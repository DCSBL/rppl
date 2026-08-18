import SwiftUI
import HealthKit
import RpplCore

struct DebugView: View {
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var permissions = PermissionsModel()
    @State private var manifests: [SessionManifest] = []
    @State private var sessionSizes: [String: Int64] = [:]
    @State private var syncedTotalBytes: Int64 = 0
    @State private var isReloadingSessions = false
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false
    @State private var hkInjectMessage: String?
    @State private var hkInjectError: String?
    @State private var isInjectingHealthKit = false

    private let healthStore = HKHealthStore()

    var body: some View {
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

            Section("HealthKit") {
                Button {
                    WakeLog.debug(.ui, "tap Inject HealthKit fixture")
                    injectHealthKitFixture()
                } label: {
                    if isInjectingHealthKit {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Injecting fixture…")
                        }
                    } else {
                        Text("Inject workout from fixture")
                    }
                }
                .disabled(isInjectingHealthKit)
                if let hkInjectMessage {
                    Text(hkInjectMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let hkInjectError {
                    Text(hkInjectError)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                    NavigationLink(value: DebugSessionRoute(sessionId: manifest.sessionId)) {
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
        .navigationTitle("Debug")
        .scrollContentBackground(.hidden)
        .background(Color.rpplBackground)
        .toolbarBackground(Color.rpplBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        .task {
            WakeLog.debug(.lifecycle, "DebugView task")
            permissions.refresh()
            connectivity.refreshSyncState()
            reload()
        }
        .onChange(of: connectivity.sessionsRevision) { _, _ in
            WakeLog.debug(.ui, "sessionsRevision changed — reload")
            reload()
        }
    }

    private func injectHealthKitFixture() {
        hkInjectMessage = nil
        hkInjectError = nil
        isInjectingHealthKit = true
        Task {
            do {
                let summary = try await HealthKitDebugInjector.inject(healthStore: healthStore)
                await MainActor.run {
                    hkInjectMessage = summary
                    hkInjectError = nil
                    isInjectingHealthKit = false
                    WakeLog.debug(.ui, "HK inject OK: \(summary)")
                }
            } catch {
                await MainActor.run {
                    hkInjectError = error.localizedDescription
                    hkInjectMessage = nil
                    isInjectingHealthKit = false
                    WakeLog.error(.ui, "HK inject: \(error.localizedDescription)")
                }
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

#Preview {
    NavigationStack {
        DebugView()
            .navigationDestination(for: DebugSessionRoute.self) { route in
                SessionDetailView(
                    sessionId: route.sessionId,
                    store: PhoneConnectivityService.shared.store
                )
            }
    }
}
