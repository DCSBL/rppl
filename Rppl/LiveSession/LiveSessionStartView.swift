import RpplCore
import SwiftUI

/// Pick the park and what to keep, then start tracking on this iPhone.
struct LiveSessionStartView: View {
    var onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var parks = ParkCatalog.loadApp()
    @State private var draft = ManualSessionDraft.new()
    @State private var location = ParksLocationProvider()
    @State private var pickedByHand = false
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var isStartingWatch = false
    @State private var watchFailed = false

    /// A fix this close to a park counts as being there.
    private static let atParkRadiusMeters = 2_000.0

    private var park: Park? { parks.first { $0.id == draft.parkId } }

    private var locationText: String {
        if let park { return park.name }
        if draft.spot != nil { return draft.spotName ?? String(localized: "Own location") }
        return String(localized: "No location")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
                    NavigationLink {
                        ManualSessionLocationPicker(parks: parks, draft: $draft)
                    } label: {
                        InfoTile("Location", metric: .park) {
                            HStack {
                                Text(locationText).font(.title3.bold()).foregroundStyle(Color.rpplText)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.rpplMuted).accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    LiveConditionsTiles(park: park)

                    actions
                }
                .padding(RpplDesign.tileSpacing)
            }
            .navigationTitle("Start session")
            .navigationBarTitleDisplayMode(.inline)
            .rpplBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // Only when the person already allowed location elsewhere: starting a session never asks.
            .task { location.refresh() }
            .alert("Could not start Apple Watch", isPresented: $watchFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open Rppl on your Apple Watch and start there, or track on iPhone.")
            }
            .onChange(of: draft.parkId) { pickedByHand = true }
            .onChange(of: draft.spot) { pickedByHand = true }
            .onChange(of: location.coordinate) { _, fix in
                guard !pickedByHand, let fix else { return }
                if let near = ParkListing.nearest(to: fix, in: parks, radiusMeters: Self.atParkRadiusMeters) {
                    draft.setPlace(parkId: near.id, spot: nil, name: nil, parks: parks)
                    pickedByHand = false
                } else {
                    draft.setPlace(parkId: nil, spot: fix, name: nil, parks: parks)
                    pickedByHand = false
                    Task {
                        let name = await SessionCityResolver.shared.placeName(near: fix)
                        guard !pickedByHand, draft.spot == fix else { return }
                        draft.spotName = name
                        pickedByHand = false
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
            if let reachable = watchReachable {
                InfoTile("Apple Watch", systemImage: "applewatch") {
                    Label(
                        reachable ? "Reachable" : "Not reachable",
                        systemImage: reachable ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .font(.title3.bold())
                    .foregroundStyle(Color.rpplText)
                    if !reachable {
                        Text("Keep your Apple Watch close and unlocked.")
                            .font(.subheadline)
                            .foregroundStyle(Color.rpplMuted)
                    }
                }
            }

            if watchReachable == true {
                Button(action: startWatch) { Text("Start session").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.rpplAccent)
                    .disabled(isStartingWatch)
            } else {
                if watchReachable == false {
                    Button { connectivity.refreshSyncState() } label: {
                        Text("Try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.rpplAccent)
                }
                Button(action: start) {
                    Text(watchReachable == false ? "Track on iPhone" : "Start session").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.rpplAccent)
            }
        }
    }

    /// nil: no Watch to start on (not paired, or Rppl not installed on it). Otherwise whether it answers now.
    private var watchReachable: Bool? {
        switch connectivity.syncState {
        case .readyLive: true
        case .readyQueued: false
        default: nil
        }
    }

    private func startWatch() {
        isStartingWatch = true
        Task {
            let started = await WatchStarter.start()
            isStartingWatch = false
            if started { dismiss() } else { watchFailed = true }
        }
    }

    private func start() {
        LiveSessionController.shared.start(
            parkId: draft.parkId, spot: draft.parkId == nil ? draft.spot : nil, spotName: draft.spotName
        )
        onStarted()
        dismiss()
    }
}
