import Foundation
import Testing
@testable import RpplCore

struct TowerWheelFinderTests {
    private let origin = ParkCoordinate(lat: 52.3581295, lon: 5.2152087)

    private struct Cell {
        let column: Int
        let row: Int
        let value: Double
    }

    private func heatmap(peaks: [Cell]) -> [Double] {
        var values = [Double](repeating: 0.0001, count: 24 * 24)
        for peak in peaks { values[peak.row * 24 + peak.column] = peak.value }
        return values
    }

    @Test func peakIsTheMiddleOfItsCell() {
        // Cell (15, 12) spans input pixels 120..128 x 96..104; the middle of the input is 96.
        let offset = TowerWheelFinder.peak(in: heatmap(peaks: [Cell(column: 15, row: 12, value: 0.9)]))
        #expect(abs(offset.x - 28) < 0.1)
        #expect(abs(offset.y - 4) < 0.1)
    }

    @Test func peakIsPulledByItsNeighbours() {
        let offset = TowerWheelFinder.peak(in: heatmap(peaks: [Cell(column: 12, row: 12, value: 0.6), Cell(column: 13, row: 12, value: 0.3)]))
        #expect(offset.x > 4 && offset.x < 8)
    }

    @Test func aFarPeakLosesToANearOne() {
        // 11 m off and twice as likely, or 2 m off: the prior around the guess picks the near one.
        let offset = TowerWheelFinder.peak(in: heatmap(peaks: [Cell(column: 12, row: 12, value: 0.3), Cell(column: 12, row: 1, value: 0.6)]))
        #expect(abs(offset.y - 4) < 0.5)
    }

    @Test func bundledFinderMatchesTheTrainedModel() throws {
        let finder = try #require(TowerWheelFinder.bundled)
        let closeup = TowerCloseupCheckTests.syntheticCloseup(origin: origin)
        let cells = finder.heatmap(TowerCloseupCheck.input(from: closeup))
        #expect(cells.count == 24 * 24)
        #expect(abs(cells.reduce(0, +) - 1) < 1e-6)
        // References from export_wheelfind.py (cell probabilities of the same pattern).
        #expect(abs(cells[12 * 24 + 12] - 0.0024439) < 0.0000500)
        #expect(abs(cells[0] - 0.0000489) < 0.0000020)
        #expect(abs(cells[5 * 24 + 16] - 0.0030807) < 0.0000600)
        // Wheel offset -4.04, -12.11 input px: 1.01 m west and 3.03 m north of the guess.
        let wheel = DetectionImage.localXY(of: finder.wheel(in: closeup), origin: origin)
        #expect(abs(wheel.x - -1.009) < 0.1)
        #expect(abs(wheel.y - 3.027) < 0.1)
    }
}
