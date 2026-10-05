import Foundation
import Testing
@testable import RpplCore

@Suite("RecordingHealth")
struct RecordingHealthTests {
    private func codes(_ inputs: RecordingHealth.Inputs) -> [String] {
        RecordingHealth.evaluate(inputs).map(\.code)
    }

    @Test func healthyRecordingHasNoIssues() {
        let inputs = RecordingHealth.Inputs(
            freeBytes: 5_000_000_000,
            secondsSinceUsableFix: 3,
            batteryLevel: 0.8,
            batteryState: BatteryStateCodes.unplugged
        )
        #expect(codes(inputs).isEmpty)
    }

    @Test func missingWorkoutIsCritical() {
        let issues = RecordingHealth.evaluate(.init(hkMissing: true))
        #expect(issues == [.init(code: RecordingHealth.Code.hkMissing, severity: .critical)])
    }

    @Test func writeFailuresNeedAStreak() {
        #expect(codes(.init(consecutiveWriteFailures: RecordingHealth.writeFailureThreshold - 1)).isEmpty)
        #expect(codes(.init(consecutiveWriteFailures: RecordingHealth.writeFailureThreshold))
            == [RecordingHealth.Code.writeFailing])
    }

    @Test func storageWarnsThenTurnsCritical() {
        let low = RecordingHealth.evaluate(.init(freeBytes: SampleRequeue.lowStorageWarningBytes - 1))
        #expect(low.first?.severity == .warning)
        let critical = RecordingHealth.evaluate(.init(freeBytes: MotionRecordingPolicy.dropBelowFreeBytes - 1))
        #expect(critical.first?.severity == .critical)
        #expect(codes(.init(freeBytes: nil)).isEmpty)
    }

    @Test func gpsGapCountsOnlyWhileNotPaused() {
        let gap = RecordingHealth.gpsMissingAfter + 1
        #expect(codes(.init(secondsSinceUsableFix: gap)) == [RecordingHealth.Code.gpsMissing])
        #expect(codes(.init(secondsSinceUsableFix: gap, isProductPaused: true)).isEmpty)
        #expect(codes(.init(secondsSinceUsableFix: RecordingHealth.gpsMissingAfter)).isEmpty)
    }

    @Test func lowBatteryIgnoredWhileChargingOrUnknown() {
        let unplugged = RecordingHealth.Inputs(batteryLevel: 0.14, batteryState: BatteryStateCodes.unplugged)
        #expect(RecordingHealth.evaluate(unplugged).first?.severity == .warning)
        var veryLow = unplugged
        veryLow.batteryLevel = 0.09
        #expect(RecordingHealth.evaluate(veryLow).first?.severity == .critical)
        var charging = unplugged
        charging.batteryState = BatteryStateCodes.charging
        #expect(codes(charging).isEmpty)
        #expect(codes(.init(batteryLevel: -1)).isEmpty)
    }

    @Test func reducedLocationIsAWarning() {
        #expect(RecordingHealth.evaluate(.init(locationReduced: true))
            == [.init(code: RecordingHealth.Code.locationReduced, severity: .warning)])
    }

    @Test func criticalIssuesSortFirst() {
        let issues = RecordingHealth.evaluate(.init(hkMissing: true, locationReduced: true))
        #expect(issues.map(\.code) == [RecordingHealth.Code.hkMissing, RecordingHealth.Code.locationReduced])
    }

    @Test func gateFiresOncePerAppearance() {
        var gate = RecordingAlertGate()
        let hk = RecordingIssue(code: RecordingHealth.Code.hkMissing, severity: .critical)
        let reduced = RecordingIssue(code: RecordingHealth.Code.locationReduced, severity: .warning)
        #expect(gate.newCriticalCodes([hk, reduced]) == [RecordingHealth.Code.hkMissing])
        #expect(gate.newCriticalCodes([hk, reduced]).isEmpty)
        #expect(gate.newCriticalCodes([]).isEmpty)
        #expect(gate.newCriticalCodes([hk]) == [RecordingHealth.Code.hkMissing])
    }
}
