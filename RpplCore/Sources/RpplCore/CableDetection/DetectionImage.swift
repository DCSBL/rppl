import Foundation

/// A satellite close-up of a park as raw RGB, with the scale and position needed to go from
/// pixels to coordinates. The detector works in a local frame of metres around the park location
/// (x east, y north), like the hand-traced data it was tuned on.
public struct DetectionImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, three bytes per pixel (R, G, B), no padding.
    public let rgb: [UInt8]
    public let metersPerPixel: Double
    /// Coordinate at the centre of the image.
    public let center: ParkCoordinate
    /// Origin of the local metres frame, normally the park location.
    public let origin: ParkCoordinate

    public init(width: Int, height: Int, rgb: [UInt8], metersPerPixel: Double, center: ParkCoordinate, origin: ParkCoordinate) {
        precondition(rgb.count == width * height * 3, "rgb must hold width * height * 3 bytes")
        self.width = width
        self.height = height
        self.rgb = rgb
        self.metersPerPixel = metersPerPixel
        self.center = center
        self.origin = origin
    }

    // MARK: Frames

    /// Local metres of a coordinate relative to the origin (equirectangular, fine within a few km).
    public static func localXY(of coordinate: ParkCoordinate, origin: ParkCoordinate) -> SIMD2<Double> {
        let scale = cos(origin.lat * .pi / 180)
        return SIMD2(
            (coordinate.lon - origin.lon) * scale * 111_320,
            (coordinate.lat - origin.lat) * 110_574
        )
    }

    public static func coordinate(fromLocal xy: SIMD2<Double>, origin: ParkCoordinate) -> ParkCoordinate {
        let scale = cos(origin.lat * .pi / 180)
        return ParkCoordinate(lat: origin.lat + xy.y / 110_574, lon: origin.lon + xy.x / (scale * 111_320))
    }

    public func localXY(of coordinate: ParkCoordinate) -> SIMD2<Double> {
        Self.localXY(of: coordinate, origin: origin)
    }

    public func coordinate(fromLocal xy: SIMD2<Double>) -> ParkCoordinate {
        Self.coordinate(fromLocal: xy, origin: origin)
    }

    private var centerXY: SIMD2<Double> { localXY(of: center) }

    /// Pixel position (column, row) of a local point; may fall outside the image.
    public func pixel(fromLocal xy: SIMD2<Double>) -> SIMD2<Double> {
        let delta = xy - centerXY
        return SIMD2(
            Double(width) / 2 + delta.x / metersPerPixel,
            Double(height) / 2 - delta.y / metersPerPixel
        )
    }

    /// Local metres of a pixel position (column, row).
    public func local(fromPixelColumn column: Double, row: Double) -> SIMD2<Double> {
        centerXY + SIMD2(
            (column - Double(width) / 2) * metersPerPixel,
            (Double(height) / 2 - row) * metersPerPixel
        )
    }

    // MARK: Derived rasters

    /// Luma per pixel with OpenCV's RGB weights, as Float.
    func grayscale() -> [Float] {
        var gray = [Float](repeating: 0, count: width * height)
        rgb.withUnsafeBufferPointer { source in
            for index in 0..<(width * height) {
                let base = index * 3
                gray[index] = 0.299 * Float(source[base]) + 0.587 * Float(source[base + 1]) + 0.114 * Float(source[base + 2])
            }
        }
        return gray
    }

    /// Block-averaged copy at 1/`factor` resolution, as Float RGB planes interleaved (R, G, B).
    func downsampled(by factor: Int) -> (width: Int, height: Int, rgb: [Float]) {
        let newWidth = width / factor
        let newHeight = height / factor
        var out = [Float](repeating: 0, count: newWidth * newHeight * 3)
        let norm = 1 / Float(factor * factor)
        rgb.withUnsafeBufferPointer { source in
            for y in 0..<newHeight {
                for x in 0..<newWidth {
                    var sum = SIMD3<Float>(repeating: 0)
                    for dy in 0..<factor {
                        var base = ((y * factor + dy) * width + x * factor) * 3
                        for _ in 0..<factor {
                            sum += SIMD3(Float(source[base]), Float(source[base + 1]), Float(source[base + 2]))
                            base += 3
                        }
                    }
                    let outBase = (y * newWidth + x) * 3
                    out[outBase] = sum.x * norm
                    out[outBase + 1] = sum.y * norm
                    out[outBase + 2] = sum.z * norm
                }
            }
        }
        return (newWidth, newHeight, out)
    }
}

/// Block average of a Float raster.
func downsample(_ values: [Float], width: Int, height: Int, by factor: Int) -> (width: Int, height: Int, values: [Float]) {
    let newWidth = width / factor
    let newHeight = height / factor
    var out = [Float](repeating: 0, count: newWidth * newHeight)
    let norm = 1 / Float(factor * factor)
    values.withUnsafeBufferPointer { source in
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                var sum: Float = 0
                for dy in 0..<factor {
                    let base = (y * factor + dy) * width + x * factor
                    for dx in 0..<factor { sum += source[base + dx] }
                }
                out[y * newWidth + x] = sum * norm
            }
        }
    }
    return (newWidth, newHeight, out)
}

/// Bilinear sample of a raster at fractional (x, y); clamps at the edges.
func bilinear(_ values: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
    let cx = min(max(x, 0), Float(width - 1))
    let cy = min(max(y, 0), Float(height - 1))
    let x0 = Int(cx), y0 = Int(cy)
    let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
    let fx = cx - Float(x0), fy = cy - Float(y0)
    let top = values[y0 * width + x0] * (1 - fx) + values[y0 * width + x1] * fx
    let bottom = values[y1 * width + x0] * (1 - fx) + values[y1 * width + x1] * fx
    return top * (1 - fy) + bottom * fy
}
