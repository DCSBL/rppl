import Foundation

/// Camera parameters to frame GPS tracks on a MapKit map (pitch 0).
public struct MapTrackFit: Equatable, Sendable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    /// MapKit heading in degrees, always in `[-maxHeadingDegrees, maxHeadingDegrees]`.
    public var headingDegrees: Double
    /// Distance from camera to ground center, meters.
    public var cameraDistanceMeters: Double

    public init(
        centerLatitude: Double,
        centerLongitude: Double,
        headingDegrees: Double,
        cameraDistanceMeters: Double
    ) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.headingDegrees = headingDegrees
        self.cameraDistanceMeters = cameraDistanceMeters
    }
}

/// Pure fit helper: PCA heading + padded AABB → camera distance.
public enum MapTrackFitter {
    /// Auto heading never exceeds this magnitude (degrees).
    public static let maxHeadingDegrees = 90.0
    /// Extra frame around track AABB (1.0 = flush).
    public static let defaultPaddingFactor = 1.2
    public static let minimumCameraDistanceMeters = 80.0

    private static let metersPerDegreeLat = 111_320.0
    /// Approximate MapKit pitch-0 half vertical FOV (radians) for distance estimate.
    private static let halfVerticalFOVRadians = 15.0 * .pi / 180.0

    public static func fit(
        locations: [(latitude: Double, longitude: Double)],
        viewWidth: Double,
        viewHeight: Double,
        paddingFactor: Double = defaultPaddingFactor
    ) -> MapTrackFit? {
        guard locations.count >= 2,
              viewWidth > 1,
              viewHeight > 1
        else {
            return nil
        }

        var sumLat = 0.0
        var sumLon = 0.0
        for loc in locations {
            sumLat += loc.latitude
            sumLon += loc.longitude
        }
        let count = Double(locations.count)
        let meanLat = sumLat / count
        let meanLon = sumLon / count
        let metersPerDegreeLon = metersPerDegreeLat * cos(meanLat * .pi / 180)

        var points: [(e: Double, n: Double)] = []
        points.reserveCapacity(locations.count)
        for loc in locations {
            let e = (loc.longitude - meanLon) * metersPerDegreeLon
            let n = (loc.latitude - meanLat) * metersPerDegreeLat
            points.append((e, n))
        }

        // Align principal axis with screen-horizontal (right), then clamp to ±90.
        let heading = clampedHeadingDegrees(principalHeadingDegrees(points) - 90)
        let frame = cameraFrameBounds(points: points, headingDegrees: heading)
        let pad = max(paddingFactor, 1.0)
        let paddedWidth = max(frame.width * pad, 12)
        let paddedHeight = max(frame.height * pad, 12)
        let metersPerPoint = max(paddedWidth / viewWidth, paddedHeight / viewHeight)
        let visibleHeightMeters = metersPerPoint * viewHeight
        let distance = max(
            minimumCameraDistanceMeters,
            (visibleHeightMeters / 2) / tan(halfVerticalFOVRadians)
        )

        let centerE = frame.midE
        let centerN = frame.midN
        let centerLat = meanLat + centerN / metersPerDegreeLat
        let centerLon = meanLon + centerE / metersPerDegreeLon

        return MapTrackFit(
            centerLatitude: centerLat,
            centerLongitude: centerLon,
            headingDegrees: heading,
            cameraDistanceMeters: distance
        )
    }

    /// Flatten ride/session tracks into coordinate pairs for `fit`.
    public static func coordinates(
        fromTracks tracks: [[LocationSample]]
    ) -> [(latitude: Double, longitude: Double)] {
        tracks.flatMap { track in
            track.map { (latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    /// Normalize undirected-axis heading into `[-maxHeadingDegrees, maxHeadingDegrees]`.
    public static func clampedHeadingDegrees(_ heading: Double) -> Double {
        var value = heading.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        while value > maxHeadingDegrees { value -= 180 }
        while value < -maxHeadingDegrees { value += 180 }
        return value
    }

    // MARK: - Private

    /// MapKit heading (degrees from north, clockwise) of the principal axis.
    private static func principalHeadingDegrees(_ points: [(e: Double, n: Double)]) -> Double {
        guard points.count >= 2 else { return 0 }

        var sumE = 0.0
        var sumN = 0.0
        for p in points {
            sumE += p.e
            sumN += p.n
        }
        let inv = 1.0 / Double(points.count)
        let meanE = sumE * inv
        let meanN = sumN * inv

        var cxx = 0.0
        var cxy = 0.0
        var cyy = 0.0
        for p in points {
            let de = p.e - meanE
            let dn = p.n - meanN
            cxx += de * de
            cxy += de * dn
            cyy += dn * dn
        }

        // Angle of major axis from +east toward +north.
        let theta = 0.5 * atan2(2 * cxy, cxx - cyy)
        let east = cos(theta)
        let north = sin(theta)
        return atan2(east, north) * 180 / .pi
    }

    private struct FrameBounds {
        var midE: Double
        var midN: Double
        var width: Double
        var height: Double
    }

    /// AABB in camera frame (right/up), returned as EN center + size.
    private static func cameraFrameBounds(
        points: [(e: Double, n: Double)],
        headingDegrees: Double
    ) -> FrameBounds {
        let hRad = headingDegrees * .pi / 180
        let cosH = cos(hRad)
        let sinH = sin(hRad)
        // Camera right / up in EN.
        let rightE = cosH
        let rightN = -sinH
        let upE = sinH
        let upN = cosH

        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity
        for p in points {
            let x = p.e * rightE + p.n * rightN
            let y = p.e * upE + p.n * upN
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }

        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return FrameBounds(
            midE: midX * rightE + midY * upE,
            midN: midX * rightN + midY * upN,
            width: max(maxX - minX, 1e-3),
            height: max(maxY - minY, 1e-3)
        )
    }
}
