import Foundation
import Testing
@testable import RpplCore

@Suite("AssumerSignalFilter")
struct AssumerSignalFilterTests {
    private let filter = AssumerSignalFilter()

    private func tick(
        speedKmh: Double?,
        accuracy: Double? = 5
    ) -> AssumerTick {
        AssumerTick(
            timestamp: Date(timeIntervalSince1970: 1),
            speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
            horizontalAccuracy: accuracy,
            waterSubmersionState: "notSubmerged",
            motionActivity: "stationary"
        )
    }

    @Test func acceptsCleanSpeed() {
        let outcome = filter.evaluate(tick(speedKmh: 16), previousUsableSpeedMps: nil)
        #expect(outcome.speedUsable)
        #expect(outcome.rejectionReason == nil)
    }

    @Test func rejectsNilSpeed() {
        let outcome = filter.evaluate(tick(speedKmh: nil, accuracy: nil), previousUsableSpeedMps: nil)
        #expect(!outcome.speedUsable)
        #expect(outcome.rejectionReason == "nil_speed")
    }

    @Test func rejectsPoorAccuracy() {
        let outcome = filter.evaluate(tick(speedKmh: 16, accuracy: 40), previousUsableSpeedMps: nil)
        #expect(!outcome.speedUsable)
        #expect(outcome.rejectionReason?.hasPrefix("accuracy>") == true)
    }

    @Test func rejectsNegativeAccuracy() {
        let outcome = filter.evaluate(tick(speedKmh: 16, accuracy: -1), previousUsableSpeedMps: nil)
        #expect(!outcome.speedUsable)
        #expect(outcome.rejectionReason == "accuracy_negative")
    }

    @Test func rejectsImplausibleSpeed() {
        let outcome = filter.evaluate(tick(speedKmh: 80), previousUsableSpeedMps: nil)
        #expect(!outcome.speedUsable)
        #expect(outcome.rejectionReason?.contains("implausible") == true)
    }

    @Test func rejectsSuddenSpeedJump() {
        let previous = SpeedUnits.metersPerSecond(fromKilometersPerHour: 2)
        let outcome = filter.evaluate(tick(speedKmh: 40), previousUsableSpeedMps: previous)
        #expect(!outcome.speedUsable)
        #expect(outcome.rejectionReason?.hasPrefix("speed_jump_") == true)
    }

    @Test func allowsGradualSpeedRise() {
        let previous = SpeedUnits.metersPerSecond(fromKilometersPerHour: 10)
        let outcome = filter.evaluate(tick(speedKmh: 25), previousUsableSpeedMps: previous)
        #expect(outcome.speedUsable)
    }
}

@Suite("AssumerRuleSetExtensibility")
struct AssumerRuleSetExtensibilityTests {
    /// Proof: prepend a custom rule → new behaviour without editing core FSM.
    struct ForceWalkFromWaiting: AssumerTransitionRule {
        let id = "test_force_walk"
        let from = LabelCodes.waiting
        let to = LabelCodes.walking

        func reasonIfMatches(_ ctx: AssumerEvalContext) -> String? {
            "test_force_walk"
        }
    }

    @Test func customRulePrependsAndWinsOverDefaults() {
        let rules = AssumerRuleSet(rules: [ForceWalkFromWaiting()] + AssumerRuleSet.cableParkV0.rules)
        var assumer = SegmentAssumer(rules: rules)
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        let event = assumer.process(
            AssumerTick(
                timestamp: Date(timeIntervalSince1970: 1),
                speedMps: SpeedUnits.metersPerSecond(fromKilometersPerHour: 16),
                horizontalAccuracy: 5,
                waterSubmersionState: "notSubmerged",
                motionActivity: "stationary"
            )
        )
        #expect(event?.code == LabelCodes.walking)
        #expect(event?.reason == "test_force_walk")
        #expect(assumer.currentCode == LabelCodes.walking)
    }

    @Test func defaultRulesCountIsStableSurfaceForAppends() {
        #expect(AssumerRuleSet.cableParkV0.rules.count == 8)
        #expect(AssumerRuleSet.cableParkV0.rules.map(\.id).contains("fall_swim"))
        #expect(AssumerRuleSet.cableParkV0.rules.map(\.id).contains("long_stop"))
    }
}

@Suite("SegmentAssumerNoise")
struct SegmentAssumerNoiseTests {
    private func tick(
        at seconds: TimeInterval,
        speedKmh: Double?,
        water: String? = "notSubmerged",
        activity: String? = "stationary",
        accuracy: Double? = 5
    ) -> AssumerTick {
        AssumerTick(
            timestamp: Date(timeIntervalSince1970: seconds),
            speedMps: speedKmh.map { SpeedUnits.metersPerSecond(fromKilometersPerHour: $0) },
            horizontalAccuracy: accuracy,
            waterSubmersionState: water,
            motionActivity: activity
        )
    }

    @Test func singleSpeedSpikeDoesNotStartRideHold() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        // Glitch spike then back to zero — hold must reset; no ride
        #expect(assumer.process(tick(at: 1, speedKmh: 80)) == nil)
        #expect(assumer.lastFilterRejection?.contains("implausible") == true)
        #expect(assumer.process(tick(at: 2, speedKmh: 0)) == nil)
        #expect(assumer.process(tick(at: 5, speedKmh: 0)) == nil)
        #expect(assumer.currentCode == LabelCodes.waiting)
    }

    @Test func intermittentPoorAccuracyResetsHighSpeedHold() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        #expect(assumer.process(tick(at: 1, speedKmh: 16, accuracy: 5)) == nil)
        // Gap with bad accuracy should clear high-speed hold
        #expect(assumer.process(tick(at: 2.5, speedKmh: 16, accuracy: 40)) == nil)
        #expect(assumer.lastFilterRejection?.hasPrefix("accuracy>") == true)
        // Only ~1s of good speed after — still under 2s hold
        #expect(assumer.process(tick(at: 3.5, speedKmh: 16, accuracy: 5)) == nil)
        #expect(assumer.currentCode == LabelCodes.waiting)

        let ride = assumer.process(tick(at: 5.6, speedKmh: 16, accuracy: 5))
        #expect(ride?.code == LabelCodes.riding)
    }

    @Test func speedJumpDoesNotCountTowardRideEnter() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))

        #expect(assumer.process(tick(at: 1, speedKmh: 3)) == nil)
        // Jump 3 → 35 rejected; hold does not advance
        #expect(assumer.process(tick(at: 2, speedKmh: 35)) == nil)
        #expect(assumer.lastFilterRejection?.hasPrefix("speed_jump_") == true)
        #expect(assumer.process(tick(at: 4.5, speedKmh: 35)) == nil)
        #expect(assumer.currentCode == LabelCodes.waiting)
    }

    @Test func waterSwimStillFiresWhenSpeedFiltered() {
        var assumer = SegmentAssumer()
        _ = assumer.makeSessionStartEvent(at: Date(timeIntervalSince1970: 0))
        #expect(assumer.process(tick(at: 1, speedKmh: 16)) == nil)
        #expect(assumer.process(tick(at: 3.1, speedKmh: 16))?.code == LabelCodes.riding)

        let swim = assumer.process(tick(at: 8, speedKmh: nil, water: "submerged", accuracy: 50))
        #expect(swim?.code == LabelCodes.swimming)
    }
}
