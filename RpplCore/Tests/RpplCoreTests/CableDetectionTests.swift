import Foundation
import Testing
@testable import RpplCore

struct CableDetectionTests {
    private let origin = ParkCoordinate(lat: 52.1, lon: 5.2)

    // MARK: Geometry

    @Test func convexHullDropsInteriorAndCollinearPoints() {
        let hull = Geometry2D.convexHull([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10), SIMD2(5, 5), SIMD2(5, 0)])
        #expect(hull.count == 4)
        #expect(Geometry2D.area(hull) == 100)
        #expect(Geometry2D.turnAnglesDegrees(hull).allSatisfy { abs($0 - 90) < 1e-9 })
    }

    @Test func minimumRectangleFollowsTheLongSide() {
        let angle = 0.6
        let along = SIMD2<Double>(cos(angle), sin(angle))
        let across = SIMD2<Double>(-sin(angle), cos(angle))
        let halfLong = along * 100
        let halfShort = across * 50
        let corners: [SIMD2<Double>] = [-halfLong - halfShort, halfLong - halfShort, halfLong + halfShort, -halfLong + halfShort]
        let sides = Geometry2D.minimumRectangleSides(corners)
        #expect(abs(sides.long - 200) < 1e-6)
        #expect(abs(sides.short - 100) < 1e-6)
    }

    @Test func bowTieIsSelfIntersectingAndSquareIsNot() {
        #expect(Geometry2D.isSelfIntersecting([SIMD2(0, 0), SIMD2(10, 10), SIMD2(10, 0), SIMD2(0, 10)]))
        #expect(!Geometry2D.isSelfIntersecting([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)]))
        #expect(Geometry2D.contains([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)], SIMD2(5, 5)))
        #expect(!Geometry2D.contains([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)], SIMD2(15, 5)))
        #expect(abs(Geometry2D.distanceToRing(SIMD2(5, 13), [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)]) - 3) < 1e-9)
    }

    // MARK: Bitmap

    @Test func bitmapFillsSmallHolesAndKeepsIslands() {
        var bitmap = Bitmap(width: 40, height: 40, fill: true)
        bitmap[5, 5] = false  // a boat
        for y in 20..<30 { for x in 20..<30 { bitmap[x, y] = false } }  // an island of 100 cells
        let filled = bitmap.fillingHoles(maxArea: 10)
        #expect(filled[5, 5])
        #expect(!filled[25, 25])
        #expect(filled.count == 40 * 40 - 100)
        let (labels, sizes) = Bitmap(width: 40, height: 40, bits: filled.bits.map { !$0 }).components()
        #expect(sizes == [100])
        #expect(labels[25 * 40 + 25] == 1)
    }

    @Test func bitmapOpeningRemovesSpecksAndErosionShrinks() {
        var bitmap = Bitmap(width: 20, height: 20)
        for y in 5..<15 { for x in 5..<15 { bitmap[x, y] = true } }
        bitmap[0, 0] = true
        let opened = bitmap.opened()
        #expect(!opened[0, 0])
        #expect(opened.count == 96)  // the cross element does not give the four corners back
        #expect(bitmap.eroded().count == 64)  // 8x8 core; the lone speck erodes
    }

    // MARK: Mast net

    @Test func bundledMastNetMatchesTheTrainedModel() throws {
        let net = try #require(MastNet.bundled)
        #expect(net.parameterCount == 17745)
        // Reference logits printed by tools/cable-tracer/detect/export_mastnet.py.
        let black = [UInt8](repeating: 0, count: 64 * 64 * 3)
        #expect(abs(net.logit(patch: black) - -0.317538) < 2e-3)
        #expect(abs(net.logit(patch: Self.syntheticPatch()) - -35.248455) < 0.05)
    }

    @Test func denseHeatmapMatchesThePythonReference() throws {
        let net = try #require(MastNet.bundled)
        // A 128 px image that is black except for the patch at (32, 32). Reference values from
        // cabledetect.mastheat.dense_logits on the same image (the dense pass sees the biases of the
        // black surroundings, so its cell differs from the lone patch logit by design).
        var rgb = [UInt8](repeating: 0, count: 128 * 128 * 3)
        let patch = Self.syntheticPatch()
        for y in 0..<64 { for x in 0..<64 { for c in 0..<3 { rgb[((y + 32) * 128 + x + 32) * 3 + c] = patch[(y * 64 + x) * 3 + c] } } }
        let image = DetectionImage(width: 128, height: 128, rgb: rgb, metersPerPixel: 0.29, center: origin, origin: origin)
        let heatmap = net.heatmap(of: image)
        #expect(heatmap.width == 5 && heatmap.height == 5)
        #expect(heatmap.logits.allSatisfy { $0.isFinite })
        #expect(abs(heatmap.logits[2 * 5 + 2] - -39.556141) < 0.05)
        // Image-border cells differ a little: the tile's zero halo goes through the convolutions,
        // the reference pads every layer with zeros.
        #expect(abs(heatmap.logits[0] - -11.057) < 0.3)
        #expect(abs(heatmap.logits[4 * 5 + 4] - -18.187) < 0.3)
    }

    @Test func heatmapPeaksAreLocalMaximaStrongestFirst() {
        var logits = [Float](repeating: -3, count: 10 * 10)
        logits[2 * 10 + 2] = 1
        logits[2 * 10 + 3] = 0.5  // shoulder of the first peak
        logits[7 * 10 + 7] = 2
        let heatmap = MastHeatmap(width: 10, height: 10, logits: logits)
        let peaks = heatmap.peaks(probability: 0.5, minimumSeparationCells: 2)
        #expect(peaks.count == 2)
        #expect(peaks[0].column == 7 * 16 + 32 && peaks[0].row == 7 * 16 + 32)
        #expect(abs(peaks[0].probability - 1 / (1 + exp(-2.0))) < 1e-9)
        #expect(peaks[1].column == 2 * 16 + 32)
        #expect(abs(heatmap.probability(nearColumn: 2 * 16 + 32 + 6, row: 2 * 16 + 32) - 1 / (1 + exp(-1.0))) < 1e-9)
    }

    // MARK: Loop fitting

    private let pentagon: [SIMD2<Double>] = [SIMD2(-120, -40), SIMD2(0, -70), SIMD2(120, -40), SIMD2(90, 60), SIMD2(-90, 60)]

    @Test func loopFitterRecoversAPentagonFromItsMasts() throws {
        let fitter = LoopFitter(isWater: { _ in true })
        var evidence = pentagon.map { LoopFitter.Evidence(xy: $0, weight: 4) }
        evidence.append(LoopFitter.Evidence(xy: SIMD2(100, 10), weight: 1))  // an obstacle on an edge
        let candidates = fitter.propose(evidence: evidence)
        let best = try #require(candidates.first)
        #expect(best.vertices.count == 5)
        for corner in pentagon {
            let nearest = best.vertices.map { vectorLength($0 - corner) }.min() ?? .infinity
            #expect(nearest < 10, "corner \(corner) missed by \(nearest) m")
        }
        #expect(best.notes.isEmpty)
    }

    @Test func impossibleCornerIsPenalisedAndDropped() {
        let fitter = LoopFitter(isWater: { _ in true })
        let knee: [SIMD2<Double>] = [SIMD2(-100, -50), SIMD2(100, -50), SIMD2(100, 50), SIMD2(0, 80), SIMD2(-100, 50)]  // 33 degrees
        let sharp: [SIMD2<Double>] = [SIMD2(-100, -50), SIMD2(100, -50), SIMD2(100, 50), SIMD2(0, 300), SIMD2(-100, 50)]  // 136 degrees
        let evidence = knee.map { LoopFitter.Evidence(xy: $0, weight: 4) }
        let scored = fitter.score(sharp, evidence: evidence)
        #expect(scored.notes.contains { $0.hasPrefix("corner of") })
        #expect(LoopFitter.sharpestVertex(sharp) == 3)
        #expect(LoopFitter.sharpestVertex(knee) == nil)
    }

    // MARK: End to end on a synthetic lake

    @Test func detectorFindsTheLoopOnASyntheticLake() throws {
        let image = Self.syntheticLake(masts: pentagon)
        let water = WaterSegmenter().segment(image)
        #expect(abs(water.fraction - 0.33) < 0.06, "water fraction \(water.fraction)")
        var options = CableDetector.Options()
        options.useMastNet = false  // the net is tested on its own; keeps this test fast in debug builds
        let result = CableDetector.detect(in: image, options: options)
        #expect(result.objects.count >= 5)
        let best = try #require(result.best, "notes: \(result.notes)")
        #expect((4...6).contains(best.vertices.count))
        for corner in pentagon {
            let nearest = best.vertices.map { vectorLength($0 - corner) }.min() ?? .infinity
            #expect(nearest < 15, "corner \(corner) missed by \(nearest) m")
        }
        #expect(best.waterFraction > 0.97)

        let cable = CableDetector.cable(from: best, in: image, direction: .clockwise)
        #expect(cable.tracedWindingIsClockwise == true)
        #expect(cable.points?.count == best.vertices.count)
        let first = try #require(cable.points?.first)
        let firstXY = image.localXY(of: first.coordinate)
        #expect(best.vertices.allSatisfy { vectorLength($0) >= vectorLength(firstXY) - 1e-6 })
    }

    @Test func pixelAndLocalFramesRoundTrip() {
        let image = DetectionImage(width: 100, height: 80, rgb: [UInt8](repeating: 0, count: 100 * 80 * 3), metersPerPixel: 0.5, center: ParkCoordinate(lat: 52.1005, lon: 5.2), origin: origin)
        let xy = SIMD2(12.0, -7.0)
        let pixel = image.pixel(fromLocal: xy)
        let back = image.local(fromPixelColumn: pixel.x, row: pixel.y)
        #expect(vectorLength(back - xy) < 1e-9)
        let coordinate = image.coordinate(fromLocal: xy)
        #expect(vectorLength(image.localXY(of: coordinate) - xy) < 1e-6)
        #expect(abs(image.localXY(of: image.center).y - 55.3) < 0.1)
    }

    // MARK: Fixtures

    /// Deterministic pattern shared with export_mastnet.py.
    static func syntheticPatch() -> [UInt8] {
        var patch = [UInt8](repeating: 0, count: 64 * 64 * 3)
        for y in 0..<64 { for x in 0..<64 { for c in 0..<3 { patch[(y * 64 + x) * 3 + c] = UInt8((x * 7 + y * 13 + c * 31 + (x * y) % 17) % 256) } } }
        return patch
    }

    /// 600 x 600 px at 1 m/px: a dark lake (400 x 300 m) in land made of several colours, bright
    /// 4 x 4 m platforms just outside each mast position and two obstacles on the long edges.
    static func syntheticLake(masts: [SIMD2<Double>]) -> DetectionImage {
        let size = 600
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        var rng = SplitMix64(seed: 42)
        let landColours: [SIMD3<Int>] = [SIMD3(70, 130, 60), SIMD3(150, 140, 120), SIMD3(110, 90, 60), SIMD3(200, 200, 195), SIMD3(70, 95, 40)]
        func put(_ x: Int, _ y: Int, _ colour: SIMD3<Int>, noise: Int) {
            let base = (y * size + x) * 3
            for c in 0..<3 {
                let n = Int(rng.next() % UInt64(2 * noise + 1)) - noise
                rgb[base + c] = UInt8(min(max(colour[c] + n, 0), 255))
            }
        }
        for y in 0..<size {
            for x in 0..<size {
                let inLake = x >= 100 && x < 500 && y >= 150 && y < 450
                if inLake {
                    put(x, y, SIMD3(40, 55, 70), noise: 3)
                } else {
                    put(x, y, landColours[((x / 50) * 7 + (y / 50) * 3) % landColours.count], noise: 12)
                }
            }
        }
        let origin = ParkCoordinate(lat: 52.1, lon: 5.2)
        let image = DetectionImage(width: size, height: size, rgb: rgb, metersPerPixel: 1, center: origin, origin: origin)
        var bright = rgb
        func platform(at xy: SIMD2<Double>, width: Int, height: Int) {
            let pixel = image.pixel(fromLocal: xy)
            for dy in 0..<height { for dx in 0..<width {
                let x = Int(pixel.x) - width / 2 + dx, y = Int(pixel.y) - height / 2 + dy
                let base = (y * size + x) * 3
                bright[base] = 210; bright[base + 1] = 205; bright[base + 2] = 200
            } }
        }
        let centroid = masts.reduce(SIMD2<Double>(0, 0), +) / Double(masts.count)
        for mast in masts {
            let outward = mast - centroid
            platform(at: mast + outward / vectorLength(outward) * 3, width: 4, height: 4)
        }
        platform(at: (masts[0] + masts[1]) / 2, width: 2, height: 6)
        platform(at: (masts[3] + masts[4]) / 2, width: 6, height: 2)
        return DetectionImage(width: size, height: size, rgb: bright, metersPerPixel: 1, center: origin, origin: origin)
    }
}
