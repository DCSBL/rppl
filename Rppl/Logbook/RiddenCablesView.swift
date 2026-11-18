import RpplCore
import SwiftUI

/// The cables the rider used, per park: the list behind the "Cables ridden by type" tile.
struct RiddenCablesView: View {
    let ridden: RiddenCables
    let parks: [Park]

    var body: some View {
        let catalog = Dictionary(parks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            ForEach(ridden.parks, id: \.parkId) { entry in
                if let park = catalog[entry.parkId], let cables = park.cables {
                    Section(park.compactName) {
                        ForEach(entry.cableIndices, id: \.self) { index in
                            if cables.indices.contains(index) {
                                row(cables[index])
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RpplBackdrop())
        .navigationTitle("Cables ridden")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if ridden.parks.isEmpty {
                ContentUnavailableView("No cables yet", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.rpplMuted)
            }
        }
    }

    private func row(_ cable: ParkCable) -> some View {
        HStack(spacing: 8) {
            ParkCableBadge(cable: cable)
            if let name = cable.name {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(Color.rpplMuted)
            }
        }
    }
}
