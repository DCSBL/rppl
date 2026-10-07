import RpplCore
import SwiftUI

/// Where a manual session took place: a park from the catalog, an own spot, or nowhere.
struct ManualSessionLocationPicker: View {
    let parks: [Park]
    @Binding var draft: ManualSessionDraft

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pickingOwn = false
    @State private var ownSpot = ParkCoordinate(lat: 0, lon: 0)

    private var shownParks: [Park] { ParkSearch.rank(parks, query: query) }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    Button("Pick your own location", systemImage: "mappin.and.ellipse") { pickingOwn = true }
                    Button("No location", systemImage: "mappin.slash") {
                        draft.setPlace(parkId: nil, spot: nil, name: nil, parks: parks)
                        dismiss()
                    }
                }
            }
            Section("Parks") {
                ForEach(shownParks) { park in
                    Button {
                        draft.setPlace(parkId: park.id, spot: nil, name: nil, parks: parks)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(park.name).foregroundStyle(Color.rpplText)
                                if let address = park.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(Color.rpplMuted)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if draft.parkId == park.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search parks"))
        .sheet(isPresented: $pickingOwn) {
            LocationPickerView(coordinate: $ownSpot, userLocation: draft.spot, title: "Your location")
        }
        .onChange(of: ownSpot) { _, spot in
            Task {
                let name = await ParkPlaceResolver.shared.placeName(at: spot)
                draft.setPlace(parkId: nil, spot: spot, name: name, parks: parks)
                dismiss()
            }
        }
    }
}
