import RpplCore
import SwiftUI

/// Pick the park and what to keep, then start tracking on this iPhone.
struct LiveSessionStartView: View {
    var onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var parks = ParkCatalog.loadApp()
    @State private var draft = ManualSessionDraft.new()
    @State private var mode = LiveSession.Mode.setsAndTime
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

                    InfoTile("Track on this iPhone", metric: .sets) {
                        Picker("Track on this iPhone", selection: $mode) {
                            Text("Sets and time").tag(LiveSession.Mode.setsAndTime)
                            Text("Time only").tag(LiveSession.Mode.timeOnly)
                        }
                        .pickerStyle(.segmented)
                    }

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
                guard !pickedByHand, let fix,
                      let near = ParkListing.nearest(to: fix, in: parks, radiusMeters: Self.atParkRadiusMeters)
                else { return }
                draft.setPlace(parkId: near.id, spot: nil, name: nil, parks: parks)
                pickedByHand = false
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: RpplDesign.tileSpacing) {
            if watchAvailable {
                Button(action: startWatch) {
                    Text("Start on Apple Watch").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(isStartingWatch)
                Text("The Watch records everything: sets, speed and heart rate.")
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
            }

            if watchAvailable {
                Text("On the iPhone you keep time and sets yourself, without speed or heart rate.")
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
            } else {
                Text("No Apple Watch found. The iPhone keeps time and sets, without speed or heart rate. You tap Next set yourself.")
                    .font(.footnote)
                    .foregroundStyle(Color.rpplMuted)
            }

            if watchAvailable {
                trackOnPhone.buttonStyle(.bordered).controlSize(.large).tint(.green)
            } else {
                trackOnPhone.buttonStyle(.borderedProminent).controlSize(.large).tint(.green)
            }
        }
    }

    private var trackOnPhone: some View {
        Button(action: start) { Text("Track on iPhone").frame(maxWidth: .infinity) }
    }

    private var watchAvailable: Bool { connectivity.syncState.isReadyToSync }

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
            mode: mode, parkId: draft.parkId, spot: draft.parkId == nil ? draft.spot : nil, spotName: draft.spotName
        )
        onStarted()
        dismiss()
    }
}
