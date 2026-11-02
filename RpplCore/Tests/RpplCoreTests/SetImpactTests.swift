import Foundation
import Testing
@testable import RpplCore

@Suite("SetImpact")
struct SetImpactTests {
    private let end = Date(timeIntervalSince1970: 1_700_000_000)

    private func motion(at offset: TimeInterval, g: Double) -> MotionSample {
        MotionSample(
            timestamp: end.addingTimeInterval(offset),
            userAccelX: g, userAccelY: 0, userAccelZ: 0,
            rotationX: 0, rotationY: 0, rotationZ: 0,
            pitch: 0, roll: 0, yaw: 0
        )
    }

    @Test func peakInsideWindowBeforeTheDetectedEnd() {
        let samples = [motion(at: -30, g: 9), motion(at: -6, g: 5.5), motion(at: -5, g: 1), motion(at: 2, g: 2), motion(at: 10, g: 8)]
        #expect(SetImpact.peakG(motion: samples, around: end) == 5.5)
        #expect(SetImpact.isFall(5.5))
        #expect(!SetImpact.isFall(1.9))
        #expect(!SetImpact.isFall(nil))
    }

    @Test func noMotionAroundTheEndGivesNil() {
        #expect(SetImpact.peakG(motion: [motion(at: -60, g: 9)], around: end) == nil)
        #expect(SetImpact.peakG(motion: [], around: end) == nil)
    }

    @Test func magnitudeCombinesAxes() throws {
        let sample = MotionSample(
            timestamp: end, userAccelX: 3, userAccelY: 4, userAccelZ: 0,
            rotationX: 0, rotationY: 0, rotationZ: 0, pitch: 0, roll: 0, yaw: 0
        )
        let peak = try #require(SetImpact.peakG(motion: [sample], around: end))
        #expect(abs(peak - 5) < 1e-9)
    }
}
