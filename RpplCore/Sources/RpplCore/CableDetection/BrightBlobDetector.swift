import Foundation

/// A small bright object floating on the water: obstacle, mast platform, buoy or boat.
public struct FloatingObject: Sendable, Equatable {
    /// Local metres (x east, y north).
    public var xy: SIMD2<Double>
    public var areaM2: Double
    /// Approximate side lengths of the object's bounding rectangle, metres.
    public var lengthM: Double
    public var widthM: Double
    /// Contrast over the surrounding water, in gray levels.
    public var brightness: Double
}

/// Finds bright compact objects on the water: everything that is neither water texture nor shore.
struct BrightBlobDetector: Sendable {
    var minimumAreaM2 = 0.8
    var maximumAreaM2 = 120.0
    var shoreMarginM = 6.0
    /// The local background is a median over roughly this many pixels.
    var backgroundWindowPx = 31

    func detect(in image: DetectionImage, water: WaterSegmenter.Mask) -> [FloatingObject] {
        let width = image.width, height = image.height
        let mpp = image.metersPerPixel
        let marginCells = max(1, Int((shoreMarginM / mpp / Double(water.factor)).rounded()))
        let inner = WaterSegmenter.Mask(bitmap: water.bitmap.eroded(iterations: marginCells), factor: water.factor)
        guard !inner.bitmap.isEmpty else { return [] }

        let gray = image.grayscale()
        // Local water brightness from a coarse median, so a bright lake and a dark lake get the same threshold.
        let coarseFactor = 8
        let coarse = downsample(gray, width: width, height: height, by: coarseFactor)
        let medianRadius = max(1, backgroundWindowPx / coarseFactor / 2)
        let background = Self.median(coarse.values, width: coarse.width, height: coarse.height, radius: medianRadius)
        var diff = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let fy = (Float(y) + 0.5) / Float(coarseFactor) - 0.5
            for x in 0..<width {
                let fx = (Float(x) + 0.5) / Float(coarseFactor) - 0.5
                diff[y * width + x] = gray[y * width + x] - bilinear(background, width: coarse.width, height: coarse.height, x: fx, y: fy)
            }
        }
        // Noise level of the water itself (sampled), then a threshold well above it.
        var sum = 0.0, sumSquares = 0.0, samples = 0
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) where inner.isWater(column: x, row: y) {
                let v = Double(diff[y * width + x])
                sum += v; sumSquares += v * v; samples += 1
            }
        }
        guard samples > 0 else { return [] }
        let mean = sum / Double(samples)
        let std = sqrt(max(sumSquares / Double(samples) - mean * mean, 0))
        let threshold = Float(max(18, 4 * std))

        var candidate = Bitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where diff[y * width + x] > threshold && inner.isWater(column: x, row: y) {
                candidate[x, y] = true
            }
        }
        candidate = candidate.opened(iterations: 1)
        let (labels, sizes) = candidate.components()
        guard !sizes.isEmpty else { return [] }

        let pixelArea = mpp * mpp
        // Per-component accumulators for centroid, second moments and brightness.
        var sx = [Double](repeating: 0, count: sizes.count), sy = sx, sxx = sx, syy = sx, sxy = sx, sb = sx
        for y in 0..<height {
            for x in 0..<width {
                let label = Int(labels[y * width + x])
                guard label > 0 else { continue }
                let i = label - 1
                let area = Double(sizes[i]) * pixelArea
                guard area >= minimumAreaM2, area <= maximumAreaM2 else { continue }
                let fx = Double(x), fy = Double(y)
                sx[i] += fx; sy[i] += fy; sxx[i] += fx * fx; syy[i] += fy * fy; sxy[i] += fx * fy
                sb[i] += Double(diff[y * width + x])
            }
        }
        var objects: [FloatingObject] = []
        let ringPx = Int((12 / mpp).rounded())
        for i in 0..<sizes.count {
            let n = Double(sizes[i])
            let area = n * pixelArea
            guard area >= minimumAreaM2, area <= maximumAreaM2 else { continue }
            let cx = sx[i] / n, cy = sy[i] / n
            // A floating object is surrounded by water; trees on an island or a quay are not.
            guard water.waterFraction(aroundColumn: Int(cx), row: Int(cy), halfSize: ringPx) >= 0.7 else { continue }
            // Side lengths from the second moments (a uniform rectangle has variance side^2 / 12).
            let vxx = sxx[i] / n - cx * cx, vyy = syy[i] / n - cy * cy, vxy = sxy[i] / n - cx * cy
            let trace = vxx + vyy
            let root = sqrt(max((vxx - vyy) * (vxx - vyy) / 4 + vxy * vxy, 0))
            let major = max(trace / 2 + root, 0), minor = max(trace / 2 - root, 0)
            let length = max(sqrt(12 * major) + 1, 1) * mpp
            let widthM = max(sqrt(12 * minor) + 1, 1) * mpp
            objects.append(FloatingObject(
                xy: image.local(fromPixelColumn: cx, row: cy),
                areaM2: area,
                lengthM: length,
                widthM: widthM,
                brightness: sb[i] / n
            ))
        }
        return objects
    }

    /// Median filter with a square window of `radius`, clipped at the edges.
    static func median(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        var window: [Float] = []
        window.reserveCapacity((2 * radius + 1) * (2 * radius + 1))
        for y in 0..<height {
            for x in 0..<width {
                window.removeAll(keepingCapacity: true)
                for wy in max(0, y - radius)...min(height - 1, y + radius) {
                    for wx in max(0, x - radius)...min(width - 1, x + radius) {
                        window.append(values[wy * width + wx])
                    }
                }
                window.sort()
                out[y * width + x] = window[window.count / 2]
            }
        }
        return out
    }
}
