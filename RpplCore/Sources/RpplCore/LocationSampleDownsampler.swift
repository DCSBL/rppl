import Foundation

public enum LocationSampleDownsampler {
    /// Evenly pick up to `maxCount` samples so MapKit stays responsive.
    public static func downsample(_ locations: [LocationSample], maxCount: Int) -> [LocationSample] {
        guard maxCount > 1, locations.count > maxCount else { return locations }
        let lastIndex = locations.count - 1
        let step = Double(lastIndex) / Double(maxCount - 1)
        var result: [LocationSample] = []
        result.reserveCapacity(maxCount)
        for index in 0..<maxCount {
            let sampleIndex = min(lastIndex, Int((Double(index) * step).rounded()))
            result.append(locations[sampleIndex])
        }
        return result
    }
}
