import CoreLocation
import RpplCore

/// Debug walking route: the averaged walk of every tracked session at a park (`ParkWalkRouteBuilder`).
enum ParkWalkRouteLoader {
    static func sections(parkId: String, store: SessionFileStore) async -> [[CLLocationCoordinate2D]] {
        let sections = (try? await StoreIO.runOffMain { () -> [[MapCoordinate]] in
            let manifests = try store.listReadableManifests()
                .filter { $0.parkId == parkId && $0.manual == nil }
            var sessionTracks: [[[MapCoordinate]]] = []
            for manifest in manifests {
                let sessionId = manifest.sessionId
                let derived = try? store.readDerivedView(sessionId: sessionId)
                if let walks = derived?.mapTracks?.walkTracks {
                    sessionTracks.append(walks)
                } else if let locations = try? store.readLocationSamples(sessionId: sessionId) {
                    // A sidecar from before walks were distilled: build them from the raw GPS.
                    let sets = derived?.stats.sets ?? []
                    sessionTracks.append(WalkTrackBuilder.build(locations: locations, sets: sets).tracks)
                }
            }
            return ParkWalkRouteBuilder.sections(sessionTracks: sessionTracks)
        }) ?? []
        return sections.map { section in
            section.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }
}
