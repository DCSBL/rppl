import Foundation
import Testing
@testable import RpplCore

struct ImpactStatsTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func motion(at offset: TimeInterval, x: Double = 0, y: Double = 0, z: Double = 0) -> MotionSample {
        MotionSample(
            timestamp: t0.addingTimeInterval(offset),
            userAccelX: x, userAccelY: y, userAccelZ: z,
            rotationX: 0, rotationY: 0, rotationZ: 0,
            pitch: 0, roll: 0, yaw: 0
        )
    }

    private func set(index: Int, impact: Double?) -> SetSegmentStats {
        SetSegmentStats(
            index: index,
            startedAt: t0.addingTimeInterval(Double(index) * 1_000),
            endedAt: t0.addingTimeInterval(Double(index) * 1_000 + 60),
            duration: 60,
            distanceMeters: 500,
            peakImpactG: impact
        )
    }

    @Test func peakIsMagnitudeWithinWindow() {
        let samples = [
            motion(at: 1, x: 1),
            motion(at: 2, x: 3, y: 4),
            motion(at: 99, x: 10),
        ]
        let peak = ImpactStats.peakG(in: samples, from: t0, to: t0.addingTimeInterval(10))
        #expect(peak == 5)
    }

    @Test func nilWithoutSamplesInWindow() {
        #expect(ImpactStats.peakG(in: [], from: t0, to: t0.addingTimeInterval(10)) == nil)
        #expect(ImpactStats.peakG(in: [motion(at: 50, x: 5)], from: t0, to: t0.addingTimeInterval(10)) == nil)
    }

    @Test func glitchAboveCapIgnored() {
        let samples = [motion(at: 1, x: 2), motion(at: 2, x: 40)]
        #expect(ImpactStats.peakG(in: samples, from: t0, to: t0.addingTimeInterval(10)) == 2)
    }

    @Test func highImpactThreshold() {
        #expect(ImpactStats.isHighImpact(ImpactStats.highImpactG))
        #expect(!ImpactStats.isHighImpact(ImpactStats.highImpactG - 0.1))
        #expect(!ImpactStats.isHighImpact(nil))
    }

    @Test func setBadgeForEveryHardSet() {
        let result = HighlightAssigner.assignSetHighlights([
            set(index: 1, impact: 5), set(index: 2, impact: 2), set(index: 3, impact: 7),
        ])
        #expect(result[0].highlights.contains(.highImpact))
        #expect(!result[1].highlights.contains(.highImpact))
        #expect(result[2].highlights.contains(.highImpact))
    }

    @Test func singleSetStillGetsImpactBadge() {
        let result = HighlightAssigner.assignSetHighlights([set(index: 1, impact: 6)])
        #expect(result[0].highlights == [.highImpact])
    }

    @Test func sessionHighestImpactNeedsHighImpact() {
        func input(_ id: String, _ g: Double?) -> SessionHighlightInput {
            SessionHighlightInput(id: id, totalDuration: 100, ridingDuration: 50, lapCount: 1, peakImpactG: g)
        }
        let hard = HighlightAssigner.assignSessionHighlights([input("a", 5), input("b", 8)])
        #expect(hard["b"]?.contains(.highestImpact) == true)
        #expect(hard["a"]?.contains(.highestImpact) != true)

        let soft = HighlightAssigner.assignSessionHighlights([input("a", 2), input("b", 3)])
        #expect(soft["b"]?.contains(.highestImpact) != true)
    }

    @Test func legacySetJSONDecodesWithoutImpact() throws {
        let json = """
        {"index":1,"startedAt":0,"endedAt":60,"duration":60,"distanceMeters":10}
        """
        let decoded = try JSONDecoder().decode(SetSegmentStats.self, from: Data(json.utf8))
        #expect(decoded.peakImpactG == nil)
    }

    @Test func peakImpactRoundTrips() throws {
        let original = set(index: 1, impact: 6.25)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SetSegmentStats.self, from: data).peakImpactG == 6.25)
    }
}
