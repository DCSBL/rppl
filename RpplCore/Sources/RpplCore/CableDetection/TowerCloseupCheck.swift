import Foundation

/// Second look at a tower guess on a zoomed close-up: 40 m around the guess at 5 cm/px (a 768 px
/// MapKit snapshot), where the wheel, the arm and the cable are sharp. The image is averaged down to
/// 256 px (0.156 m/px), the middle 192 px (30 m) are standardised per channel so the water's colour
/// does not matter, and a small CNN (`TowerNet` layers, five convolutions) scores it in all eight
/// rotations and mirror images. Trained and checked with parks held out in
/// tools/cable-tracer/detect/cabledetect/closeupcheck.py.
public struct TowerCloseupCheck: Sendable {
    public static let closeupMeters = 40.0
    public static let closeupPixels = 768
    static let storedPixels = 256
    static let inputPixels = 192

    let net: TowerNet

    /// Weights bundled with RpplCore; nil when the resource is missing or malformed.
    public static let bundled: TowerCloseupCheck? = {
        guard let url = Bundle.module.url(forResource: "TowerCloseupCheck", withExtension: "weights"),
              let net = try? TowerNet(contentsOf: url) else { return nil }
        return TowerCloseupCheck(net: net)
    }()

    init(net: TowerNet) {
        self.net = net
    }

    /// Probability that a tower stands at the centre of `closeup` (768 or 256 px square).
    public func score(_ closeup: DetectionImage) -> Double {
        let input = Self.input(from: closeup)
        let size = Self.inputPixels
        var total = 0.0
        for mirrored in [false, true] {
            for turns in 0..<4 {
                let view = Self.transformed(input, size: size, turns: turns, mirrored: mirrored)
                total += 1 / (1 + exp(-Double(net.logit(input: view, size: size))))
            }
        }
        return total / 8
    }

    /// The close-up as the net sees it: 256 px, the middle 192 px, each channel to zero mean and
    /// unit spread (plus 0.02), times 0.15.
    static func input(from closeup: DetectionImage) -> [Float] {
        let stored = closeup.width > storedPixels ? closeup.downsampled(by: closeup.width / storedPixels) : closeup
        precondition(stored.width >= storedPixels && stored.height >= storedPixels, "close-up must be at least 256 px")
        let size = inputPixels, offset = (storedPixels - inputPixels) / 2
        var values = [Float](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                for c in 0..<3 {
                    values[(y * size + x) * 3 + c] = Float(stored.rgb[((y + offset) * stored.width + x + offset) * 3 + c]) / 255
                }
            }
        }
        let pixels = Float(size * size)
        for c in 0..<3 {
            var mean: Float = 0
            for i in 0..<(size * size) { mean += values[i * 3 + c] }
            mean /= pixels
            var variance: Float = 0
            for i in 0..<(size * size) { let d = values[i * 3 + c] - mean; variance += d * d }
            let spread = (variance / pixels).squareRoot() + 0.02
            for i in 0..<(size * size) { values[i * 3 + c] = (values[i * 3 + c] - mean) / spread * 0.15 }
        }
        return values
    }

    /// Quarter turns and an optional mirror of a square RGB map.
    static func transformed(_ values: [Float], size: Int, turns: Int, mirrored: Bool) -> [Float] {
        guard turns % 4 != 0 || mirrored else { return values }
        var out = [Float](repeating: 0, count: values.count)
        for y in 0..<size {
            for x in 0..<size {
                var sx = mirrored ? size - 1 - x : x, sy = y
                for _ in 0..<(turns % 4) { (sx, sy) = (sy, size - 1 - sx) }
                let from = (sy * size + sx) * 3, to = (y * size + x) * 3
                out[to] = values[from]; out[to + 1] = values[from + 1]; out[to + 2] = values[from + 2]
            }
        }
        return out
    }
}
