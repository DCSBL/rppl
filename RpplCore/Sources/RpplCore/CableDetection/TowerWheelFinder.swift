import Foundation

/// Puts a tower guess on the tower's wheel, where the cable wraps around it. The coarse net's peak
/// often lands on the arm or the platform, a few metres off (median 5.6 m on held-out parks); the
/// reviewer then has to drag the map. This net looks at the same input as `TowerCloseupCheck` (the
/// 48 m around the guess at 0.25 m/px, 192 px) and gives a probability per 2 m cell, averaged over
/// the eight rotations and mirror images. The wheel is the probability-weighted mean of the 3 x 3
/// cells around the most likely cell under a 12 m Gaussian around the guess (a far peak is usually
/// another tower). Held out by park it brings the median distance to the wheel from 5.6 to 0.7 m
/// (81% within 2 m); trained in tools/cable-tracer/detect/cabledetect/wheelfind.py.
public struct TowerWheelFinder: Sendable {
    static let pooledLayers = 3
    static let cellPixels = 8
    static let priorCells = 6.0

    let net: TowerNet

    /// Weights bundled with RpplCore; nil when the resource is missing or malformed.
    public static let bundled: TowerWheelFinder? = {
        guard let url = Bundle.module.url(forResource: "TowerWheelFinder", withExtension: "weights"),
              let net = try? TowerNet(contentsOf: url) else { return nil }
        return TowerWheelFinder(net: net)
    }()

    /// Where the wheel is on a close-up centred on a guess (from `CableDetectionRunner.closeup`,
    /// as fetched or as the review keeps it).
    public func wheel(in closeup: DetectionImage) -> ParkCoordinate {
        let offset = Self.peak(in: heatmap(TowerCloseupCheck.input(from: closeup)))
        let guess = closeup.controlPoints.count == 9 ? closeup.controlPoints[4].coordinate : closeup.origin
        let meters = TowerCloseupCheck.metersPerPixel
        // Input x runs east and y south, both at 0.25 m per pixel.
        return DetectionImage.coordinate(fromLocal: SIMD2(offset.x * meters, -offset.y * meters), origin: guess)
    }

    /// Cell probabilities, row-major, cells a side = input / 8: the softmax of each of the eight
    /// views, turned back and averaged.
    func heatmap(_ input: [Float]) -> [Double] {
        let size = TowerCloseupCheck.inputPixels
        let cells = size / Self.cellPixels
        var total = [Double](repeating: 0, count: cells * cells)
        for mirrored in [false, true] {
            for turns in 0..<4 {
                let view = TowerCloseupCheck.transformed(input, size: size, turns: turns, mirrored: mirrored)
                let logits = net.cellLogits(input: view, size: size, pooledLayers: Self.pooledLayers)
                let largest = Double(logits.max() ?? 0)
                let exps = logits.map { exp(Double($0) - largest) }
                let sum = exps.reduce(0, +)
                for y in 0..<cells {
                    for x in 0..<cells {
                        // View cell (x, y) shows the original cell `transformed` takes it from.
                        var sx = mirrored ? cells - 1 - x : x, sy = y
                        for _ in 0..<turns { (sx, sy) = (sy, cells - 1 - sx) }
                        total[sy * cells + sx] += exps[y * cells + x] / sum / 8
                    }
                }
            }
        }
        return total
    }

    /// Offset of the wheel from the middle of the input in input pixels (x right, y down).
    static func peak(in heatmap: [Double]) -> SIMD2<Double> {
        let cells = Int(Double(heatmap.count).squareRoot())
        let half = Double(cells) / 2
        var best = 0, bestValue = -1.0
        for index in heatmap.indices {
            let dx = Double(index % cells) + 0.5 - half, dy = Double(index / cells) + 0.5 - half
            let value = heatmap[index] * exp(-0.5 * (dx * dx + dy * dy) / (priorCells * priorCells))
            if value > bestValue { bestValue = value; best = index }
        }
        let row = best / cells, column = best % cells
        var weight = 0.0, sumX = 0.0, sumY = 0.0
        for y in max(row - 1, 0)...min(row + 1, cells - 1) {
            for x in max(column - 1, 0)...min(column + 1, cells - 1) {
                let w = heatmap[y * cells + x]
                weight += w
                sumX += w * Double(x)
                sumY += w * Double(y)
            }
        }
        let cell = Double(cellPixels)
        return SIMD2((sumX / weight + 0.5 - half) * cell, (sumY / weight + 0.5 - half) * cell)
    }
}
