import SwiftUI
import RpplCore

private struct SessionDetailRoute: Identifiable, Hashable {
    let id: String
}

struct LogbookView: View {
    @Binding var navigation: LogbookNavigationRequest

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var catalog = SessionCatalog()
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false
    @State private var showExampleSession = false
    @State private var showActionError = false
    @State private var actionErrorText: String?
    @State private var detailRoute: SessionDetailRoute?
    @State private var highlightSessionId: String?

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
                        .rpplTileChrome()
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
                                .onDisappear {
                                    flashHighlight(entry.manifest.sessionId)
                                }
                            } label: {
                                SessionCard(
                                    entry: entry,
                                    isHighlighted: highlightSessionId == entry.manifest.sessionId
                                )
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
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
            .background(RpplBackdrop())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .tint(Color.rpplAccent)
            .navigationDestination(isPresented: $showExampleSession) {
                LogbookSessionDetailView(source: .bundledExample)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(item: $detailRoute) { route in
                LogbookSessionDetailView(sessionId: route.id, store: connectivity.store)
                    .onDisappear {
                        flashHighlight(route.id)
                    }
            }
            .alert(
                "Delete session?",
                isPresented: $showDeleteConfirmation
            ) {
                if iCloud.isSyncEnabled, iCloud.isICloudAvailable {
                    Button("Delete from this iPhone", role: .destructive) {
                        if let sessionId = pendingDeleteSessionId {
                            hideSessionFromLogbook(sessionId)
                        }
                        pendingDeleteSessionId = nil
                    }
                    Button("Delete from iPhone and iCloud", role: .destructive) {
                        if let sessionId = pendingDeleteSessionId {
                            deleteSessionPermanently(sessionId)
                        }
                        pendingDeleteSessionId = nil
                    }
                } else {
                    Button("Delete from Rppl", role: .destructive) {
                        if let sessionId = pendingDeleteSessionId {
                            deleteSessionLocally(sessionId)
                        }
                        pendingDeleteSessionId = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteSessionId = nil
                }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .alert(
                "Could not delete session",
                isPresented: $showActionError,
                presenting: actionErrorText
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .onAppear {
                connectivity.refreshSyncState()
                reloadCatalog()
                consumeNavigationRequests()
            }
            .onChange(of: connectivity.sessionsRevision) { _, _ in
                reloadCatalog()
            }
            .onChange(of: iCloud.acceptedSessionIDs) { _, _ in
                reloadCatalog()
            }
            .onChange(of: navigation.openSessionId) { _, _ in
                consumeNavigationRequests()
            }
            .onChange(of: navigation.highlightSessionId) { _, sessionId in
                if let sessionId {
                    flashHighlight(sessionId)
                    navigation.highlightSessionId = nil
                }
            }
        }
    }

    private func consumeNavigationRequests() {
        if let sessionId = navigation.openSessionId {
            detailRoute = SessionDetailRoute(id: sessionId)
            navigation.openSessionId = nil
            flashHighlight(sessionId)
        }
        if let sessionId = navigation.highlightSessionId {
            flashHighlight(sessionId)
            navigation.highlightSessionId = nil
        }
    }

    private func flashHighlight(_ sessionId: String) {
        highlightSessionId = sessionId
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if highlightSessionId == sessionId {
                highlightSessionId = nil
            }
        }
    }

    private func reloadCatalog() {
        catalog.reload(
            store: connectivity.store,
            acceptedSessionIDs: iCloud.logbookFilterIDs
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Logbook")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.rpplText)
            Text("Sessions and sets")
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

        return InfoTile("Total", metric: .riding) {
            Group {
                if useAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 12) {
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
                        sets: totals.totalSets,
                        laps: totals.totalLaps
                    )
            )
            .font(.caption)
            .foregroundStyle(RpplDesign.secondaryText)
        }
    }

    private func totalDivider(horizontal: Bool) -> some View {
        Rectangle()
            .fill(Color.rpplFill)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : 44)
            .frame(maxWidth: horizontal ? .infinity : nil)
    }

    private func totalMetric(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            MetricValue(value, size: .medium)
            Text(label)
                .font(.caption)
                .foregroundStyle(RpplDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

    private var deleteConfirmationMessage: String {
        if iCloud.isSyncEnabled, iCloud.isICloudAvailable {
            return String(
                localized:
                    "Delete from This iPhone hides the session in Rppl here. Delete from iPhone and iCloud permanently removes it from all devices. This cannot be undone."
            )
        }
        return String(
            localized:
                "Permanently removes this session from Rppl on this iPhone. This cannot be undone."
        )
    }

    private func hideSessionFromLogbook(_ sessionId: String) {
        WakeLog.debug(.ui, "confirm hide \(sessionId.prefix(8))…")
        iCloud.hideSessionFromLogbook(sessionId)
        SessionCityResolver.shared.invalidate(sessionId: sessionId)
        reloadCatalog()
    }

    private func deleteSessionPermanently(_ sessionId: String) {
        WakeLog.debug(.ui, "confirm permanent delete \(sessionId.prefix(8))…")
        Task {
            do {
                try await iCloud.deleteSessionPermanently(sessionId)
                SessionCityResolver.shared.invalidate(sessionId: sessionId)
                PhoneWatchViewSync.pushViewDelete(sessionId: sessionId)
                WakeLog.debug(.store, "deleted session \(sessionId.prefix(8))…")
                reloadCatalog()
            } catch {
                presentDeleteError(error)
            }
        }
    }

    private func deleteSessionLocally(_ sessionId: String) {
        WakeLog.debug(.ui, "confirm local delete \(sessionId.prefix(8))…")
        do {
            try connectivity.store.deleteSession(sessionId: sessionId)
            SessionCityResolver.shared.invalidate(sessionId: sessionId)
            PhoneWatchViewSync.pushViewDelete(sessionId: sessionId)
            WakeLog.debug(.store, "deleted session \(sessionId.prefix(8))…")
            reloadCatalog()
        } catch {
            presentDeleteError(error)
        }
    }

    private func presentDeleteError(_ error: Error) {
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

extension SessionHighlight {
    var badgeIcon: String {
        switch self {
        case .longest: "clock.fill"
        case .mostWaterTime: "water.waves"
        case .mostLaps: "arrow.triangle.2.circlepath"
        case .highestRidePercentage: "chart.pie.fill"
        case .mostCalories: "flame.fill"
        case .longestSetEver: "ruler"
        }
    }

    var badgeTint: Color {
        switch self {
        case .longest: .orange
        case .mostWaterTime: .blue
        case .mostLaps: .purple
        case .highestRidePercentage: .green
        case .mostCalories: .red
        case .longestSetEver: .yellow
        }
    }
}

extension SetHighlight {
    var badgeIcon: String {
        switch self {
        case .longest: "ruler"
        case .longestTime: "clock.fill"
        case .shortest: "arrow.down.to.line"
        case .fastest: "bolt.fill"
        }
    }

    var badgeTint: Color {
        switch self {
        case .longest: .orange
        case .longestTime: .blue
        case .shortest: .gray
        case .fastest: .purple
        }
    }
}

private struct SessionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: SessionEntry
    var isHighlighted = false

    private var useAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    activityIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ActivityCodes.localizedTitle(for: entry.manifest.activityCode))
                            .foregroundStyle(Color.rpplText)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        // Park name wraps instead of truncating: it is how riders tell sessions apart.
                        Label {
                            Text(entry.cityName ?? "-")
                        } icon: {
                            Image(systemName: MetricKind.park.systemImage)
                                .foregroundStyle(MetricKind.park.tint)
                        }
                        .font(.subheadline)
                        .foregroundStyle(RpplDesign.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !entry.highlights.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.highlights, id: \.rawValue) { highlight in
                            ParkChip(
                                text: LogbookFormatting.sessionHighlightLabel(highlight),
                                systemImage: highlight.badgeIcon,
                                tint: highlight.badgeTint,
                                fill: highlight.badgeTint.opacity(0.14)
                            )
                        }
                    }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.rpplMuted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpplTileChrome()
        .background(
            RoundedRectangle(cornerRadius: RpplDesign.tileCornerRadius, style: .continuous)
                .fill(isHighlighted ? Color.rpplAccent.opacity(0.12) : Color.clear)
        )
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
    }

    private var activityIcon: some View {
        MDIIconView(icon: .skiWater)
            .foregroundStyle(MetricKind.riding.tint)
            .frame(width: 20, height: 20)
            .frame(width: 36, height: 36)
            .background(
                MetricKind.riding.tint.opacity(0.16),
                in: .rect(cornerRadius: 10, style: .continuous)
            )
            .accessibilityHidden(true)
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

    private var setsText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.setCount(stats.setCount)
    }

    private var lapsText: String {
        guard let stats = entry.stats else { return "—" }
        return LogbookFormatting.lapCount(stats.totalLapCount)
    }

    @ViewBuilder
    private var sessionStatsSummary: some View {
        if useAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                StatChip(metric: .distance, value: distanceText)
                StatChip(metric: .sets, value: setsText)
                StatChip(metric: .laps, value: lapsText)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                statsRow(includeDistance: true, includeLaps: true)
                statsRow(includeDistance: true, includeLaps: false)
                statsRow(includeDistance: false, includeLaps: false)
            }
        }
    }

    private func statsRow(includeDistance: Bool, includeLaps: Bool) -> some View {
        HStack(spacing: 16) {
            if includeDistance {
                StatChip(metric: .distance, value: distanceText)
            }
            StatChip(metric: .sets, value: setsText)
            if includeLaps {
                StatChip(metric: .laps, value: lapsText)
            }
        }
    }
}

#Preview {
    LogbookView(navigation: .constant(LogbookNavigationRequest()))
}
