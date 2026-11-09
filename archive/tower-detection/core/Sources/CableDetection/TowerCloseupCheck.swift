import Foundation

/// Second look at a tower guess on a zoomed close-up, where the wheel, the arm and the cable are
/// sharp. The app asks MapKit for 40 m around the guess, but MapKit stops zooming at about 70 m and
/// 6 cm/px (a little different per park), so the input is defined in metres: the close-up is averaged
/// over whole pixel blocks to about 0.25 m/px, then the 48 m around the guess are resampled to exactly
/// 0.25 m/px (192 px), standardised per channel so the water's colour does not matter, and a small CNN
/// (`TowerNet` layers, five convolutions) scores it in all eight rotations and mirror images. Trained
/// and checked with parks held out in tools/cable-tracer/detect/cabledetect/closeupcheck.py.
public struct TowerCloseupCheck: Sendable {
    public static let closeupMeters = 40.0
    public static let closeupPixels = 768
    static let metersPerPixel = 0.25
    static let inputPixels = 192

    let net: TowerNet

    /// Weights bundled with RpplCore; nil when the resource is missing or malformed.
    public static let bundled: TowerCloseupCheck? = {
        guard let url = Bundle.module.url(forResource: "TowerCloseupCheck", withExtension: "weights"),
              let net = try? TowerNet(contentsOf: url) else { return nil }
        return TowerCloseupCheck(net: net)
    }()

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

    /// Whole pixel blocks that bring a close-up nearest to 0.25 m/px (4 for MapKit's 6 cm/px). The
    /// review stores close-ups averaged by this, so a stored one gives the same input as the original.
    public static func blockFactor(for closeup: DetectionImage) -> Int {
        max(1, Int((metersPerPixel / closeup.metersPerPixel).rounded()))
    }

    /// The close-up as the net sees it: block-averaged, the 48 m around the guess (where MapKit drew
    /// the middle control point, else the frame's origin) bilinearly at 0.25 m/px, rounded to whole
    /// levels, each channel to zero mean and unit spread (plus 0.02), times 0.15.
    static func input(from closeup: DetectionImage) -> [Float] {
        let factor = blockFactor(for: closeup)
        let image = factor > 1 ? closeup.scaledDown(by: factor) : closeup
        let guess: SIMD2<Double>
        if image.controlPoints.count == 9 {
            guess = SIMD2(image.controlPoints[4].column, image.controlPoints[4].row)
        } else {
            guess = image.pixel(fromLocal: SIMD2(0, 0))
        }
        let size = inputPixels
        let step = metersPerPixel / image.metersPerPixel
        let maxU = Double(image.width - 1), maxV = Double(image.height - 1)
        var values = [Float](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            let offsetY: Double = (Double(y) + 0.5 - Double(size) / 2) * step
            let v = min(max(guess.y + offsetY - 0.5, 0), maxV)
            let v0 = min(Int(v.rounded(.down)), image.height - 2)
            let fv = Float(v - Double(v0))
            for x in 0..<size {
                let offsetX: Double = (Double(x) + 0.5 - Double(size) / 2) * step
                let u = min(max(guess.x + offsetX - 0.5, 0), maxU)
                let u0 = min(Int(u.rounded(.down)), image.width - 2)
                let fu = Float(u - Double(u0))
                let topLeft = (v0 * image.width + u0) * 3
                let bottomLeft = topLeft + image.width * 3
                for c in 0..<3 {
                    let a = Float(image.rgb[topLeft + c]), b = Float(image.rgb[topLeft + 3 + c])
                    let d = Float(image.rgb[bottomLeft + c]), e = Float(image.rgb[bottomLeft + 3 + c])
                    let top: Float = a * (1 - fu) + b * fu
                    let bottom: Float = d * (1 - fu) + e * fu
                    let level: Float = (top * (1 - fv) + bottom * fv + 0.5).rounded(.down)
                    values[(y * size + x) * 3 + c] = min(max(level, 0), 255) / 255
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
