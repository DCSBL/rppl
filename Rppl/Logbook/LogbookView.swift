import StoreKit
import SwiftUI
import RpplCore

struct LogbookView: View {
    @Binding var navigation: LogbookNavigationRequest

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.requestReview) private var requestReview
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var catalog = SessionCatalog()
    @AppStorage(AppSettingsKey.speedTotal) private var speedTotal = SpeedTotal.max
    @AppStorage(AppSettingsKey.countTotal) private var countTotal = CountTotal.sessions
    @AppStorage(AppSettingsKey.distanceTotal) private var distanceTotal = DistanceTotal.distance
    @State private var pendingDeleteSessionId: String?
    @State private var showDeleteConfirmation = false
    @State private var showExampleSession = false
    @State private var showAddSession = false
    @State private var showActionError = false
    @State private var actionErrorText: String?
    @State private var highlightSessionId: String?
    @State private var didOpenSession = false
    @State private var windowWidth: CGFloat = 0
    @State private var selectedSessionId: String?
    /// Collapsed (narrow), the list is the root; opening a session shows the detail on top.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @Environment(\.showAppSettings) private var showAppSettings

    private var useAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var layout: WindowLayout {
        WindowLayout.resolve(width: Double(windowWidth), isAccessibilityTextSize: useAccessibilityLayout)
    }

    var body: some View {
        // Always a split view, also when narrow: there it collapses into one stack, so folding or unfolding
        // keeps the open session (and what was pushed on it). Column widths are the system's: on iPhone Duo
        // it puts the divider on the fold.
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            listContent
        } detail: {
            splitDetail
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .sheet(isPresented: $showAddSession) {
            ManualSessionEditorView(onSaved: flashHighlight)
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
            requestReviewIfPending()
        }
        .onChange(of: catalog.isLoading) { _, loading in
            if !loading { armReviewPrompt() }
        }
        .onChange(of: connectivity.sessionsRevision) { _, _ in
            reloadCatalog()
        }
        .onChange(of: iCloud.acceptedSessionIDs) { _, _ in
            reloadCatalog()
        }
        // Back from a session (narrow) or deselected: flash its row, maybe ask for a review.
        .onChange(of: selectedSessionId) { old, new in
            guard let old, new == nil else { return }
            didOpenSession = true
            flashHighlight(old)
            requestReviewIfPending()
        }
        .onChange(of: catalog.entries.map(\.manifest.sessionId)) { _, ids in
            if let selected = selectedSessionId, !ids.contains(selected) { selectedSessionId = nil }
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

    private var listContent: some View {
        List(selection: $selectedSessionId) {
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

            if catalog.season.showsCharts {
                Section {
                    SeasonCharts(season: catalog.season)
                        .listRowInsets(LogbookLayout.rowInsets(top: 0, bottom: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
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
                            "Record a park day with Apple Watch, or add a session by hand with the + button."
                        )
                    } actions: {
                        VStack(spacing: 12) {
                            Button("Show example session") {
                                showExampleSession = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Color.rpplAccent)

                            Text(
                                "Apple Watch is recommended: it records your sets, laps, speed and route, and brings them here when your iPhone is nearby."
                            )
                            .font(.footnote)
                            .foregroundStyle(Color.rpplMuted)
                            .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(Color.rpplText)
                    .onAppear { ExampleSessionPreload.warmUp() }
                    .listRowInsets(LogbookLayout.rowInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(catalog.entries) { entry in
                        sessionRow(entry)
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
            .contentMargins(.horizontal, layout == .twoPane ? LogbookLayout.wideInset : LogbookLayout.horizontalInset, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .background(RpplBackdrop())
            .navigationTitle("Logbook")
            .navigationSubtitle("Sessions and sets")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Settings above add in the vertical bar of iPhone Duo, settings left of add elsewhere.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape", action: showAppSettings)
                    Button("Add session", systemImage: "plus") { showAddSession = true }
                }
            }
            .tint(Color.rpplAccent)
            .navigationDestination(isPresented: $showExampleSession) {
                LogbookSessionDetailView(source: .bundledExample)
                    .toolbar(.visible, for: .navigationBar)
            }
    }

    /// Selecting the row opens the session: beside the list when wide, pushed when the split view is collapsed.
    private func sessionRow(_ entry: SessionEntry) -> some View {
        let sessionId = entry.manifest.sessionId
        return SessionCard(
            entry: entry,
            isHighlighted: highlightSessionId == sessionId,
            isSelected: layout == .twoPane && selectedSessionId == sessionId,
            showsChevron: layout == .stack
        )
        .tag(sessionId)
    }

    /// The detail column's stack beside the list: the selected session pushed on the placeholder; empty while
    /// collapsed, where the session is the column's root. A path, so picking another session replaces the
    /// pushed one instead of popping it first and losing the new selection; the system back button clears it.
    private var pushedPath: Binding<[String]> {
        Binding(
            get: { horizontalSizeClass == .compact ? [] : (selectedSessionId.map { [$0] } ?? []) },
            set: { selectedSessionId = $0.last }
        )
    }

    /// Detail column. Beside the list: a stack with a placeholder, the selected session pushed on it (the
    /// system's push and back button). Collapsed: the session is the root, so back goes to the list.
    @ViewBuilder
    private var splitDetail: some View {
        if horizontalSizeClass == .compact, let sessionId = selectedSessionId {
            NavigationStack {
                LogbookSessionDetailView(sessionId: sessionId, store: connectivity.store)
                    .embeddedInSplit(layout == .twoPane)
                    .toolbar(.visible, for: .navigationBar)
            }
            .id(sessionId)
        } else {
            NavigationStack(path: pushedPath) {
                ContentUnavailableView("No session selected", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(Color.rpplMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RpplBackdrop())
                    .navigationDestination(for: String.self) { sessionId in
                        LogbookSessionDetailView(sessionId: sessionId, store: connectivity.store)
                            .embeddedInSplit()
                            .toolbar(.visible, for: .navigationBar)
                    }
            }
        }
    }

    private func consumeNavigationRequests() {
        if let sessionId = navigation.openSessionId {
            selectedSessionId = sessionId
            compactColumn = .detail
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

    /// Count good sessions; reaching a milestone only arms the prompt (shown on return to the list).
    private func armReviewPrompt() {
        let goodIDs = catalog.entries.compactMap { entry -> String? in
            guard let stats = entry.stats,
                  ReviewPromptState.isGoodSession(manifest: entry.manifest, stats: stats) else { return nil }
            return entry.manifest.sessionId
        }
        var state = ReviewPromptStore.load()
        if state.record(goodSessionIDs: goodIDs) {
            WakeLog.debug(.ui, "review prompt armed good=\(state.countedSessionIDs.count) milestone=\(state.promptedMilestone)")
        }
        ReviewPromptStore.save(state)
    }

    /// Native review sheet right after the rider comes back from a session to the list.
    private func requestReviewIfPending() {
        guard didOpenSession else { return }
        var state = ReviewPromptStore.load()
        guard state.consumePending() else { return }
        ReviewPromptStore.save(state)
        if AppReleaseChannel.isTestFlight {
            WakeLog.debug(.ui, "review prompt skipped (TestFlight) good=\(state.countedSessionIDs.count)")
            return
        }
        WakeLog.debug(.ui, "review prompt requested good=\(state.countedSessionIDs.count) milestone=\(state.promptedMilestone)")
        #if !DEBUG
        requestReview()
        #endif
    }

    private func reloadCatalog() {
        catalog.reload(
            store: connectivity.store,
            acceptedSessionIDs: iCloud.logbookFilterIDs
        )
    }

    private var totalsCard: some View {
        let season = catalog.season
        let loading = catalog.isLoading
        let countLabel: LocalizedStringKey
        let countValue: Int
        switch countTotal {
        case .sessions:
            countLabel = "Sessions"
            countValue = season.sessionCount
        case .sets:
            countLabel = "Sets"
            countValue = season.totalSets
        case .laps:
            countLabel = "Laps"
            countValue = season.totalLaps
        }
        let sessionsValue = loading ? "-" : "\(countValue)"

        let distanceLabel: LocalizedStringKey
        let distanceValue: String
        switch distanceTotal {
        case .distance:
            distanceLabel = "Distance"
            distanceValue = DistanceFormat.kilometers(season.totalDistanceMeters, fixedFraction: 1)
        case .duration:
            distanceLabel = "Total time"
            distanceValue = DurationFormat.total(season.totalDuration, fractionDigits: 1)
        case .riding:
            distanceLabel = "Total riding time"
            distanceValue = DurationFormat.total(season.totalRidingDuration, fractionDigits: 1)
        }

        let speedLabel: LocalizedStringKey = speedTotal == .max ? "Maximum speed" : "Average speed"
        let speedShortLabel: LocalizedStringKey = speedTotal == .max ? "Max speed" : "Avg speed"
        let speed = speedTotal == .max ? season.topSpeedKmh : season.typicalSpeedKmh
        let speedValue = if let speed, speed > 0 { DistanceFormat.kilometersPerHour(speed) } else { "-" }

        return InfoTile("Total", metric: .riding) {
            Group {
                if useAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        totalMetric(value: sessionsValue, label: countLabel, id: "logbook-total-sessions") {
                            countTotal = countTotal.cycled()
                        }
                        totalDivider(horizontal: true)
                        totalMetric(value: loading ? "-" : distanceValue, label: distanceLabel, id: "logbook-total-distance") {
                            distanceTotal = distanceTotal.cycled()
                        }
                        totalDivider(horizontal: true)
                        totalMetric(value: loading ? "-" : speedValue, label: speedLabel, shortLabel: speedShortLabel, id: "logbook-total-speed") {
                            speedTotal = speedTotal.cycled()
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        totalMetric(value: sessionsValue, label: countLabel, id: "logbook-total-sessions") {
                            countTotal = countTotal.cycled()
                        }
                        totalDivider(horizontal: false)
                        totalMetric(value: loading ? "-" : distanceValue, label: distanceLabel, id: "logbook-total-distance") {
                            distanceTotal = distanceTotal.cycled()
                        }
                        totalDivider(horizontal: false)
                        totalMetric(value: loading ? "-" : speedValue, label: speedLabel, shortLabel: speedShortLabel, id: "logbook-total-speed") {
                            speedTotal = speedTotal.cycled()
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: countTotal)
            .sensoryFeedback(.selection, trigger: speedTotal)
            .sensoryFeedback(.selection, trigger: distanceTotal)
        }
    }

    private func totalDivider(horizontal: Bool) -> some View {
        Rectangle()
            .fill(Color.rpplFill)
            .frame(width: horizontal ? nil : 1, height: horizontal ? 1 : 44)
            .frame(maxWidth: horizontal ? .infinity : nil)
    }

    /// A tap on `action` cycles what the total shows (quiet easter egg, no visual affordance).
    @ViewBuilder
    private func totalMetric(
        value: String,
        label: LocalizedStringKey,
        shortLabel: LocalizedStringKey? = nil,
        id: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        // Full label when it fits on one line, else the abbreviation. Never scaled, so the text size
        // stays the same when a tap swaps the metric.
        let content = VStack(spacing: 4) {
            MetricValue(value, size: .total)
            ViewThatFits(in: .horizontal) {
                if shortLabel != nil { Text(label).lineLimit(1) }
                Text(shortLabel ?? label).lineLimit(2)
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(RpplDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id ?? "")

        if let action {
            Button(action: action) { content.contentShape(.rect) }
                .buttonStyle(.plain)
        } else {
            content
        }
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
        case .mostSets: "square.stack.3d.up.fill"
        case .mostDistance: "map.fill"
        case .topSpeed: "gauge.with.dots.needle.67percent"
        case .laziest: "sofa.fill"
        case .coldest: "thermometer.snowflake"
        case .hottest: "sun.max.fill"
        case .windiest: "wind"
        case .rainiest: "cloud.rain.fill"
        case .iceBath: "snowflake"
        case .earlyBird: "sunrise.fill"
        case .nightOwl: "moon.stars.fill"
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
        case .mostSets: .pink
        case .mostDistance: .teal
        case .topSpeed: .purple
        case .laziest: .gray
        case .coldest: .cyan
        case .hottest: .orange
        case .windiest: .mint
        case .rainiest: .indigo
        case .iceBath: .blue
        case .earlyBird: .yellow
        case .nightOwl: .indigo
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
        case .mostLaps: "arrow.triangle.2.circlepath"
        case .comeback: "arrow.counterclockwise"
        case .backToBack: "forward.fill"
        }
    }

    var badgeTint: Color {
        switch self {
        case .longest: .orange
        case .longestTime: .blue
        case .shortest: .gray
        case .fastest: .purple
        case .mostLaps: .pink
        case .comeback: .green
        case .backToBack: .teal
        }
    }
}

private struct SessionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: SessionEntry
    var isHighlighted = false
    /// Two-pane: the row whose session is open on the right.
    var isSelected = false
    var showsChevron = true

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

                        if isManual { ManualBadge() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !entry.highlights.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.highlights, id: \.rawValue) { highlight in
                            HighlightChip(highlight)
                        }
                    }
                }

                Text(sessionMetaText)
                    .font(.footnote)
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

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.rpplMuted)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpplTileChrome()
        .background(
            RoundedRectangle(cornerRadius: RpplDesign.tileCornerRadius, style: .continuous)
                .fill(isHighlighted || isSelected ? Color.rpplAccent.opacity(isSelected ? 0.2 : 0.12) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RpplDesign.tileCornerRadius, style: .continuous)
                .stroke(Color.rpplAccent, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        // One element that opens the session, as the NavigationLink row was; a selection row alone reads
        // as loose texts to VoiceOver and to UI tests.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .rpplAnimation(.easeOut(duration: 0.3), value: isHighlighted)
    }

    private var activityIcon: some View {
        WakeboardIcon()
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

    private var isManual: Bool { entry.manifest.manual != nil }

    /// A manual session without a cable length has no distance to show.
    private var showsDistance: Bool { !isManual || (entry.stats?.totalDistanceMeters ?? 0) > 0 }

    private var distanceText: String {
        guard let stats = entry.stats else { return "-" }
        return isManual
            ? DistanceFormat.approximateKilometers(stats.totalDistanceMeters)
            : DistanceFormat.kilometers(stats.totalDistanceMeters)
    }

    private var setsText: String {
        guard let stats = entry.stats else { return "—" }
        return stats.knownSetCount.map(LogbookFormatting.setCount) ?? LogbookFormatting.unknownCount
    }

    private var lapsText: String {
        guard let stats = entry.stats else { return "—" }
        return stats.knownLapCount.map(LogbookFormatting.lapCount) ?? LogbookFormatting.unknownCount
    }

    @ViewBuilder
    private var sessionStatsSummary: some View {
        if useAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                if showsDistance { StatChip(metric: .distance, value: distanceText) }
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
            if includeDistance, showsDistance {
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
