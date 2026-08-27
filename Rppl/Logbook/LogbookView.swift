import SwiftUI
import RpplCore

struct LogbookView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var catalog = SessionCatalog()
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false
    @State private var showExampleSession = false
    @State private var showActionError = false
    @State private var actionErrorText: String?

    private var useAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(LogbookLayout.rowInsets(top: 8, bottom: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if connectivity.pendingAckCount > 0 {
                    Section {
                        SyncStatusIndicator(
                            state: connectivity.syncState,
                            pendingCount: connectivity.pendingAckCount
                        )
                        .listRowInsets(LogbookLayout.rowInsets(top: 0, bottom: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
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
                                "Record a park day on Apple Watch. Or browse the example session."
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
            .alert(
                "Delete Session?",
                isPresented: $showDeleteConfirmation
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
            .alert(
                "Could Not Delete Session",
                isPresented: $showActionError,
                presenting: actionErrorText
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .onAppear {
                connectivity.refreshSyncState()
                catalog.reload(store: connectivity.store)
            }
            .onChange(of: connectivity.sessionsRevision) { _, _ in
                catalog.reload(store: connectivity.store)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Logbook")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.rpplText)
            Text("Park days and rides")
                .font(.subheadline)
                .foregroundStyle(Color.rpplMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalsCard: some View {
        let totals = catalog.totals
        let sessionsValue = catalog.isLoading ? "-" : "\(totals.sessionCount)"
        let distanceValue = catalog.isLoading
            ? "-"
            : LogbookFormatting.distanceKilometers(totals.totalDistanceMeters)
        let maxSpeedValue = catalog.isLoading || totals.topSpeedKmh <= 0
            ? "-"
            : LogbookFormatting.speedKilometersPerHour(totals.topSpeedKmh)

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

            Group {
                if useAccessibilityLayout {
                    VStack(spacing: 12) {
                        totalMetric(value: sessionsValue, label: "Sessions")
                        totalDivider(horizontal: true)
                        totalMetric(value: distanceValue, label: "Distance")
                        totalDivider(horizontal: true)
                        totalMetric(value: maxSpeedValue, label: "Max speed")
                    }
                } else {
                    HStack(spacing: 0) {
                        totalMetric(value: sessionsValue, label: "Sessions")
                        totalDivider(horizontal: false)
                        totalMetric(value: distanceValue, label: "Distance")
                        totalDivider(horizontal: false)
                        totalMetric(value: maxSpeedValue, label: "Max speed")
                    }
                }
            }

            Divider()
                .overlay(Color.rpplFill)

            Text(
                catalog.isLoading
                    ? "—"
                    : LogbookFormatting.totalsFooter(
                        rides: totals.totalRuns,
                        sets: totals.totalSets
                    )
            )
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
        }
        .logbookCardChrome()
    }

    private func totalDivider(horizontal: Bool) -> some View {
        Rectangle()
            .fill(Color.rpplFill)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : 44)
            .frame(maxWidth: horizontal ? .infinity : nil)
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
            let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            actionErrorText = description.isEmpty
                ? String(localized: "Something went wrong while deleting the session.")
                : description
            // Delete confirm alert still dismissing — defer so the error alert is not swallowed.
            Task { @MainActor in
                showActionError = true
            }
            WakeLog.error(.store, "delete session: \(error.localizedDescription)")
        }
    }
}

private struct SessionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: SessionEntry

    private var useAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.cityName ?? "-")
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                    .lineLimit(1)
            }

            Text(sessionMetaText)
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(Color.rpplFill)

            sessionStatsSummary
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .logbookCardChrome()
    }

    private var sessionMetaText: String {
        let date = LogbookFormatting.sessionDate(entry.manifest.startedAt)
        let range = LogbookFormatting.sessionTimeRange(
            start: entry.manifest.startedAt,
            end: entry.manifest.endedAt ?? entry.stats?.endedAt
        )
        return "\(date) · \(range) · \(durationText)"
    }

    private var durationText: String {
        guard let stats = entry.stats else { return "-" }
        return LogbookFormatting.duration(stats.totalDuration)
    }

    private var distanceText: String {
        guard let stats = entry.stats else { return "-" }
        return LogbookFormatting.distanceKilometers(stats.totalDistanceMeters)
    }

    private var ridesText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.rideCount(stats.rideCount)
    }

    private var setsText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.setCount(stats.totalSetCount)
    }

    @ViewBuilder
    private var sessionStatsSummary: some View {
        if useAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                // Display order matches roomy row; keep priority still rides → distance → sets.
                statLabel("water.waves", value: distanceText)
                statLabel("flag.checkered", value: ridesText)
                statLabel("arrow.triangle.2.circlepath", value: setsText)
            }
        } else {
            // Drop lowest-priority stats first when width is tight (sets → distance → rides).
            ViewThatFits(in: .horizontal) {
                statsRow(includeDistance: true, includeSets: true)
                statsRow(includeDistance: true, includeSets: false)
                statsRow(includeDistance: false, includeSets: false)
            }
        }
    }

    private func statsRow(includeDistance: Bool, includeSets: Bool) -> some View {
        HStack(spacing: 12) {
            // Display: distance → rides → sets. Drop order (lowest first): sets → distance.
            if includeDistance {
                statLabel("water.waves", value: distanceText)
            }
            statLabel("flag.checkered", value: ridesText)
            if includeSets {
                statLabel("arrow.triangle.2.circlepath", value: setsText)
            }
        }
    }

    private func statLabel(_ symbol: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LogbookView()
}
