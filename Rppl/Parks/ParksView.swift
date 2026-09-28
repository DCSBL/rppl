import MapKit
import RpplCore
import SwiftUI

struct ParksView: View {
    @Binding var navigation: ParksNavigationRequest
    @State private var path = NavigationPath()
    @State private var store = ParkStore.shared
    @State private var showEditor = false
    @AppStorage(AppSettingsKey.parkEditorEnabled) private var editorEnabled = true
    @State private var sort: ParkListSort = .distance
    @State private var favorites = ParkFavorites.shared
    @State private var location = ParksLocationProvider()
    @State private var catalog = SessionCatalog()
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var showMap = false
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var openFilterDate: Date?
    @State private var cableFilter: Set<ParkCableDirection> = []
    @State private var favoritesOnly = false
    @State private var headerHeight: CGFloat = 0
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var mapPendingRecenter = false
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var mapUsesSatellite = false
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private var parks: [Park] { store.entries.map(\.park) }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visits: [String: Int] {
        let centers = catalog.entries.compactMap(\.center)
        return ParkListing.visitCounts(parks: parks, sessionCenters: centers)
    }

    private var filters: ParkFilters {
        ParkFilters(openOnDate: openFilterDate, cableDirections: cableFilter, favoritesOnly: favoritesOnly)
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
            favorites: favorites.ids,
            visits: visitCounts,
            userLocation: location.coordinate,
            sort: sort
        )
    }

    private func clearFilters() {
        withAnimation(.snappy(duration: 0.2)) {
            openFilterDate = nil
            cableFilter = []
            favoritesOnly = false
        }
    }

    /// "Reasonable distance" for the here/reset button: close enough to be useful, wide enough to
    /// see nearby landmarks around the park.
    private static let recenterCameraDistance: CLLocationDistance = 5_000

    /// Jumps the map to the user's location at a reasonable distance; requests a fresh fix first if needed.
    private func recenterOnUser() {
        if let coordinate = location.coordinate {
            moveMap(to: coordinate)
        } else {
            mapPendingRecenter = true
            location.refresh()
        }
    }

    private func moveMap(to coordinate: ParkCoordinate) {
        let center = CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
        withAnimation {
            mapPosition = .camera(MapCamera(centerCoordinate: center, distance: Self.recenterCameraDistance))
        }
    }

    private func toggleSearch() {
        withAnimation(.snappy(duration: 0.25)) {
            showSearch.toggle()
            if !showSearch { searchText = "" }
        }
        searchFieldFocused = showSearch
    }

    private enum SortChoice: Hashable {
        case sort(ParkListSort)
        case map
    }

    /// The map is a destination, not a sort: picking it opens the cover and keeps the previous sort
    /// selected. Picking "Nearby"/"Most visited" while the map is open closes it back to the list.
    private var sortChoice: Binding<SortChoice> {
        Binding(
            get: { showMap ? .map : .sort(sort) },
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

        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                RpplBackdrop()

                // The map is full height, bleeding under the translucent header below.
                if showMap {
                    ParksMapView(parks: visibleParks, location: location, topInset: headerHeight, position: $mapPosition)
                        .ignoresSafeArea()
                } else {
                    List {
                        if !isSearching, sort == .distance, location.availability != .available {
                            ParksLocationNeededCard(
                                availability: location.availability,
                                onRequestAccess: { location.refresh() },
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
                                    filterDate: openFilterDate
                                )
                                .listRowInsets(LogbookLayout.rowInsets(top: 6, bottom: 6))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, LogbookLayout.horizontalInset, for: .scrollContent)
                    .contentMargins(.top, headerHeight + 8, for: .scrollContent)
                }

                // Floats on top always: title, search/add, sort picker, filter bar. Translucent
                // over the map so it reads as an overlay rather than a second opaque bar.
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Parks")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.rpplText)
                        Spacer()
                        if !allParks.isEmpty {
                            Button(action: toggleSearch) {
                                Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel(Text(showSearch ? "Close search" : "Search parks"))
                        }
                        if editorEnabled {
                            Button {
                                showEditor = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel(Text("Add park"))
                        }
                    }
                    if showSearch {
                        ParkSearchField(text: $searchText, isFocused: $searchFieldFocused)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        Picker("Sort", selection: sortChoice) {
                            Text("Nearby").tag(SortChoice.sort(.distance))
                            Text("Most visited").tag(SortChoice.sort(.visits))
                            Text("View on map").tag(SortChoice.map)
                        }
                        .pickerStyle(.segmented)
                    }
                    if !allParks.isEmpty {
                        ParksFilterBar(
                            openDate: $openFilterDate,
                            cableDirections: $cableFilter,
                            favoritesOnly: $favoritesOnly
                        )
                    }
                }
                .padding(.horizontal, LogbookLayout.horizontalInset)
                .padding(.top, 8)
                .padding(.bottom, 8)
                // `.regularMaterial` (not `.ultraThinMaterial`): the header sits over map/satellite
                // imagery of any color, so it needs enough opacity to keep its text and pills legible.
                .background(showMap ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.rpplBackdropTop))
                .onGeometryChange(
                    for: CGFloat.self,
                    of: { $0.size.height },
                    action: { headerHeight = $0 }
                )

                // Pinned to the header's own measured height, in this same layer, so it always
                // draws above the map and never lags the header by a layout pass.
                if showMap {
                    VStack(spacing: 8) {
                        MapStyleToggleButton(usesSatellite: $mapUsesSatellite)
                        MapRecenterButton(action: recenterOnUser)
                    }
                    .padding(.top, headerHeight + 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Park.self) { park in
                ParkDetailContainer(park: park)
            }
        }
        .tint(Color.rpplAccent)
        .sheet(isPresented: $showEditor) {
            ParkEditorView(original: nil, onSaved: {})
        }
        .task {
            store.reload()
            catalog.reload(store: connectivity.store, acceptedSessionIDs: iCloud.logbookFilterIDs)
        }
        // Refresh only on appear / foreground return — a live-updating fix would reorder the
        // Nearby list out from under the user while they're scrolling or tapping a park.
        .onAppear { location.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            location.refresh()
        }
        .onChange(of: location.coordinate) { _, coordinate in
            guard mapPendingRecenter, let coordinate else { return }
            mapPendingRecenter = false
            moveMap(to: coordinate)
        }
        // `initial: true`: TabView builds this view lazily, so a notification tap before the Parks
        // tab was ever opened creates it with `openParkId` already set — a plain onChange never fires.
        .onChange(of: navigation.openParkId, initial: true) { _, parkId in
            guard let parkId else { return }
            navigation.openParkId = nil
            if store.entries.isEmpty { store.reload() }
            guard let park = store.entry(id: parkId)?.park else { return }
            path.append(park)
        }
    }
}

/// Standard/satellite toggle for the map, using the same native Liquid Glass chrome as the
/// search/add buttons above.
private struct MapStyleToggleButton: View {
    @Binding var usesSatellite: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { usesSatellite.toggle() }
        } label: {
            Image(systemName: usesSatellite ? "map.fill" : "globe.europe.africa.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(
            usesSatellite
                ? Text("Show standard map")
                : Text("Show satellite map")
        )
    }
}

/// Recenters the map on the user's current location at a fixed, useful zoom — unlike MapKit's own
/// user-location button, which recenters without changing the current zoom level.
private struct MapRecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text("Center on my location"))
    }
}

/// Filter pills row: Open (datepicker), Cable (multi-pick), Favourites only (toggle).
private struct ParksFilterBar: View {
    @Binding var openDate: Date?
    @Binding var cableDirections: Set<ParkCableDirection>
    @Binding var favoritesOnly: Bool
    @State private var showOpenPicker = false

    private static let cableChoices: [ParkCableDirection] = [.clockwise, .counterClockwise, .twoD]

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
        case .twoD: String(localized: "2.0")
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
                selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button(String(localized: "Today")) { date = Date() }
                Spacer(minLength: 12)
                Button(String(localized: "Clear"), role: .destructive) { date = nil }
            }
        }
        .padding()
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
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
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.rpplMuted)
            TextField("Search parks", text: $text)
                .focused(isFocused)
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

private struct ParkCard: View {
    let park: Park
    let visitCount: Int
    let distanceMeters: Double?
    let isFavorite: Bool
    let entry: ParkEntry?
    let filterDate: Date?

    private var statusBadge: (text: String, color: Color)? {
        ParkStatusBadge.text(for: park, filterDate: filterDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: park) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(park.name)
                            .font(.headline)
                            .foregroundStyle(Color.rpplText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
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
                    if let address = park.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    FlowLayout(spacing: 6) {
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
                        if visitCount > 0 {
                            ParkChip(text: ParkFormatting.visits(visitCount))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                ParkNavigation.openDirections(to: park)
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.rpplAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Navigate"))
        }
        .logbookCardChrome()
    }
}
