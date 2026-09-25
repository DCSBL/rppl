import RpplCore
import SwiftUI

struct ParksView: View {
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

    /// While searching, order is relevance (best hit first); otherwise the chosen sort.
    private var sortedParks: [Park] {
        if isSearching {
            return ParkSearch.rank(parks, query: searchText)
        }
        return ParkListing.sorted(
            parks,
            favorites: favorites.ids,
            visits: visits,
            userLocation: location.coordinate,
            sort: sort
        )
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

    /// The map is a destination, not a sort: picking it opens the cover and keeps the previous sort selected.
    private var sortChoice: Binding<SortChoice> {
        Binding(
            get: { .sort(sort) },
            set: {
                switch $0 {
                case .sort(let value): sort = value
                case .map: showMap = true
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if showMap {
                    ParksMapView(parks: parks, location: location, onClose: { showMap = false })
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Parks")
                                        .font(.largeTitle.bold())
                                        .foregroundStyle(Color.rpplText)
                                    Spacer()
                                    if !parks.isEmpty {
                                        Button(action: toggleSearch) {
                                            Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                                                .font(.title3.weight(.semibold))
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(Text(showSearch ? "Close search" : "Search parks"))
                                    }
                                    if editorEnabled {
                                        Button {
                                            showEditor = true
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.title3.weight(.semibold))
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.borderless)
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
                            }
                            .listRowInsets(LogbookLayout.rowInsets(top: 8, bottom: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

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
                        } else if parks.isEmpty {
                            Text("No parks yet")
                                .foregroundStyle(Color.rpplMuted)
                                .listRowBackground(Color.clear)
                        } else if sortedParks.isEmpty {
                            Text("No parks found")
                                .foregroundStyle(Color.rpplMuted)
                                .listRowBackground(Color.clear)
                        } else {
                            let counts = visits
                            ForEach(sortedParks) { park in
                                ParkCard(
                                    park: park,
                                    visitCount: counts[park.id] ?? 0,
                                    distanceMeters: location.coordinate.map { park.location.meters(to: $0) },
                                    isFavorite: favorites.contains(park.id),
                                    entry: store.entry(id: park.id)
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
                    .contentMargins(.top, 8, for: .scrollContent)
                }
            }
            .background(Color.rpplBackground)
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
    }
}

extension Park: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

    private var openStatus: ParkOpenStatus? {
        park.opening == nil ? nil : park.openStatus()
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
                        if let openStatus {
                            ParkChip(
                                text: openStatus.badgeText,
                                tint: openStatus.badgeColor,
                                fill: openStatus.badgeColor.opacity(0.14)
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
