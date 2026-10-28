import MapKit
import RpplCore
import SwiftUI
import WidgetKit

struct ParksView: View {
    /// Park id from a widget tap; opened once, then cleared.
    @Binding var openParkID: String?
    /// Top parks widget tap: nearby order with the Favourites filter on; cleared once applied.
    @Binding var openFavorites: Bool
    @State private var store = ParkStore.shared
    @State private var showEditor = false
    @State private var drafts = ParkDraftsController.shared
    @State private var resumingDraft: ParkEditDraft?
    @State private var draftToDelete: ParkEditDraft?
    @AppStorage(AppSettingsKey.parkEditorEnabled) private var editorEnabled = true
    @State private var sort: ParkListSort = .distance
    @State private var favorites = ParkFavorites.shared
    @State private var location = ParksLocationProvider()
    @State private var catalog = SessionCatalog()
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var showMap = false
    @State private var windowWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSearch = false
    @State private var searchText = ""
    /// Bumped when the search field is submitted on the map: it then looks the text up as a place.
    @State private var placeSearchToken = 0
    @AppStorage(AppSettingsKey.parkWaterTemperatureEnabled) private var waterTemperatureEnabled = false
    @AppStorage(AppSettingsKey.parkDataUpdatesEnabled) private var parkDataUpdatesEnabled = false
    @AppStorage(AppSettingsKey.didAskParkDataConsent) private var didAskParkDataConsent = false
    @State private var updates = ParkDataUpdateController.shared
    @State private var showParkDataConsent = false
    @State private var openFilterDate: Date?
    @State private var cableFilter: Set<ParkCableDirection> = []
    @State private var favoritesOnly = false
    @State private var withoutCableGeoOnly = false
    @AppStorage(AppSettingsKey.debugParkNoCableGeoFilter) private var noCableGeoFilterEnabled = false
    @State private var headerHeight: CGFloat = 0
    /// Accessibility sizes: the "Open on a day" sheet, opened from the Filters menu.
    @State private var showOpenDateSheet = false
    /// How far the list is pulled down past its resting position, for the pull-to-refresh indicator.
    @State private var pullDistance: CGFloat = 0
    @State private var mapPosition: MapCameraPosition = .region(ParksMapDefaults.opening())
    @State private var mapPendingRecenter = false
    /// Two-pane only: the park shown on the right instead of the map.
    @State private var selectedParkID: String?
    /// Collapsed (narrow), the list is the root; opening a park shows the detail on top.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    /// Bumped by `select(_:)` when another park is picked while one is open beside the list, so the detail
    /// stack is rebuilt for it: replacing the item of a pushed destination makes SwiftUI report a pop, which
    /// cleared the new selection.
    @State private var detailStackToken = 0
    /// The park `select(_:)` is about to push on a rebuilt detail stack.
    @State private var switchingToPark: String?
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var mapUsesSatellite = false
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.showAppSettings) private var showAppSettings

    private var parks: [Park] { store.entries.map(\.park).filter(\.isListed) }

    /// At accessibility sizes the sort picker and the filter pills leave no room for the list under the
    /// large title, so sort and filters become menus in the navigation bar.
    private var useAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visits: [String: Int] {
        let centers = catalog.entries.compactMap(\.center)
        return ParkListing.visitCounts(parks: parks, sessionCenters: centers)
    }

    private var filters: ParkFilters {
        ParkFilters(
            openOnDate: openFilterDate,
            cableDirections: cableFilter,
            favoritesOnly: favoritesOnly,
            withoutCableGeoOnly: noCableGeoFilterEnabled && withoutCableGeoOnly
        )
    }

    /// The distance-sorted list is on screen: the one place this tab needs the person's location.
    private var layout: WindowLayout {
        WindowLayout.resolve(
            width: Double(windowWidth),
            isAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize,
            isCompactWidthClass: horizontalSizeClass == .compact
        )
    }

    /// The map replaces the list only while the split view is collapsed into one stack; otherwise it shows
    /// beside the list. Follows the size class, not the width, so the column never swaps mid-fold.
    private var showsMapInList: Bool {
        WindowLayout.sidebarHostsMap(wantsMap: showMap, isCompactWidthClass: horizontalSizeClass == .compact)
    }

    /// The park open in the detail column (pushed when the split view is collapsed).
    private var selectedPark: Park? {
        selectedParkID.flatMap { store.entry(id: $0)?.park }
    }

    private var showsNearby: Bool {
        !showsMapInList && !isSearching && sort == .distance
    }

    private func filteredParks(_ parks: [Park]) -> [Park] {
        ParkListing.filtered(parks, favorites: favorites.ids, filters: filters)
    }

    /// While searching, order is relevance (best hit first); otherwise the chosen sort.
    private func sortedParks(_ filtered: [Park], visitCounts: [String: Int]) -> [Park] {
        if isSearching {
            return ParkSearch.rank(filtered, query: searchText)
        }
        return ParkListing.sorted(
            filtered,
            visits: visitCounts,
            userLocation: location.coordinate,
            sort: sort
        )
    }

    private func clearFilters() {
        withRpplAnimation(.snappy(duration: 0.2)) {
            openFilterDate = nil
            cableFilter = []
            favoritesOnly = false
            withoutCableGeoOnly = false
        }
    }

    /// "Reasonable distance" for the here/reset button: close enough to be useful, wide enough to
    /// see nearby landmarks around the park.
    private static let recenterCameraDistance: CLLocationDistance = 5_000

    /// Jumps the map to the user's location at a reasonable distance; requests a fresh fix first if
    /// needed. Tapping the button is what asks for location access: opening the map never does.
    private func recenterOnUser() {
        if let coordinate = location.coordinate {
            moveMap(to: coordinate)
        } else {
            mapPendingRecenter = true
            location.requestAccess()
        }
    }

    /// Asks for location access only while the Nearby list is showing; every other view of this
    /// tab just reads a fix when access was already granted.
    private func refreshLocation() {
        if showsNearby {
            location.requestAccess()
        } else {
            location.refresh()
        }
    }

    private func moveMap(to coordinate: ParkCoordinate) {
        let center = CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
        withRpplAnimation {
            mapPosition = .camera(MapCamera(centerCoordinate: center, distance: Self.recenterCameraDistance))
        }
    }

    private func toggleSearch() {
        withRpplAnimation(.snappy(duration: 0.25)) {
            showSearch.toggle()
            if !showSearch { searchText = "" }
        }
        searchFieldFocused = showSearch
    }

    private func reloadDrafts() { drafts.reload() }

    /// Pull distance (pt) that counts as a refresh when the finger lets go.
    private static let pullThreshold: CGFloat = 70
    private static let pullIndicatorHeight: CGFloat = 64

    private var showsRefreshIndicator: Bool {
        !showsMapInList && parkDataUpdatesEnabled && updates.errorMessage == nil && updates.isRefreshing
    }

    /// A pull drags the large title down with the list; the header goes along instead of letting the
    /// title slide under it. While refreshing it stays lower, making room for the indicator above it.
    private var headerShift: CGFloat {
        guard !showsMapInList else { return 0 }
        return pullDistance + (showsRefreshIndicator ? Self.pullIndicatorHeight : 0)
    }

    /// Pull to refresh. Off and never asked: ask first. Off and already answered: nothing to do.
    private func pullToRefresh() async {
        guard parkDataUpdatesEnabled else {
            if !didAskParkDataConsent { showParkDataConsent = true }
            return
        }
        await updates.manualRefresh()
    }

    private func answerParkDataConsent(allow: Bool) {
        didAskParkDataConsent = true
        guard allow else { return }
        parkDataUpdatesEnabled = true
        Task { await updates.manualRefresh() }
    }

    private func showRequestedFavorites() {
        guard openFavorites else { return }
        openFavorites = false
        selectedParkID = nil
        showMap = false
        showSearch = false
        searchText = ""
        openFilterDate = nil
        cableFilter = []
        sort = .distance
        favoritesOnly = true
    }

    private func openRequestedPark() {
        guard let id = openParkID else { return }
        if store.entries.isEmpty { store.reload() }
        openParkID = nil
        guard store.entry(id: id) != nil else { return }
        select(id)
        compactColumn = .detail
    }

    /// Unfinished parks, on top of the list until they are saved or deleted.
    @ViewBuilder
    private var draftRows: some View {
        ForEach(drafts.drafts) { draft in
            ParkDraftCard(draft: draft) { resumingDraft = draft }
                .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { draftToDelete = draft } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    private enum SortChoice: Hashable {
        case sort(ParkListSort)
        case map
    }

    /// The map is a destination, not a sort: picking it opens the cover and keeps the previous sort
    /// selected. Picking "Nearby"/"Most visited" while the map is open closes it back to the list.
    private var sortChoice: Binding<SortChoice> {
        Binding(
            get: { showsMapInList ? .map : .sort(sort) },
            set: {
                switch $0 {
                case .sort(let value):
                    sort = value
                    showMap = false
                case .map:
                    showMap = true
                }
            }
        )
    }

    var body: some View {
        // Computed once per body evaluation instead of re-filtering/sorting on every access below.
        let allParks = parks
        let visitCounts = visits
        let visibleParks = filteredParks(allParks)
        let orderedParks = sortedParks(visibleParks, visitCounts: visitCounts)

        // Always a split view, also when narrow: there it collapses into one stack, so folding or unfolding
        // keeps the open park (and what was pushed on it). Column widths are the system's: on iPhone Duo it
        // puts the divider on the fold.
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            listColumn(allParks: allParks, visitCounts: visitCounts, visibleParks: visibleParks, orderedParks: orderedParks)
        } detail: {
            detailColumn(visibleParks: visibleParks)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .tint(Color.rpplAccent)
        // Collapsed, a pick from the list or the map has to bring the detail on top itself: a tap on a pin
        // sets the selection from outside the list, and a park that is still selected after back would make
        // the next tap on its row a no-op. So back clears the selection.
        .onChange(of: selectedParkID) { _, id in
            guard id != nil, horizontalSizeClass == .compact else { return }
            withRpplAnimation { compactColumn = .detail }
        }
        .onChange(of: compactColumn) { _, column in
            guard column == .sidebar, horizontalSizeClass == .compact else { return }
            selectedParkID = nil
        }
        .sheet(isPresented: $showEditor, onDismiss: reloadDrafts) {
            ParkEditorView(original: nil)
        }
        .sheet(item: $resumingDraft, onDismiss: reloadDrafts) { draft in
            ParkEditorView(original: draft.editsParkID.flatMap { store.entry(id: $0)?.park }, resuming: draft)
        }
        .alert(
            "Delete this draft?",
            isPresented: Binding(get: { draftToDelete != nil }, set: { if !$0 { draftToDelete = nil } }),
            presenting: draftToDelete
        ) { draft in
            Button("Delete draft", role: .destructive) { drafts.delete(draft) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The unsaved park and everything you filled in will be gone.")
        }
        .alert("Update park data?", isPresented: $showParkDataConsent) {
            Button("Turn on") { answerParkDataConsent(allow: true) }
            Button("Not now", role: .cancel) { answerParkDataConsent(allow: false) }
        } message: {
            Text("Rppl fetches new park info from GitHub, a website where developers share files. GitHub can see your IP address; nothing else is sent. You can change this in Info.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: updates.startedCount)
        .sensoryFeedback(.success, trigger: updates.successCount)
        .sensoryFeedback(.error, trigger: updates.failureCount)
        .task {
            drafts.reload()
            store.reload()
            await updates.refreshIfDue()
            catalog.reload(store: connectivity.store, acceptedSessionIDs: iCloud.logbookFilterIDs)
        }
        .onChange(of: connectivity.sessionsRevision) { _, _ in
            catalog.reload(store: connectivity.store, acceptedSessionIDs: iCloud.logbookFilterIDs)
        }
        .onChange(of: waterTemperatureEnabled, initial: true) { _, enabled in
            if ParkWidgetWater.setEnabled(enabled) { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: visits, initial: true) { _, counts in
            favorites.publishToWidgets()
            // shortcut: an empty logbook never clears old counts (also guards the first pass before the catalog loads).
            guard !catalog.entries.isEmpty else { return }
            if ParkWidgetSnapshotStore.update({ $0.visits = counts }) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .onChange(of: openParkID, initial: true) { _, _ in openRequestedPark() }
        .onChange(of: openFavorites, initial: true) { _, _ in showRequestedFavorites() }
        // Refresh only on appear / foreground return — a live-updating fix would reorder the
        // Nearby list out from under the user while they're scrolling or tapping a park.
        .onAppear { refreshLocation() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshLocation()
            Task { await updates.refreshIfDue() }
        }
        .onChange(of: showsNearby) { _, shows in
            if shows { location.requestAccess() }
        }
        .onChange(of: location.coordinate) { _, coordinate in
            guard mapPendingRecenter, let coordinate else { return }
            mapPendingRecenter = false
            moveMap(to: coordinate)
        }
        // "Don't Allow" on the recenter prompt: drop the pending jump so a later fix (after the
        // person enables location in Settings) doesn't move the map out from under them.
        .onChange(of: location.availability) { _, availability in
            guard availability == .denied || availability == .servicesDisabled else { return }
            mapPendingRecenter = false
        }
    }

    /// The list with its pinned sort and filter header; in a narrow window "View on map" swaps the list for the map.
    @ViewBuilder
    private func listColumn(allParks: [Park], visitCounts: [String: Int], visibleParks: [Park], orderedParks: [Park]) -> some View {
        ZStack(alignment: .top) {
            RpplBackdrop()

            // The map is full height, bleeding under the translucent header bar.
            if showsMapInList {
                ParksMapView(
                    parks: visibleParks,
                    location: location,
                    topInset: headerHeight,
                    position: $mapPosition,
                    placeQuery: searchText,
                    placeSearchToken: placeSearchToken,
                    onSelectPark: { select($0.id) }
                )
                    .ignoresSafeArea()
            } else {
                List(selection: parkSelection) {
                    if editorEnabled, !isSearching {
                        draftRows
                    }
                    if !isSearching, sort == .distance, location.availability != .available {
                        ParksLocationNeededCard(
                            availability: location.availability,
                            onRequestAccess: { location.requestAccess() },
                            onOpenSettings: {
                                if let url = ParkNavigation.appSettingsURL { openURL(url) }
                            }
                        )
                        .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if allParks.isEmpty {
                        Text("No parks yet")
                            .foregroundStyle(Color.rpplMuted)
                            .listRowBackground(Color.clear)
                    } else if filters.isActive, visibleParks.isEmpty {
                        ParksNoMatchCard(onClear: clearFilters)
                            .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else if orderedParks.isEmpty {
                        Text("No parks found")
                            .foregroundStyle(Color.rpplMuted)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(orderedParks) { park in
                            ParkCard(
                                park: park,
                                visitCount: visitCounts[park.id] ?? 0,
                                distanceMeters: location.coordinate.map { park.location.meters(to: $0) },
                                isFavorite: favorites.contains(park.id),
                                entry: store.entry(id: park.id),
                                filterDate: openFilterDate,
                                isSelected: layout == .twoPane && selectedParkID == park.id
                            )
                            .tag(park.id)
                            .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    if !isSearching, parkDataUpdatesEnabled {
                        ParkDataStatusLine(controller: updates)
                            .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                // Own pull-to-refresh: the system spinner sits at the top of the scroll
                // content, behind the pinned header, and only shows after a long pull.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, pull in
                    pullDistance = pull
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    guard oldPhase == .interacting, newPhase != .interacting,
                          pullDistance >= Self.pullThreshold else { return }
                    Task { await pullToRefresh() }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, LogbookLayout.horizontalInset, for: .scrollContent)
                .contentMargins(
                    .top,
                    8 + (showsRefreshIndicator ? Self.pullIndicatorHeight : 0),
                    for: .scrollContent
                )
            }

            // The error sits right below the pinned header.
            if !showsMapInList, let message = updates.errorMessage {
                ParkDataErrorBanner(message: message)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            filterHeader(hasParks: !allParks.isEmpty)
                // While refreshing, the indicator takes the place the header moved away from.
                .overlay(alignment: .top) {
                    if showsRefreshIndicator {
                        ParkDataPullIndicator(controller: updates, progress: 1)
                            .frame(height: Self.pullIndicatorHeight)
                            .offset(y: -Self.pullIndicatorHeight)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .offset(y: headerShift)
                .animation(.snappy(duration: 0.25), value: showsRefreshIndicator)
        }
        .navigationTitle("Parks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { listToolbar(hasParks: !allParks.isEmpty) }
    }

    /// Sort picker (or the search field) and filters, in a bar under the navigation bar: the list scrolls under it
    /// with the system's edge effect, and the large title collapses as with any list.
    private func filterHeader(hasParks: Bool) -> some View {
        filterHeaderContent(hasParks: hasParks)
    }

    private func filterHeaderContent(hasParks: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSearch {
                ParkSearchField(
                    text: $searchText,
                    prompt: showsMapInList ? "Search places" : "Search parks",
                    isFocused: $searchFieldFocused,
                    onSubmit: { if showsMapInList { placeSearchToken += 1 } }
                )
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if useAccessibilityLayout {
                // Two icon-only menus instead of the segments and pills: a short header, and nothing
                // added to the navigation bar, where more buttons squeeze the title out in landscape.
                HStack(spacing: 12) {
                    sortMenu
                    if hasParks { filterMenu }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                sortPicker.pickerStyle(.segmented)
            }
            if hasParks, !useAccessibilityLayout {
                ParksFilterBar(
                    openDate: $openFilterDate,
                    cableDirections: $cableFilter,
                    favoritesOnly: $favoritesOnly,
                    withoutCableGeoOnly: noCableGeoFilterEnabled ? $withoutCableGeoOnly : nil
                )
            }
        }
        .padding(.horizontal, LogbookLayout.horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 8)
        // Over the list the bar's own scroll edge effect is the background. Over the map: `.regularMaterial`
        // (not `.ultraThinMaterial`), enough opacity to keep the text and pills legible on any imagery.
        .background(showsMapInList ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
        .onGeometryChange(
            for: CGFloat.self,
            of: { $0.size.height },
            action: { headerHeight = $0 }
        )
    }

    /// Opens a park, or closes it with nil. Use this rather than setting `selectedParkID`, so that
    /// switching parks beside the list works: the detail stack is rebuilt (`detailStackToken`) empty and the
    /// new park is pushed on it once it exists. A stack created with a park already pushed reported a pop
    /// of it straight away, which closed it again.
    private func select(_ id: String?) {
        WakeLog.debug(.ui, "select park \(id ?? "nil") (was \(selectedParkID ?? "nil"))")
        guard let id, let current = selectedParkID, id != current, horizontalSizeClass != .compact else {
            switchingToPark = nil
            selectedParkID = id
            return
        }
        switchingToPark = id
        detailStackToken += 1
        selectedParkID = nil
        DispatchQueue.main.async {
            guard switchingToPark == id else { return }
            switchingToPark = nil
            selectedParkID = id
        }
    }

    /// The list's selection, through `select(_:)`.
    private var parkSelection: Binding<String?> {
        Binding(get: { switchingToPark ?? selectedParkID }, set: { select($0) })
    }

    /// Park pushed on the detail column's stack beside the list; nil while collapsed, where the park is the
    /// column's root. The system back button clears the selection.
    /// A stack replaced by `select(_:)` reports a pop as it goes, so only a pop of the park that is still
    /// selected clears the selection.
    private var pushedPark: Binding<Park?> {
        let shown = selectedParkID
        return Binding(
            get: { horizontalSizeClass == .compact ? nil : selectedPark },
            set: { item in
                WakeLog.debug(.ui, "pushed park set \(item == nil ? "nil" : "item"), shown \(shown ?? "nil"), selected \(selectedParkID ?? "nil")")
                if item == nil, selectedParkID == shown { selectedParkID = nil }
            }
        )
    }

    /// Right side. Beside the list: a stack with the map of the listed parks, the selected park pushed on it
    /// (the system's push and back button). Collapsed: the park is the root, so back goes to the list.
    @ViewBuilder
    private func detailColumn(visibleParks: [Park]) -> some View {
        if horizontalSizeClass == .compact, let park = selectedPark {
            NavigationStack {
                ParkDetailContainer(park: park, plannedDate: openFilterDate)
            }
            .id(park.id)
        } else {
            NavigationStack {
                ParksMapView(
                    parks: visibleParks,
                    location: location,
                    position: $mapPosition,
                    onSelectPark: { select($0.id) }
                )
                .mapScreen(usesSatellite: $mapUsesSatellite, locate: recenterOnUser)
                .navigationDestination(item: pushedPark) { park in
                    ParkDetailContainer(park: park, plannedDate: openFilterDate, isBesideList: true)
                }
            }
            .id(detailStackToken)
            // Beside the list the detail swaps in place, as in any split view; only collapsed does it slide in.
            .transaction { $0.disablesAnimations = true }
        }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: sortChoice) {
            Text("Nearby").tag(SortChoice.sort(.distance))
            Text("Most visited").tag(SortChoice.sort(.visits))
            if layout == .stack {
                Text("View on map").tag(SortChoice.map)
            }
        }
    }

    /// Accessibility sizes: the sort picker as a menu button.
    private var sortMenu: some View {
        Menu {
            sortPicker
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// Accessibility sizes: the filter pills as one menu button; the icon fills while a filter is on.
    private var filterMenu: some View {
        Menu {
            Toggle("Open today", systemImage: "clock", isOn: Binding(
                get: { openFilterDate.map { Calendar.current.isDateInToday($0) } ?? false },
                set: { openFilterDate = $0 ? AppClock.now : nil }
            ))
            Button("Open on a day…", systemImage: "calendar") { showOpenDateSheet = true }
            Menu {
                ForEach(ParksFilterBar.cableChoices, id: \.self) { direction in
                    Toggle(ParksFilterBar.label(for: direction), isOn: Binding(
                        get: { cableFilter.contains(direction) },
                        set: { if $0 { cableFilter.insert(direction) } else { cableFilter.remove(direction) } }
                    ))
                }
            } label: {
                Label("Cable", systemImage: "arrow.triangle.2.circlepath")
            }
            Toggle("Favourites", systemImage: "star.fill", isOn: $favoritesOnly)
            if noCableGeoFilterEnabled {
                Toggle("No cable geo", systemImage: "ladybug", isOn: $withoutCableGeoOnly)
            }
            if filters.isActive {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive, action: clearFilters)
            }
        } label: {
            Label(
                "Filters",
                systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .sheet(isPresented: $showOpenDateSheet) {
            ParksOpenDatePicker(date: $openFilterDate)
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        if showSearch {
            Button("Close search", systemImage: "xmark", action: toggleSearch)
        } else {
            Button("Search parks", systemImage: "magnifyingglass", action: toggleSearch)
        }
    }

    /// Settings above add, like the Logbook; search on top. On the map: search, then the map buttons.
    @ToolbarContentBuilder
    private func listToolbar(hasParks: Bool) -> some ToolbarContent {
        if showsMapInList {
            // Search first, as on the list; it opens the same field in the header.
            ToolbarItemGroup(placement: .topBarTrailing) {
                searchButton
            }
            MapScreenToolbar(usesSatellite: $mapUsesSatellite, locate: recenterOnUser)
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasParks {
                    searchButton
                }
                Button("Settings", systemImage: "gearshape", action: showAppSettings)
                if editorEnabled {
                    Button("Add park", systemImage: "plus") { showEditor = true }
                }
            }
        }
    }

}

/// Filter pills row: Open (datepicker), Cable (multi-pick), Favourites only (toggle).
private struct ParksFilterBar: View {
    @Binding var openDate: Date?
    @Binding var cableDirections: Set<ParkCableDirection>
    @Binding var favoritesOnly: Bool
    /// Debug filter; nil hides the pill.
    var withoutCableGeoOnly: Binding<Bool>?
    @State private var showOpenPicker = false

    static let cableChoices: [ParkCableDirection] = [.clockwise, .counterClockwise, .twoPointZero]

    private var openLabel: String {
        guard let openDate else { return String(localized: "Open") }
        if Calendar.current.isDateInToday(openDate) { return String(localized: "Open today") }
        return openDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var cableLabel: String {
        guard !cableDirections.isEmpty else { return String(localized: "Cable") }
        return Self.cableChoices
            .filter { cableDirections.contains($0) }
            .map { Self.label(for: $0) }
            .joined(separator: ", ")
    }

    static func label(for direction: ParkCableDirection) -> String {
        switch direction {
        case .clockwise: String(localized: "CW")
        case .counterClockwise: String(localized: "CCW")
        case .twoPointZero: String(localized: "2.0")
        default: direction.rawValue.uppercased()
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showOpenPicker = true } label: {
                    ParksFilterPillLabel(title: openLabel, isActive: openDate != nil, showsChevron: true)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOpenPicker) {
                    ParksOpenDatePicker(date: $openDate)
                }

                Menu {
                    ForEach(Self.cableChoices, id: \.self) { direction in
                        Button {
                            if cableDirections.contains(direction) {
                                cableDirections.remove(direction)
                            } else {
                                cableDirections.insert(direction)
                            }
                        } label: {
                            Text(Self.label(for: direction))
                            if cableDirections.contains(direction) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    ParksFilterPillLabel(title: cableLabel, isActive: !cableDirections.isEmpty, showsChevron: true)
                }

                Button { favoritesOnly.toggle() } label: {
                    ParksFilterPillLabel(
                        title: String(localized: "Favourites"),
                        isActive: favoritesOnly,
                        systemImage: "star.fill"
                    )
                }
                .buttonStyle(.plain)

                if let withoutCableGeoOnly {
                    Button { withoutCableGeoOnly.wrappedValue.toggle() } label: {
                        ParksFilterPillLabel(
                            title: "No cable geo",
                            isActive: withoutCableGeoOnly.wrappedValue,
                            systemImage: "ladybug"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct ParksFilterPillLabel: View {
    let title: String
    let isActive: Bool
    var systemImage: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.6)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isActive ? .white : Color.rpplText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.rpplAccent : Color.rpplFill, in: Capsule())
    }
}

private struct ParksOpenDatePicker: View {
    @Binding var date: Date?

    var body: some View {
        VStack(spacing: 12) {
            DatePicker(
                "Date",
                selection: Binding(get: { date ?? AppClock.now }, set: { date = $0 }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button(String(localized: "Today")) { date = AppClock.now }
                Spacer(minLength: 12)
                Button(String(localized: "Clear"), role: .destructive) { date = nil }
            }
        }
        .padding()
        .rpplPopoverContent(width: 320)
    }
}

/// Shown in place of the parks list when active filters leave nothing to show.
private struct ParksNoMatchCard: View {
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No parks with these filters")
                .font(.headline)
                .foregroundStyle(Color.rpplText)
            Button(String(localized: "Clear filters"), action: onClear)
                .buttonStyle(.borderedProminent)
                .tint(Color.rpplAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .logbookCardChrome()
    }
}

private struct ParkSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.rpplMuted)
            TextField(prompt, text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.rpplText)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.rpplMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.rpplFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A park that was started but not saved yet.
private struct ParkDraftCard: View {
    let draft: ParkEditDraft
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.title3)
                    .foregroundStyle(Color.rpplAccent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title.isEmpty ? String(localized: "Untitled park") : draft.title)
                        .font(.headline)
                        .foregroundStyle(Color.rpplText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.rpplMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.rpplMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .logbookCardChrome()
    }

    private var subtitle: String {
        let when = draft.savedAt.formatted(.relative(presentation: .named))
        return draft.editsParkID == nil
            ? String(localized: "Draft · edited \(when)")
            : String(localized: "Unsaved changes · edited \(when)")
    }
}

private struct ParkCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let park: Park
    let visitCount: Int
    let distanceMeters: Double?
    let isFavorite: Bool
    let entry: ParkEntry?
    let filterDate: Date?
    /// Two-pane: the park open beside the list. Tapping the card selects its list row, which opens it.
    var isSelected = false

    private var statusBadge: (text: String, color: Color)? {
        ParkStatusBadge.text(for: park, filterDate: filterDate)
    }

    @ViewBuilder private var statusChips: some View {
        if let statusBadge {
            ParkChip(
                text: statusBadge.text,
                tint: statusBadge.color,
                fill: statusBadge.color.opacity(0.14)
            )
        }
        if let distanceMeters {
            ParkChip(text: DistanceFormat.kilometers(distanceMeters))
        }
    }

    @ViewBuilder private var countChips: some View {
        if visitCount > 0 {
            ParkChip(text: ParkFormatting.visits(visitCount))
        }
        if park.wakesys == true, !dynamicTypeSize.hidesDecoration {
            ParkChip(text: "Wakesys")
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The name wraps: it is how riders tell parks apart. The star and the origin badge go under it
            // at accessibility sizes.
            AdaptiveStack(rowAlignment: .firstTextBaseline, spacing: 6) {
                Text(park.name)
                    .font(.headline)
                    .foregroundStyle(Color.rpplText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if isFavorite || ParkOriginBadge.text(for: entry) != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(Color.rpplAccent)
                                .accessibilityLabel(Text("Favorite"))
                        }
                        if let badge = ParkOriginBadge.text(for: entry) {
                            Text(badge)
                                .font(.caption)
                                .foregroundStyle(Color.rpplMuted)
                        }
                    }
                }
            }
            // The detail has the address; at the largest sizes the list keeps to name and status.
            if let address = park.address, !dynamicTypeSize.hidesDecoration {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(Color.rpplMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            // Two explicit rows when one row overflows: a wrapping Layout inside a List
            // row reported one row of height, so the card did not grow with the chips.
            // One chip per row when two no longer share one (accessibility sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    statusChips
                    countChips
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { statusChips }
                    HStack(spacing: 6) { countChips }
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusChips
                    countChips
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        cardContent
            .logbookCardChrome()
            .overlay {
                RoundedRectangle(cornerRadius: LogbookLayout.cardCornerRadius, style: .continuous)
                    .stroke(Color.rpplAccent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            // One element that opens the park, as the NavigationLink row was (see SessionCard).
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
