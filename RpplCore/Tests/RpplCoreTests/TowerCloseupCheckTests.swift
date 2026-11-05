import Foundation
import Testing
@testable import RpplCore

struct TowerCloseupCheckTests {
    private let origin = ParkCoordinate(lat: 52.3581295, lon: 5.2152087)

    /// The pattern export_closeupcheck.py scores: a close-up as MapKit returns it (1152 px at
    /// 6.25 cm/px), with the guess drawn at (560, 590), a little off the middle.
    static func syntheticCloseup(origin: ParkCoordinate) -> DetectionImage {
        let size = 1152
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                for c in 0..<3 {
                    let value: Int = (x * 7 + y * 13 + c * 31 + (x * y) % 17) % 256
                    rgb[(y * size + x) * 3 + c] = UInt8(value)
                }
            }
        }
        var image = DetectionImage(width: size, height: size, rgb: rgb, metersPerPixel: 0.0625, center: origin, origin: origin)
        image.controlPoints = (0..<9).map { index in
            let column: Double = index == 4 ? 560 : Double(index % 3) * 500 + 76
            let row: Double = index == 4 ? 590 : Double(index / 3) * 500 + 76
            return DetectionImage.ControlPoint(coordinate: origin, column: column, row: row)
        }
        return image
    }

    @Test func downsamplingAveragesBlocksAndKeepsTheFrame() {
        // 6 x 6, channel value = column: each 3 x 3 block averages to its middle column.
        var rgb = [UInt8](repeating: 0, count: 6 * 6 * 3)
        for y in 0..<6 { for x in 0..<6 { for c in 0..<3 { rgb[(y * 6 + x) * 3 + c] = UInt8(x * 10 + c) } } }
        var image = DetectionImage(width: 6, height: 6, rgb: rgb, metersPerPixel: 0.05, center: origin, origin: origin)
        image.controlPoints = [DetectionImage.ControlPoint(coordinate: origin, column: 3, row: 3)]
        let small = image.scaledDown(by: 3)
        #expect(small.width == 2 && small.height == 2)
        #expect(Array(small.rgb[0..<6]) == [10, 11, 12, 40, 41, 42])
        #expect(abs(small.metersPerPixel - 0.15) < 1e-12)
        #expect(small.center == image.center)
        #expect(small.controlPoints.first?.column == 1)
        #expect(image.scaledDown(by: 1).rgb == image.rgb)
    }

    @Test func eightViewsAreTheEightOrientations() {
        let size = 3
        let values = (0..<(size * size * 3)).map { Float($0) }
        var views = Set<[Float]>()
        for mirrored in [false, true] {
            for turns in 0..<4 { views.insert(TowerCloseupCheck.transformed(values, size: size, turns: turns, mirrored: mirrored)) }
        }
        #expect(views.count == 8)
        #expect(TowerCloseupCheck.transformed(values, size: size, turns: 4, mirrored: false) == values)
        // A quarter turn moves pixels, never the channels within a pixel.
        let turned = TowerCloseupCheck.transformed(values, size: size, turns: 1, mirrored: false)
        var channelsKept = true
        for base in stride(from: 0, to: turned.count, by: 3) {
            let red: Float = turned[base]
            let green: Float = turned[base + 1]
            let blue: Float = turned[base + 2]
            if green != red + 1 || blue != red + 2 { channelsKept = false }
        }
        #expect(channelsKept)
    }

    @Test func blocksBringTheCloseupNearestToAQuarterMetre() {
        func factor(_ metersPerPixel: Double) -> Int {
            TowerCloseupCheck.blockFactor(for: DetectionImage(width: 4, height: 4, rgb: [UInt8](repeating: 0, count: 48), metersPerPixel: metersPerPixel, center: origin, origin: origin))
        }
        #expect(factor(0.0625) == 4)
        #expect(factor(0.058) == 4)
        #expect(factor(0.24) == 1)
        #expect(factor(0.5) == 1)
    }

    @Test func inputIsTheStandardisedMiddleOfTheCloseup() {
        let closeup = Self.syntheticCloseup(origin: origin)
        let input = TowerCloseupCheck.input(from: closeup)
        #expect(input.count == 192 * 192 * 3)
        for c in 0..<3 {
            let channel = stride(from: c, to: input.count, by: 3).map { input[$0] }
            let mean = channel.reduce(0, +) / Float(channel.count)
            #expect(abs(mean) < 1e-3)
        }
        // A close-up as the review keeps it (averaged by the block factor) gives the same input.
        let kept = closeup.scaledDown(by: TowerCloseupCheck.blockFactor(for: closeup))
        #expect(kept.width == 288)
        #expect(TowerCloseupCheck.input(from: kept) == input)
    }

    @Test func bundledCheckMatchesTheTrainedModel() throws {
        let check = try #require(TowerCloseupCheck.bundled)
        let input = TowerCloseupCheck.input(from: Self.syntheticCloseup(origin: origin))
        // Reference from export_closeupcheck.py (logit of the plain view of the same pattern).
        #expect(abs(check.net.logit(input: input, size: 192) - 2.193006) < 0.05)
    }
}
