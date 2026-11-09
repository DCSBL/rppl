import Foundation

/// Water on a satellite close-up: smooth, darker and less saturated than land. Unsupervised:
/// k-means on (L, a, b, saturation, local texture) picks the cluster that looks most like water,
/// then the water body at or nearest to the park location is kept.
///
/// Works on a grid of `factor` x `factor` pixel blocks; the returned mask has that resolution.
struct WaterSegmenter: Sendable {
    struct Mask: Sendable {
        let bitmap: Bitmap
        /// Full-resolution pixels per mask cell.
        let factor: Int

        /// Whether a full-resolution pixel is water (false outside the image).
        @inline(__always) func isWater(column: Int, row: Int) -> Bool {
            bitmap.value(x: column / factor, y: row / factor)
        }

        func isWater(column: Double, row: Double) -> Bool {
            column >= 0 && row >= 0 && isWater(column: Int(column), row: Int(row))
        }

        /// Fraction of water cells in the square of `halfSize` full-resolution pixels around a pixel.
        func waterFraction(aroundColumn column: Int, row: Int, halfSize: Int) -> Double {
            let x0 = max(0, (column - halfSize) / factor), x1 = min(bitmap.width - 1, (column + halfSize) / factor)
            let y0 = max(0, (row - halfSize) / factor), y1 = min(bitmap.height - 1, (row + halfSize) / factor)
            guard x1 >= x0, y1 >= y0 else { return 0 }
            var water = 0
            for y in y0...y1 { for x in x0...x1 where bitmap[x, y] { water += 1 } }
            return Double(water) / Double((x1 - x0 + 1) * (y1 - y0 + 1))
        }

        var cellCount: Int { bitmap.count }
        var fraction: Double { Double(bitmap.count) / Double(bitmap.width * bitmap.height) }
    }

    var factor = 4
    var clusterCount = 6
    /// Thresholds in full-resolution pixels (tuned at 0.29 m/px, 2048 px images).
    var minimumAreaPx = 20_000
    var maximumHolePx = 18_000
    var nearPx = 1_000

    func segment(_ image: DetectionImage) -> Mask {
        let coarse = image.downsampled(by: factor)
        let cellCount = coarse.width * coarse.height
        // Features per cell: L, a, b (OpenCV-style, scaled to 0...1), HSV saturation, texture.
        var features = [Float](repeating: 0, count: cellCount * 5)
        var gray = [Float](repeating: 0, count: cellCount)
        for index in 0..<cellCount {
            let r = coarse.values[index * 3] / 255, g = coarse.values[index * 3 + 1] / 255, b = coarse.values[index * 3 + 2] / 255
            let lab = Self.lab(r: r, g: g, b: b)
            let maxC = max(r, g, b), minC = min(r, g, b)
            features[index * 5] = lab.x / 100
            features[index * 5 + 1] = (lab.y + 128) / 255
            features[index * 5 + 2] = (lab.z + 128) / 255
            features[index * 5 + 3] = maxC > 0 ? (maxC - minC) / maxC : 0
            gray[index] = (0.299 * r + 0.587 * g + 0.114 * b) * 255
        }
        let texture = Self.localStandardDeviation(Self.boxBlur(gray, width: coarse.width, height: coarse.height, radius: 1), width: coarse.width, height: coarse.height, radius: 2)
        for index in 0..<cellCount { features[index * 5 + 4] = min(texture[index] / 30, 1) }

        let clustering = KMeans.run(features, dimensions: 5, count: clusterCount, attempts: 3, iterations: 30)
        // Water-likeness of each cluster centre: smooth, not bright, not saturated, not green
        // (a < 0.5 in Lab is green: grass and fields are smooth too, the usual confusion).
        var best = 0
        var bestScore = Float.greatestFiniteMagnitude
        for cluster in 0..<clusterCount {
            let c = clustering.centers[(cluster * 5)..<(cluster * 5 + 5)]
            let center = Array(c)
            let score = 2 * center[4] + center[0] + center[3] + 2 * max(0.5 - center[1], 0) + 0.5 * max(center[2] - 0.55, 0)
            if score < bestScore { bestScore = score; best = cluster }
        }
        var mask = Bitmap(width: coarse.width, height: coarse.height, bits: clustering.labels.map { $0 == best })
        mask = mask.opened(iterations: 1).closed(iterations: 2)
        mask = mask.fillingHoles(maxArea: maximumHolePx / (factor * factor))

        let (labels, sizes) = mask.components()
        guard !sizes.isEmpty else { return Mask(bitmap: mask, factor: factor) }
        let seedPixel = image.pixel(fromLocal: SIMD2(0, 0))
        let seedX = min(max(Int(seedPixel.x) / factor, 0), coarse.width - 1)
        let seedY = min(max(Int(seedPixel.y) / factor, 0), coarse.height - 1)
        let minimumArea = minimumAreaPx / (factor * factor)
        var chosen = Int(labels[seedY * coarse.width + seedX])
        if chosen == 0 || sizes[chosen - 1] < minimumArea {
            // The park location is usually on the shore next to the water: take the largest
            // component that comes within `nearPx` of it; the cable is never further away.
            var nearest = [Double](repeating: .infinity, count: sizes.count + 1)
            for y in 0..<coarse.height {
                for x in 0..<coarse.width {
                    let label = Int(labels[y * coarse.width + x])
                    if label > 0 {
                        let d = hypot(Double(x - seedX), Double(y - seedY))
                        if d < nearest[label] { nearest[label] = d }
                    }
                }
            }
            let limit = Double(nearPx / factor)
            var bestLabel = 0, bestSize = 0
            for label in 1...sizes.count where sizes[label - 1] >= minimumArea && sizes[label - 1] > bestSize && nearest[label] <= limit {
                bestLabel = label; bestSize = sizes[label - 1]
            }
            if bestLabel == 0, let largest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) {
                bestLabel = largest + 1
            }
            chosen = bestLabel
        }
        return Mask(bitmap: Bitmap.component(Int32(chosen), in: labels, width: coarse.width, height: coarse.height), factor: factor)
    }

    // MARK: Helpers

    /// CIE Lab (D65) as (L, a, b) from sRGB in 0...1, like OpenCV's RGB2LAB before its 8-bit scaling.
    static func lab(r: Float, g: Float, b: Float) -> SIMD3<Float> {
        func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let x = (0.412453 * rl + 0.357580 * gl + 0.180423 * bl) / 0.950456
        let y = 0.212671 * rl + 0.715160 * gl + 0.072169 * bl
        let z = (0.019334 * rl + 0.119193 * gl + 0.950227 * bl) / 1.088754
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrtf(t) : 7.787 * t + 16 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func boxBlur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let integral = IntegralImage(values, width: width, height: height)
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = integral.mean(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius)
            }
        }
        return out
    }

    static func localStandardDeviation(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let integral = IntegralImage(values, width: width, height: height)
        let squares = IntegralImage(values.map { $0 * $0 }, width: width, height: height)
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let mean = integral.mean(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius)
                let meanSquare = squares.mean(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius)
                out[y * width + x] = sqrt(max(meanSquare - mean * mean, 0))
            }
        }
        return out
    }
}

/// Summed-area table for fast box means; windows are clipped to the raster.
struct IntegralImage {
    let width: Int
    let height: Int
    private var sums: [Double]

    init(_ values: [Float], width: Int, height: Int) {
        self.width = width
        self.height = height
        sums = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            for x in 0..<width {
                rowSum += Double(values[y * width + x])
                sums[(y + 1) * (width + 1) + x + 1] = sums[y * (width + 1) + x + 1] + rowSum
            }
        }
    }

    func mean(x0: Int, y0: Int, x1: Int, y1: Int) -> Float {
        let cx0 = max(0, x0), cy0 = max(0, y0), cx1 = min(width - 1, x1), cy1 = min(height - 1, y1)
        guard cx1 >= cx0, cy1 >= cy0 else { return 0 }
        let stride = width + 1
        let total = sums[(cy1 + 1) * stride + cx1 + 1] - sums[cy0 * stride + cx1 + 1] - sums[(cy1 + 1) * stride + cx0] + sums[cy0 * stride + cx0]
        return Float(total / Double((cx1 - cx0 + 1) * (cy1 - cy0 + 1)))
    }
}

/// Plain k-means with k-means++ seeding; deterministic, several attempts keep the tightest result.
enum KMeans {
    struct Result {
        var labels: [Int]
        var centers: [Float]
        var compactness: Double
    }

    static func run(_ data: [Float], dimensions: Int, count: Int, attempts: Int, iterations: Int, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) -> Result {
        var best: Result?
        var rng = SplitMix64(seed: seed)
        for _ in 0..<attempts {
            let result = runOnce(data, dimensions: dimensions, count: count, iterations: iterations, rng: &rng)
            if best == nil || result.compactness < best!.compactness { best = result }
        }
        return best!
    }

    private static func runOnce(_ data: [Float], dimensions: Int, count: Int, iterations: Int, rng: inout SplitMix64) -> Result {
        let n = data.count / dimensions
        precondition(n >= count)
        var centers = [Float](repeating: 0, count: count * dimensions)
        // k-means++: the first centre at random, each next one far from the existing ones.
        var distances = [Float](repeating: .greatestFiniteMagnitude, count: n)
        var first = Int(rng.next() % UInt64(n))
        for k in 0..<count {
            if k > 0 {
                var total = 0.0
                for d in distances { total += Double(d) }
                var pick = rng.nextDouble() * total
                first = n - 1
                for i in 0..<n {
                    pick -= Double(distances[i])
                    if pick <= 0 { first = i; break }
                }
            }
            for d in 0..<dimensions { centers[k * dimensions + d] = data[first * dimensions + d] }
            for i in 0..<n {
                var dist: Float = 0
                for d in 0..<dimensions {
                    let diff = data[i * dimensions + d] - centers[k * dimensions + d]
                    dist += diff * diff
                }
                if dist < distances[i] { distances[i] = dist }
            }
        }
        var labels = [Int](repeating: 0, count: n)
        var compactness = 0.0
        for _ in 0..<iterations {
            compactness = 0
            var sums = [Double](repeating: 0, count: count * dimensions)
            var sizes = [Int](repeating: 0, count: count)
            for i in 0..<n {
                var bestK = 0
                var bestDist = Float.greatestFiniteMagnitude
                for k in 0..<count {
                    var dist: Float = 0
                    for d in 0..<dimensions {
                        let diff = data[i * dimensions + d] - centers[k * dimensions + d]
                        dist += diff * diff
                    }
                    if dist < bestDist { bestDist = dist; bestK = k }
                }
                labels[i] = bestK
                sizes[bestK] += 1
                compactness += Double(bestDist)
                for d in 0..<dimensions { sums[bestK * dimensions + d] += Double(data[i * dimensions + d]) }
            }
            var shift: Float = 0
            for k in 0..<count where sizes[k] > 0 {
                for d in 0..<dimensions {
                    let updated = Float(sums[k * dimensions + d] / Double(sizes[k]))
                    shift += abs(updated - centers[k * dimensions + d])
                    centers[k * dimensions + d] = updated
                }
            }
            if shift < 1e-3 { break }
        }
        return Result(labels: labels, centers: centers, compactness: compactness)
    }
}

/// Small deterministic random generator (SplitMix64).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
