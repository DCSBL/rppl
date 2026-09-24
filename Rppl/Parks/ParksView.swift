import RpplCore
import SwiftUI

struct ParksView: View {
    @State private var parks: [Park] = []
    @State private var sort: ParkListSort = .distance
    @State private var favorites = ParkFavorites()
    @State private var location = ParksLocationProvider()
    @State private var catalog = SessionCatalog()
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var iCloud = PhoneICloudDriveController.shared

    private var visits: [String: Int] {
        let centers = catalog.entries.compactMap(\.center)
        return ParkListing.visitCounts(parks: parks, sessionCenters: centers)
    }

    private var sortedParks: [Park] {
        ParkListing.sorted(
            parks,
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
                    Picker("Sort", selection: $sort) {
                        Text("Nearby").tag(ParkListSort.distance)
                        Text("Most visited").tag(ParkListSort.visits)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if parks.isEmpty {
                    Text("No parks yet")
                        .foregroundStyle(Color.rpplMuted)
                } else {
                    let counts = visits
                    ForEach(sortedParks) { park in
                        NavigationLink(value: park) {
                            ParkRow(
                                park: park,
                                visitCount: counts[park.id] ?? 0,
                                distanceMeters: location.coordinate.map { park.location.meters(to: $0) },
                                isFavorite: favorites.contains(park.id),
                                onToggleFavorite: { favorites.toggle(park.id) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Parks")
            .navigationDestination(for: Park.self) { park in
                ParkDetailView(
                    park: park,
                    isFavorite: favorites.contains(park.id),
                    onToggleFavorite: { favorites.toggle(park.id) }
                )
            }
        }
        .task {
            parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
            location.start()
            catalog.reload(store: connectivity.store, acceptedSessionIDs: iCloud.logbookFilterIDs)
        }
    }
}

extension Park: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct ParkRow: View {
    let park: Park
    let visitCount: Int
    let distanceMeters: Double?
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.rpplAccent : Color.rpplMuted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? Text("Remove favorite") : Text("Add favorite"))

            VStack(alignment: .leading, spacing: 2) {
                Text(park.name)
                    .font(.headline)
                    .foregroundStyle(Color.rpplText)
                if let address = park.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(Color.rpplMuted)
                }
                HStack(spacing: 8) {
                    if let distanceMeters {
                        Text(DistanceFormat.kilometers(distanceMeters))
                    }
                    if visitCount > 0 {
                        Text(ParkFormatting.visits(visitCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.rpplMuted)
            }

            Spacer(minLength: 0)

            Button {
                ParkNavigation.openDirections(to: park)
            } label: {
                Image(systemName: "location.fill")
            }
            .buttonStyle(.borderless)
            .tint(Color.rpplAccent)
            .accessibilityLabel(Text("Navigate"))
        }
    }
}
