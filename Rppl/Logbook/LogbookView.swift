import SwiftUI
import UIKit
import RpplCore

struct LogbookView: View {
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var catalog = SessionCatalog()
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false
    @State private var showExampleSession = false
    @State private var actionErrorText: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(LogbookLayout.rowInsets(top: 8, bottom: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    SyncStatusIndicator(
                        state: connectivity.syncState,
                        pendingCount: connectivity.pendingAckCount
                    )
                    .listRowInsets(LogbookLayout.rowInsets(top: 0, bottom: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    totalsCard
                        .listRowInsets(LogbookLayout.rowInsets(top: 4, bottom: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if catalog.isLoading && catalog.entries.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading sessions…")
                            Spacer()
                        }
                        .listRowInsets(LogbookLayout.rowInsets())
                        .listRowBackground(Color.clear)
                    }
                } else if catalog.entries.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label {
                                Text("No sessions yet")
                            } icon: {
                                Image("icon-simple")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(Color.rpplMuted.opacity(0.45))
                            }
                        } description: {
                            Text(
                                "Recording needs Apple Watch. Open Rppl on Watch, start a cable-park session, then keep iPhone nearby to sync. No Watch? Browse the example."
                            )
                        } actions: {
                            Button("Show example session") {
                                showExampleSession = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Color.rpplAccent)
                        }
                        .foregroundStyle(Color.rpplText)
                        .listRowInsets(LogbookLayout.rowInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(catalog.entries) { entry in
                            NavigationLink {
                                LogbookSessionDetailView(
                                    sessionId: entry.manifest.sessionId,
                                    store: connectivity.store
                                )
                            } label: {
                                SessionCard(entry: entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    WakeLog.debug(.ui, "swipe delete \(entry.manifest.sessionId.prefix(8))…")
                                    // #region agent log
                                    agentDebugLog(
                                        hypothesisId: "A,B,D",
                                        location: "LogbookView.swift:swipeDelete",
                                        message: "swipe delete requested confirmationDialog",
                                        data: [
                                            "sessionIdPrefix": String(entry.manifest.sessionId.prefix(8)),
                                            "entryCount": catalog.entries.count,
                                            "presentationAPI": "confirmationDialog",
                                            "modifierHost": "List_inside_NavigationStack",
                                            "sizeClass": horizontalSizeClass == .regular ? "regular" : "compact"
                                        ]
                                    )
                                    // #endregion
                                    pendingDeleteSessionId = entry.manifest.sessionId
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        sessionsHeader
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, LogbookLayout.horizontalInset, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .background(Color.rpplBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(Color.rpplAccent)
            .navigationDestination(isPresented: $showExampleSession) {
                LogbookSessionDetailView(source: .bundledExample)
                    .toolbar(.visible, for: .navigationBar)
            }
            .confirmationDialog(
                "Delete Session?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    // #region agent log
                    agentDebugLog(
                        hypothesisId: "E",
                        location: "LogbookView.swift:confirmDelete",
                        message: "user confirmed delete via confirmationDialog",
                        data: [
                            "sessionIdPrefix": pendingDeleteSessionId.map { String($0.prefix(8)) } ?? "nil",
                            "presentationAPI": "confirmationDialog"
                        ]
                    )
                    // #endregion
                    if let sessionId = pendingDeleteSessionId {
                        deleteSession(sessionId)
                    }
                    pendingDeleteSessionId = nil
                }
                Button("Cancel", role: .cancel) {
                    // #region agent log
                    agentDebugLog(
                        hypothesisId: "A",
                        location: "LogbookView.swift:cancelDelete",
                        message: "user canceled confirmationDialog",
                        data: ["presentationAPI": "confirmationDialog"]
                    )
                    // #endregion
                    pendingDeleteSessionId = nil
                }
            } message: {
                Text("This permanently removes the session from this iPhone. This cannot be undone.")
            }
            .alert(
                "Could Not Delete Session",
                isPresented: Binding(
                    get: { actionErrorText != nil },
                    set: { if !$0 { actionErrorText = nil } }
                )
            ) {
                Button("OK", role: .cancel) { actionErrorText = nil }
            } message: {
                Text(actionErrorText ?? "")
            }
            .onAppear {
                connectivity.refreshSyncState()
                catalog.reload(store: connectivity.store)
                // #region agent log
                agentDebugLog(
                    hypothesisId: "A,C",
                    location: "LogbookView.swift:onAppear",
                    message: "Logbook appeared; delete uses confirmationDialog (iPhone bottom sheet)",
                    data: [
                        "presentationAPI": "confirmationDialog",
                        "expectedIPhoneStyle": "bottomActionSheet",
                        "centeredAlternative": "alert",
                        "sizeClass": horizontalSizeClass == .regular ? "regular" : "compact",
                        "idiom": UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone"
                    ]
                )
                // #endregion
            }
            .onChange(of: connectivity.sessionsRevision) { _, _ in
                catalog.reload(store: connectivity.store)
            }
            .onChange(of: showDeleteConfirmation) { _, isPresented in
                // #region agent log
                agentDebugLog(
                    hypothesisId: "A,B,C,D",
                    location: "LogbookView.swift:showDeleteConfirmation",
                    message: isPresented ? "confirmationDialog presenting" : "confirmationDialog dismissed",
                    data: [
                        "isPresented": isPresented,
                        "pendingSessionIdPrefix": pendingDeleteSessionId.map { String($0.prefix(8)) } ?? "nil",
                        "presentationAPI": "confirmationDialog",
                        "modifierHost": "List_inside_NavigationStack_not_row",
                        "sizeClass": horizontalSizeClass == .regular ? "regular" : "compact",
                        "note": "SwiftUI confirmationDialog on compact = bottom sheet; no row anchor"
                    ]
                )
                // #endregion
            }
        }
    }

    // #region agent log
    private func agentDebugLog(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        var payload: [String: Any] = [
            "sessionId": "ed3251",
            "runId": "pre-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "data": data
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        // File sink (Simulator shares host FS for absolute Mac paths in practice via ingest)
        let path = "/Users/ducosebel/Development/rppl/.cursor/debug-ed3251.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: body)
            try? handle.write(contentsOf: Data("\n".utf8))
        } else {
            FileManager.default.createFile(atPath: path, contents: body + Data("\n".utf8))
        }
        guard let url = URL(string: "http://127.0.0.1:7587/ingest/a62eff6e-0d4d-4266-b71b-b6c8b7fef170") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ed3251", forHTTPHeaderField: "X-Debug-Session-Id")
        req.httpBody = body
        URLSession.shared.dataTask(with: req).resume()
    }
    // #endregion

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Logbook")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.rpplText)
            Text("Cable park sessions · Watch records")
                .font(.subheadline)
                .foregroundStyle(Color.rpplMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalsCard: some View {
        let totals = catalog.totals
        return VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("TOTAL")
            } icon: {
                MDIIconView(icon: .skiWater)
                    .frame(width: 14, height: 14)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.rpplAccent)
            .labelStyle(.titleAndIcon)

            HStack(spacing: 0) {
                totalMetric(
                    value: catalog.isLoading ? "—" : "\(totals.sessionCount)",
                    label: "Sessions"
                )
                totalDivider
                totalMetric(
                    value: catalog.isLoading
                        ? "—"
                        : LogbookFormatting.distanceKilometers(totals.totalDistanceMeters),
                    label: "Distance"
                )
                totalDivider
                totalMetric(
                    value: catalog.isLoading || totals.topSpeedKmh <= 0
                        ? "—"
                        : LogbookFormatting.speedKilometersPerHour(totals.topSpeedKmh),
                    label: "Max Speed"
                )
            }

            Divider()
                .overlay(Color.rpplFill)

            Text(
                catalog.isLoading
                    ? String(localized: "— total rides")
                    : LogbookFormatting.totalsFooter(
                        rides: totals.totalRuns,
                        laps: totals.totalLaps
                    )
            )
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
        }
        .padding(20)
        .background(Color.rpplCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var totalDivider: some View {
        Rectangle()
            .fill(Color.rpplFill)
            .frame(width: 1, height: 44)
    }

    private func totalMetric(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color.rpplText)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionsHeader: some View {
        HStack {
            Text("Sessions")
                .font(.title3.bold())
                .foregroundStyle(Color.rpplText)
            Spacer()
            Text(catalog.isLoading ? "…" : LogbookFormatting.sessionCount(catalog.entries.count))
                .font(.subheadline)
                .foregroundStyle(Color.rpplMuted)
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func deleteSession(_ sessionId: String) {
        WakeLog.debug(.ui, "confirm delete \(sessionId.prefix(8))…")
        do {
            try connectivity.store.deleteSession(sessionId: sessionId)
            SessionCityResolver.shared.invalidate(sessionId: sessionId)
            WakeLog.debug(.store, "deleted session \(sessionId.prefix(8))…")
            catalog.reload(store: connectivity.store)
        } catch {
            actionErrorText = error.localizedDescription
            WakeLog.error(.store, "delete session: \(error.localizedDescription)")
        }
    }
}

private struct SessionCard: View {
    let entry: SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    (
                        Text(ActivityCodes.localizedTitle(for: entry.manifest.activityCode))
                            .foregroundStyle(Color.rpplText)
                        + (entry.highlights.isEmpty
                            ? Text("")
                            : Text(" - \(LogbookFormatting.joinedSessionHighlights(entry.highlights))")
                                .foregroundStyle(Color.rpplMuted))
                    )
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(timeRangeText)
                        .font(.caption)
                        .foregroundStyle(Color.rpplMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(LogbookFormatting.sessionDate(entry.manifest.startedAt))
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)

                    Text(entry.cityName ?? "—")
                        .font(.caption)
                        .foregroundStyle(Color.rpplMuted)
                }
            }

            Divider()
                .overlay(Color.rpplFill)

            HStack(spacing: 12) {
                statLabel("clock", value: durationText)
                statLabel("water.waves", value: distanceText)
                statLabel("flag.checkered", value: ridesText)
                statLabel("arrow.triangle.2.circlepath", value: lapsText)
            }
            .font(.caption)
            .foregroundStyle(Color.rpplMuted)
        }
        .padding(16)
        .background(Color.rpplCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var timeRangeText: String {
        LogbookFormatting.sessionTimeRange(
            start: entry.manifest.startedAt,
            end: entry.manifest.endedAt ?? entry.stats?.endedAt
        )
    }

    private var durationText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.duration(stats.totalDuration)
    }

    private var distanceText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.distanceKilometers(stats.totalDistanceMeters)
    }

    private var ridesText: String {
        guard let stats = entry.stats else { return String(localized: "— rides") }
        return LogbookFormatting.rideCount(stats.rideCount)
    }

    private var lapsText: String {
        guard let stats = entry.stats else { return String(localized: "— laps") }
        return LogbookFormatting.lapCount(stats.totalLapCount)
    }

    private func statLabel(_ symbol: String, value: String) -> some View {
        Label(value, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private enum LogbookLayout {
    static let horizontalInset: CGFloat = 16

    static func rowInsets(top: CGFloat = 8, bottom: CGFloat = 8) -> EdgeInsets {
        EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }
}

#Preview {
    LogbookView()
}
