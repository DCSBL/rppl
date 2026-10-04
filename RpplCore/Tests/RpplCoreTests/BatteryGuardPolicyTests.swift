import Foundation
import Testing
@testable import RpplCore

@Suite("BatteryGuardPolicy")
struct BatteryGuardPolicyTests {
    private let unplugged = BatteryStateCodes.unplugged

    private func decide(_ level: Double, state: String? = nil, warned: Set<String> = []) -> BatteryGuardPolicy.Action {
        BatteryGuardPolicy.decide(level: level, state: state ?? unplugged, alreadyWarned: warned)
    }

    @Test func aHealthyBatteryDoesNothing() {
        #expect(decide(0.80) == .none)
        #expect(decide(0.16) == .none)
    }

    @Test func warnsAtFifteenAndAtTenPercentOnceEach() {
        #expect(decide(0.15) == .warn(code: BatteryGuardPolicy.Warning.low))
        #expect(decide(0.15, warned: [BatteryGuardPolicy.Warning.low]) == .none)

        #expect(decide(0.10, warned: [BatteryGuardPolicy.Warning.low]) == .warn(code: BatteryGuardPolicy.Warning.veryLow))
        #expect(
            decide(0.09, warned: [BatteryGuardPolicy.Warning.low, BatteryGuardPolicy.Warning.veryLow]) == .none
        )
    }

    @Test func autoStopsAtFivePercentAndBelow() {
        #expect(decide(0.05) == .autoStop)
        #expect(decide(0.02) == .autoStop)
        #expect(decide(0.051) != .autoStop)
        // Even when the warnings were already shown.
        #expect(decide(0.05, warned: [BatteryGuardPolicy.Warning.low, BatteryGuardPolicy.Warning.veryLow]) == .autoStop)
    }

    @Test func chargingAndFullNeverActEvenWhenLow() {
        for state in [BatteryStateCodes.charging, BatteryStateCodes.full] {
            #expect(decide(0.03, state: state) == .none)
            #expect(decide(0.10, state: state) == .none)
        }
    }

    @Test func anUnknownStateCountsAsRunningOnBattery() {
        #expect(decide(0.04, state: BatteryStateCodes.unknown) == .autoStop)
        #expect(decide(0.12, state: BatteryStateCodes.unknown) == .warn(code: BatteryGuardPolicy.Warning.low))
    }

    @Test func anUnknownLevelNeverActs() {
        #expect(decide(-1) == .none)
    }

    @Test func aJumpPastBothThresholdsWarnsOnceAsVeryLow() {
        let action = decide(0.08)
        #expect(action == .warn(code: BatteryGuardPolicy.Warning.veryLow))

        let covered = BatteryGuardPolicy.coveredCodes(by: BatteryGuardPolicy.Warning.veryLow)
        #expect(covered == [BatteryGuardPolicy.Warning.veryLow, BatteryGuardPolicy.Warning.low])
        #expect(decide(0.08, warned: covered) == .none)
    }

    @Test func aLowWarningDoesNotCoverTheVeryLowOne() {
        #expect(BatteryGuardPolicy.coveredCodes(by: BatteryGuardPolicy.Warning.low) == [BatteryGuardPolicy.Warning.low])
        #expect(BatteryGuardPolicy.coveredCodes(by: "something_else") == ["something_else"])
    }

    @Test func thresholdsAreOrderedAndBelowTheWarnings() {
        let levels = BatteryGuardPolicy.warnLevels.map(\.level)
        #expect(levels == levels.sorted())
        #expect(BatteryGuardPolicy.autoStopLevel < (levels.first ?? 0))
    }
}

@Suite("BatterySample")
struct BatterySampleTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test func lowPowerModeIsOptionalOnDisk() throws {
        let json = Data(#"{"timestamp":"2026-10-04T10:00:00Z","level":0.5,"state":"unplugged"}"#.utf8)
        let sample = try decoder.decode(BatterySample.self, from: json)
        #expect(sample.lowPowerMode == nil)
        #expect(sample.level == 0.5)
    }

    @Test func lowPowerModeRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = BatterySample(
            timestamp: Date(timeIntervalSince1970: 1_790_000_000), level: 0.12, state: "unplugged", lowPowerMode: true
        )
        let decoded = try decoder.decode(BatterySample.self, from: try encoder.encode(original))
        #expect(decoded == original)
        #expect(decoded.lowPowerMode == true)
    }
}
