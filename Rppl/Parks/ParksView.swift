import RpplCore
import SwiftUI

struct ParksView: View {
    @State private var parks: [Park] = []
    @State private var sort: ParkListSort = .distance
    @State private var favorites = ParkFavorites.shared
    @State private var location = ParksLocationProvider()
    @State private var catalog = SessionCatalog()
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private var visits: [String: Int] {
        let centers = catalog.entries.compactMap(\.center)
        return ParkListing.visitCounts(parks: parks, sessionCenters: centers)
    }

    private var sortedParks: [Park] {
        ParkListing.sorted(
            ParkSearch.filter(parks, query: searchText),
            favorites: favorites.ids,
            visits: visits,
            userLocation: location.coordinate,
            sort: sort
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Parks")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.rpplText)
                        Picker("Sort", selection: $sort) {
                            Text("Nearby").tag(ParkListSort.distance)
                            Text("Most visited").tag(ParkListSort.visits)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowInsets(LogbookLayout.rowInsets(top: 8, bottom: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if sort == .distance, location.availability != .available {
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
                            isFavorite: favorites.contains(park.id)
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
            .background(Color.rpplBackground)
            .toolbar(.hidden, for: .navigationBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search parks"))
            .navigationDestination(for: Park.self) { park in
                ParkDetailContainer(park: park)
            }
        }
        .tint(Color.rpplAccent)
        .task {
            parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
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

private struct ParkCard: View {
    let park: Park
    let visitCount: Int
    let distanceMeters: Double?
    let isFavorite: Bool

    private var openToday: Bool? {
        park.opening == nil ? nil : park.schedule().isOpen
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
                    }
                    if let address = park.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(Color.rpplMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        if let openToday {
                            ParkChip(
                                text: openToday ? String(localized: "Open today") : String(localized: "Closed today"),
                                tint: openToday ? .green : .red,
                                fill: (openToday ? Color.green : Color.red).opacity(0.14)
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
