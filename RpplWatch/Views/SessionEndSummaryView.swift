import SwiftUI
import MapKit
import RpplCore

/// Post-stop session recap: stats, start map, sync line, Done → idle.
struct SessionEndSummaryView: View {
    let summary: EndedSessionSummary
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService

    private static let store = SessionFileStore(rootURL: AppConstants.documentsSessionsRoot)

    @State private var mapTracks: SessionMapTrackData?
    @State private var mapFrame: MapTrackFrame?
    /// 0 = not rated. Saved to Health on Done.
    @State private var effort = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchSessionMapPreview(
                    mapTracks: mapTracks,
                    startCoordinate: startCoordinate,
                    mapFrame: mapFrame
                )

                Text("Session complete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(SessionFormatters.elapsed(summary.duration))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Color.rpplIdlePrimary)

                SessionMetricRow(
                    label: "Distance",
                    metric: .distance,
                    value: SessionFormatters.distance(summary.distanceMeters)
                )
                SessionMetricRow(
                    label: "Sets",
                    metric: .sets,
                    value: "\(summary.setCount)"
                )

                Divider()
                    .padding(.vertical, 2)

                WatchLastSetSection(
                    duration: summary.lastSetDuration,
                    distanceMeters: summary.lastSetMeters,
                    lapCount: summary.lastSetLapCount,
                    didCompleteSet: summary.didCompleteSet
                )

                Group {
                    if session.isFinalizing {
                        savingLine
                    } else {
                        syncLine
                    }
                }
                .padding(.top, 4)

                if !session.isFinalizing, session.savedWorkout != nil {
                    effortPicker
                }

                Button {
                    let score = effort
                    Task {
                        if score > 0 { await session.saveEffort(score) }
                        session.dismissSessionSummary()
                    }
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rpplIdleAccent)
                // Health save and transfer package are still being written; Done returns to idle,
                // which cannot start a new session until they are.
                .disabled(session.isFinalizing)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .containerBackground(Color.rpplIdleBackground.gradient, for: .tabView)
        .preferredColorScheme(.dark)
        .onAppear {
            transfer.refreshPendingCount()
        }
        // The derived view (map tracks) is written in the background after Stop; load once it
        // exists instead of rebuilding it from raw streams in parallel.
        .task(id: session.isFinalizing) {
            guard !session.isFinalizing else { return }
            await loadMapTracks()
        }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        if let mapTracks {
            return CLLocationCoordinate2D(
                latitude: mapTracks.start.latitude,
                longitude: mapTracks.start.longitude
            )
        }
        guard let latitude = summary.startLatitude, let longitude = summary.startLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func loadMapTracks() async {
        let store = Self.store
        if let derived = try? await StoreIO.runOffMain({
            try store.readDerivedView(sessionId: summary.sessionId)
        }) {
            mapFrame = derived.mapFrame
            if let tracks = derived.mapTracks {
                mapTracks = tracks
                return
            }
        }

        guard store.hasRawStreams(sessionId: summary.sessionId) else { return }
        let built = try? await StoreIO.runOffMain { () -> (SessionMapTrackData?, MapTrackFrame?) in
            let locations = try store.readLocationSamples(sessionId: summary.sessionId)
            let detections = try store.readDetections(sessionId: summary.sessionId)
            let manifest = try store.readManifest(sessionId: summary.sessionId)
            let stats = SessionStatsBuilder.build(
                manifest: manifest,
                detections: detections,
                locations: locations,
                health: [],
                water: []
            )
            let coords = locations.map { (latitude: $0.latitude, longitude: $0.longitude) }
            let frame = MapTrackFitter.frame(locations: coords)
            let tracks = SessionMapTrackBuilder.build(locations: locations, sets: stats.sets)
            return (tracks, frame)
        }
        if let built {
            mapTracks = built.0
            mapFrame = built.1
        }
    }

    /// Digital Crown picker, same 1–10 scale and Easy/Moderate/Hard/All Out bands as Fitness.
    private var effortPicker: some View {
        Picker("Effort", selection: $effort) {
            Text("Skip").tag(0)
            ForEach(1...10, id: \.self) { score in
                Text("\(score) \(Self.effortLabel(score))").tag(score)
            }
        }
        .frame(height: 60)
    }

    private static func effortLabel(_ score: Int) -> String {
        switch score {
        case ...3: String(localized: "Easy")
        case 4...6: String(localized: "Moderate")
        case 7...8: String(localized: "Hard")
        default: String(localized: "All Out")
        }
    }

    private var savingLine: some View {
        HStack(spacing: 6) {
            ProgressView()
                .frame(width: 14, height: 14)
            Text("Saving…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Saving session"))
    }

    private var syncLine: some View {
        let synced = transfer.isSessionSynced(sessionId: summary.sessionId)
        _ = transfer.syncStatusRevision
        return HStack(spacing: 6) {
            Circle()
                .fill(synced ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(synced ? String(localized: "Synced") : String(localized: "Syncing…"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            synced
                ? String(localized: "Synced to iPhone")
                : String(localized: "Syncing to iPhone")
        )
    }
}

#Preview {
    SessionEndSummaryView(
        summary: EndedSessionSummary(
            sessionId: "preview",
            duration: 3725,
            setCount: 4,
            distanceMeters: 2840,
            lastSetDuration: 312,
            lastSetMeters: 720,
            lastSetLapCount: 2,
            didCompleteSet: true,
            startLatitude: 51.9794,
            startLongitude: 4.5740
        ),
        session: WatchSessionController.shared,
        transfer: WatchTransferService.shared
    )
}
