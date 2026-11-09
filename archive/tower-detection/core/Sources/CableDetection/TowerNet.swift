import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Tiny convolutional classifier that says whether a 64 px (about 19 m at 0.29 m/px) patch of
/// satellite imagery is centred on a cable tower. Four 3x3 convolutions, each followed by 2x2 max
/// pooling, a global mean and one linear unit: about 18k weights, trained on the hand-traced bends
/// of the bundled parks (see tools/cable-tracer/detect). Run fully convolutionally it yields a tower
/// heatmap with one cell per 16 px.
public struct TowerNet: Sendable {
    struct ConvLayer: Sendable {
        let inChannels: Int
        let outChannels: Int
        /// Row-major [tap (dy * 3 + dx)][in][out].
        let weights: [Float]
        let bias: [Float]
    }

    public static let patchSize = 64
    public static let heatmapStride = 16

    let convs: [ConvLayer]
    let linearWeights: [Float]
    let linearBias: Float

    public var parameterCount: Int {
        convs.reduce(0) { $0 + $1.weights.count + $1.bias.count } + linearWeights.count + 1
    }

    // MARK: Loading

    /// Weights bundled with RpplCore; nil when the resource is missing or malformed.
    public static let bundled: TowerNet? = {
        guard let url = Bundle.module.url(forResource: "TowerNet", withExtension: "weights") else { return nil }
        return try? TowerNet(contentsOf: url)
    }()

    public enum LoadError: Error { case badFormat }

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// Format: "RPMN", UInt32 version (1), UInt32 conv count, then per conv UInt32 in, UInt32 out,
    /// Float32 weights [3][3][in][out], Float32 bias [out]; then UInt32 in, UInt32 out (1), Float32
    /// weights [in][out], Float32 bias [out]. Little-endian throughout.
    public init(data: Data) throws {
        var reader = ByteReader(data: data)
        guard try reader.bytes(4) == [0x52, 0x50, 0x4D, 0x4E], try reader.uint32() == 1 else { throw LoadError.badFormat }
        let convCount = Int(try reader.uint32())
        guard (1...16).contains(convCount) else { throw LoadError.badFormat }
        var convs: [ConvLayer] = []
        for _ in 0..<convCount {
            let inChannels = Int(try reader.uint32()), outChannels = Int(try reader.uint32())
            guard (1...512).contains(inChannels), (1...512).contains(outChannels) else { throw LoadError.badFormat }
            let weights = try reader.floats(9 * inChannels * outChannels)
            let bias = try reader.floats(outChannels)
            convs.append(ConvLayer(inChannels: inChannels, outChannels: outChannels, weights: weights, bias: bias))
        }
        let linearIn = Int(try reader.uint32()), linearOut = Int(try reader.uint32())
        guard linearIn == convs.last?.outChannels, linearOut == 1 else { throw LoadError.badFormat }
        linearWeights = try reader.floats(linearIn)
        linearBias = try reader.floats(1)[0]
        self.convs = convs
    }

    // MARK: Inference

    /// Logit for one 64 x 64 RGB patch (row-major, 3 bytes per pixel); probability = sigmoid(logit).
    public func logit(patch: [UInt8]) -> Float {
        precondition(patch.count == Self.patchSize * Self.patchSize * 3)
        let input = patch.map { Float($0) / 255 }
        let features = backbone(input, width: Self.patchSize, height: Self.patchSize)
        let pooled = Self.averagePool(features.values, width: features.width, height: features.height, channels: features.channels, window: features.width)
        return linear(pooled.values)[0]
    }

    /// Logit for one square input that is already scaled (row-major RGB floats, `size` x `size`):
    /// the same layers as `logit(patch:)` without the /255, for nets trained on standardised
    /// input such as `TowerCloseupCheck`.
    func logit(input: [Float], size: Int) -> Float {
        precondition(input.count == size * size * 3)
        let features = backbone(input, width: size, height: size)
        let pooled = Self.averagePool(features.values, width: features.width, height: features.height, channels: features.channels, window: features.width)
        return linear(pooled.values)[0]
    }

    /// One logit per cell for a square scaled input, for nets that end in a per-cell linear unit
    /// instead of a global mean (`TowerWheelFinder`): only the first `pooledLayers` convolutions pool,
    /// so a cell is 2^pooledLayers input pixels. Row-major, `size >> pooledLayers` cells a side.
    func cellLogits(input: [Float], size: Int, pooledLayers: Int) -> [Float] {
        precondition(input.count == size * size * 3)
        let features = backbone(input, width: size, height: size, pooledLayers: pooledLayers)
        return linear(features.values)
    }

    /// Tower heatmap over the whole image. Cell (row, column) scores the patch whose top-left pixel
    /// is (16 row, 16 column). Tiles without water (when a mask is given) are skipped and stay at -inf.
    func heatmap(of image: DetectionImage, water: WaterSegmenter.Mask? = nil) -> TowerHeatmap {
        let patch = Self.patchSize, step = Self.heatmapStride
        let cellsWide = max(0, image.width / step - patch / step + 1)
        let cellsHigh = max(0, image.height / step - patch / step + 1)
        var logits = [Float](repeating: -.infinity, count: cellsWide * cellsHigh)
        guard cellsWide > 0, cellsHigh > 0 else { return TowerHeatmap(width: cellsWide, height: cellsHigh, logits: logits) }

        // Tiles of `core` output pixels with a halo wide enough for the receptive field.
        let halo = 64
        let core = min(512, ((max(image.width, image.height) + 15) / 16) * 16)
        let tileSize = core + 2 * halo
        var tile = [Float](repeating: 0, count: tileSize * tileSize * 3)
        for tileRow in Swift.stride(from: 0, to: image.height, by: core) {
            for tileColumn in Swift.stride(from: 0, to: image.width, by: core) {
                if let water, !Self.hasWater(water, rows: tileRow..<min(tileRow + core, image.height), columns: tileColumn..<min(tileColumn + core, image.width)) {
                    continue
                }
                Self.fill(&tile, size: tileSize, from: image, topRow: tileRow - halo, leftColumn: tileColumn - halo)
                let features = backbone(tile, width: tileSize, height: tileSize)
                let pooled = Self.averagePool(features.values, width: features.width, height: features.height, channels: features.channels, window: patch / step)
                let tileLogits = linear(pooled.values)
                // Local cell (i, j) has its patch top-left at tile pixel (16 i, 16 j) = image pixel (tileRow - halo + 16 i, ...).
                for i in 0..<pooled.height {
                    let top = tileRow - halo + i * step
                    guard top >= tileRow, top < tileRow + core, top + patch <= image.height else { continue }
                    for j in 0..<pooled.width {
                        let left = tileColumn - halo + j * step
                        guard left >= tileColumn, left < tileColumn + core, left + patch <= image.width else { continue }
                        logits[(top / step) * cellsWide + left / step] = tileLogits[i * pooled.width + j]
                    }
                }
            }
        }
        return TowerHeatmap(width: cellsWide, height: cellsHigh, logits: logits)
    }

    private static func hasWater(_ water: WaterSegmenter.Mask, rows: Range<Int>, columns: Range<Int>) -> Bool {
        for row in Swift.stride(from: rows.lowerBound, to: rows.upperBound, by: water.factor) {
            for column in Swift.stride(from: columns.lowerBound, to: columns.upperBound, by: water.factor) where water.isWater(column: column, row: row) {
                return true
            }
        }
        return false
    }

    private static func fill(_ tile: inout [Float], size: Int, from image: DetectionImage, topRow: Int, leftColumn: Int) {
        for y in 0..<size {
            let row = topRow + y
            for x in 0..<size {
                let column = leftColumn + x
                let base = (y * size + x) * 3
                if row >= 0, row < image.height, column >= 0, column < image.width {
                    let source = (row * image.width + column) * 3
                    tile[base] = Float(image.rgb[source]) / 255
                    tile[base + 1] = Float(image.rgb[source + 1]) / 255
                    tile[base + 2] = Float(image.rgb[source + 2]) / 255
                } else {
                    tile[base] = 0; tile[base + 1] = 0; tile[base + 2] = 0
                }
            }
        }
    }

    private struct FeatureMap {
        var values: [Float]
        var width: Int
        var height: Int
        var channels: Int
    }

    /// Convolutions with ReLU; the first `pooledLayers` (all by default) are followed by 2x2 max pooling.
    private func backbone(_ input: [Float], width: Int, height: Int, pooledLayers: Int = .max) -> FeatureMap {
        var current = FeatureMap(values: input, width: width, height: height, channels: 3)
        for (index, layer) in convs.enumerated() {
            current.values = Self.convolve(current.values, width: current.width, height: current.height, layer: layer)
            current.channels = layer.outChannels
            if index < pooledLayers { current = Self.maxPool(current) }
        }
        return current
    }

    private func linear(_ pooled: [Float]) -> [Float] {
        let channels = linearWeights.count
        let count = pooled.count / channels
        var out = [Float](repeating: linearBias, count: count)
        for i in 0..<count {
            var sum: Float = 0
            for c in 0..<channels { sum += pooled[i * channels + c] * linearWeights[c] }
            out[i] += sum
        }
        return out
    }

    /// 3x3 convolution, "same" zero padding, followed by ReLU. Input and output are [H][W][C].
    static func convolve(_ input: [Float], width: Int, height: Int, layer: ConvLayer) -> [Float] {
        let cin = layer.inChannels, cout = layer.outChannels
        let inner = 9 * cin
        var output = [Float](repeating: 0, count: width * height * cout)
        // One image row at a time: gather the 3x3 neighbourhoods (im2col), multiply by the weights.
        var patches = [Float](repeating: 0, count: width * inner)
        var rowOut = [Float](repeating: 0, count: width * cout)
        input.withUnsafeBufferPointer { source in
            for y in 0..<height {
                patches.withUnsafeMutableBufferPointer { patchBuffer in
                    for x in 0..<width {
                        var offset = x * inner
                        for dy in -1...1 {
                            let sy = y + dy
                            for dx in -1...1 {
                                let sx = x + dx
                                if sy >= 0, sy < height, sx >= 0, sx < width {
                                    let base = (sy * width + sx) * cin
                                    for c in 0..<cin { patchBuffer[offset + c] = source[base + c] }
                                } else {
                                    for c in 0..<cin { patchBuffer[offset + c] = 0 }
                                }
                                offset += cin
                            }
                        }
                    }
                }
                matmul(patches, rows: width, inner: inner, layer.weights, columns: cout, into: &rowOut)
                output.withUnsafeMutableBufferPointer { outBuffer in
                    let rowBase = y * width * cout
                    for i in 0..<width {
                        for c in 0..<cout {
                            outBuffer[rowBase + i * cout + c] = max(rowOut[i * cout + c] + layer.bias[c], 0)
                        }
                    }
                }
            }
        }
        return output
    }

    /// C (rows x columns) = A (rows x inner) * B (inner x columns), all row-major.
    static func matmul(_ a: [Float], rows: Int, inner: Int, _ b: [Float], columns: Int, into c: inout [Float]) {
        #if canImport(Accelerate)
        vDSP_mmul(a, 1, b, 1, &c, 1, vDSP_Length(rows), vDSP_Length(columns), vDSP_Length(inner))
        #else
        a.withUnsafeBufferPointer { aBuffer in
            b.withUnsafeBufferPointer { bBuffer in
                c.withUnsafeMutableBufferPointer { cBuffer in
                    for i in 0..<rows {
                        let cRow = i * columns
                        for j in 0..<columns { cBuffer[cRow + j] = 0 }
                        for k in 0..<inner {
                            let aValue = aBuffer[i * inner + k]
                            if aValue == 0 { continue }
                            let bRow = k * columns
                            for j in 0..<columns { cBuffer[cRow + j] += aValue * bBuffer[bRow + j] }
                        }
                    }
                }
            }
        }
        #endif
    }

    private static func maxPool(_ map: FeatureMap) -> FeatureMap {
        let width = map.width / 2, height = map.height / 2, channels = map.channels
        var out = [Float](repeating: 0, count: width * height * channels)
        map.values.withUnsafeBufferPointer { source in
            for y in 0..<height {
                for x in 0..<width {
                    let a = ((2 * y) * map.width + 2 * x) * channels
                    let b = a + channels
                    let c = a + map.width * channels
                    let d = c + channels
                    let o = (y * width + x) * channels
                    for ch in 0..<channels {
                        out[o + ch] = max(max(source[a + ch], source[b + ch]), max(source[c + ch], source[d + ch]))
                    }
                }
            }
        }
        return FeatureMap(values: out, width: width, height: height, channels: channels)
    }

    /// Mean over a `window` x `window` box, stride 1, no padding.
    private static func averagePool(_ values: [Float], width: Int, height: Int, channels: Int, window: Int) -> FeatureMap {
        let outWidth = max(0, width - window + 1), outHeight = max(0, height - window + 1)
        // Horizontal running sums, then vertical.
        var horizontal = [Float](repeating: 0, count: outWidth * height * channels)
        for y in 0..<height {
            for x in 0..<outWidth {
                for ch in 0..<channels {
                    var sum: Float = 0
                    for k in 0..<window { sum += values[(y * width + x + k) * channels + ch] }
                    horizontal[(y * outWidth + x) * channels + ch] = sum
                }
            }
        }
        var out = [Float](repeating: 0, count: outWidth * outHeight * channels)
        let norm = 1 / Float(window * window)
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                for ch in 0..<channels {
                    var sum: Float = 0
                    for k in 0..<window { sum += horizontal[((y + k) * outWidth + x) * channels + ch] }
                    out[(y * outWidth + x) * channels + ch] = sum * norm
                }
            }
        }
        return FeatureMap(values: out, width: outWidth, height: outHeight, channels: channels)
    }
}

/// Tower probabilities on a grid of `TowerNet.heatmapStride` pixels.
public struct TowerHeatmap: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major logits; -inf where nothing was computed.
    public let logits: [Float]

    public struct Peak: Sendable, Equatable {
        /// Pixel position of the patch centre.
        public var column: Double
        public var row: Double
        public var probability: Double
    }

    /// Local maxima above `probability`, at least `minimumSeparationCells` apart, strongest first.
    public func peaks(probability: Double = 0.5, minimumSeparationCells: Int = 2) -> [Peak] {
        let threshold = Float(log(probability / (1 - probability)))
        var peaks: [Peak] = []
        for i in 0..<height {
            for j in 0..<width {
                let value = logits[i * width + j]
                guard value > threshold else { continue }
                var isMax = true
                search: for di in -minimumSeparationCells...minimumSeparationCells {
                    let ni = i + di
                    guard ni >= 0, ni < height else { continue }
                    for dj in -minimumSeparationCells...minimumSeparationCells where di != 0 || dj != 0 {
                        let nj = j + dj
                        guard nj >= 0, nj < width else { continue }
                        let other = logits[ni * width + nj]
                        // Ties go to the earlier cell so one plateau gives one peak.
                        if other > value || (other == value && (di < 0 || (di == 0 && dj < 0))) { isMax = false; break search }
                    }
                }
                if isMax {
                    let half = Double(TowerNet.patchSize) / 2
                    peaks.append(Peak(
                        column: Double(j * TowerNet.heatmapStride) + half,
                        row: Double(i * TowerNet.heatmapStride) + half,
                        probability: 1 / (1 + exp(-Double(value)))
                    ))
                }
            }
        }
        return peaks.sorted { $0.probability > $1.probability }
    }

    /// Highest probability within `radiusCells` of a pixel position; 0 where nothing was computed.
    public func probability(nearColumn column: Double, row: Double, radiusCells: Int = 1) -> Double {
        let half = Double(TowerNet.patchSize) / 2
        let j = Int(((column - half) / Double(TowerNet.heatmapStride)).rounded())
        let i = Int(((row - half) / Double(TowerNet.heatmapStride)).rounded())
        var best = -Float.infinity
        for di in -radiusCells...radiusCells {
            for dj in -radiusCells...radiusCells {
                let ni = i + di, nj = j + dj
                guard ni >= 0, ni < height, nj >= 0, nj < width else { continue }
                best = max(best, logits[ni * width + nj])
            }
        }
        return best.isFinite ? 1 / (1 + exp(-Double(best))) : 0
    }
}

/// Sequential little-endian reader for the weights file.
struct ByteReader {
    let data: Data
    private var offset = 0

    init(data: Data) { self.data = data }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw TowerNet.LoadError.badFormat }
        defer { offset += count }
        return Array(data[(data.startIndex + offset)..<(data.startIndex + offset + count)])
    }

    mutating func uint32() throws -> UInt32 {
        let b = try bytes(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func floats(_ count: Int) throws -> [Float] {
        let raw = try bytes(count * 4)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let bits = UInt32(raw[i * 4]) | UInt32(raw[i * 4 + 1]) << 8 | UInt32(raw[i * 4 + 2]) << 16 | UInt32(raw[i * 4 + 3]) << 24
            out[i] = Float(bitPattern: bits)
        }
        return out
    }
}
