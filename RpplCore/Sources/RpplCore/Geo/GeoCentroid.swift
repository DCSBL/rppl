import Foundation

public enum GeoCentroid {
    /// Centroid of usable GPS points for reverse geocoding.
    public static func representative(from locations: [LocationSample]) -> (latitude: Double, longitude: Double)? {
        let usable = locations.filter { sample in
            sample.horizontalAccuracy > 0 && sample.horizontalAccuracy <= 500
        }
        let points = usable.isEmpty ? locations : usable
        guard !points.isEmpty else { return nil }

        let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let longitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return (latitude, longitude)
    }
}
