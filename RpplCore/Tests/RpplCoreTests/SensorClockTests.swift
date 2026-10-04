import Foundation
import Testing
@testable import RpplCore

@Suite("SensorClock")
struct SensorClockTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func bootOffsetIsWallTimeMinusUptime() {
        #expect(SensorClock.bootOffset(now: now, systemUptime: 1_000) == 1_790_000_000 - 1_000)
    }

    @Test func aSampleKeepsItsSensorTimeWhenDeliveryIsLate() {
        let offset = SensorClock.bootOffset(now: now, systemUptime: 5_000)
        // Measured 3 s before "now" (uptime 5000), delivered at `now`.
        let date = SensorClock.wallDate(bootOffset: offset, sensorTimestamp: 5_000 - 3, now: now)
        #expect(date == now.addingTimeInterval(-3))
    }

    @Test func aBackedUpBatchKeepsEvenSpacingInsteadOfBunching() {
        let offset = SensorClock.bootOffset(now: now, systemUptime: 5_000)
        // 25 Hz samples (40 ms apart) all delivered at the same instant.
        let dates = (0..<5).map {
            SensorClock.wallDate(bootOffset: offset, sensorTimestamp: 5_000 - 0.2 + Double($0) * 0.04, now: now)
        }
        for (a, b) in zip(dates, dates.dropFirst()) {
            #expect(abs(b.timeIntervalSince(a) - 0.04) < 1e-6)
        }
    }

    @Test func outputDependsOnlyOnOffsetAndSensorTimeWhenPlausible() {
        let offset = 1_789_995_000.0
        let first = SensorClock.wallDate(bootOffset: offset, sensorTimestamp: 4_990, now: now)
        let later = SensorClock.wallDate(bootOffset: offset, sensorTimestamp: 4_990, now: now.addingTimeInterval(30))
        #expect(first == later)
    }

    @Test func monotonicInputGivesMonotonicOutput() {
        let offset = SensorClock.bootOffset(now: now, systemUptime: 5_000)
        let dates = stride(from: 4_990.0, to: 4_999.0, by: 0.5).map {
            SensorClock.wallDate(bootOffset: offset, sensorTimestamp: $0, now: now)
        }
        #expect(dates == dates.sorted())
    }

    @Test func aFutureResultFallsBackToNow() {
        let date = SensorClock.wallDate(bootOffset: 1_790_000_100, sensorTimestamp: 0, now: now)
        #expect(date == now)
    }

    @Test func anImplausiblyOldResultFallsBackToNow() {
        let date = SensorClock.wallDate(bootOffset: 1_700_000_000, sensorTimestamp: 0, now: now)
        #expect(date == now)
    }

    @Test func theToleranceEdgesAreAccepted() {
        let future = SensorClock.wallDate(
            bootOffset: now.timeIntervalSince1970 + SensorClock.maxFutureSkew, sensorTimestamp: 0, now: now
        )
        #expect(future == now.addingTimeInterval(SensorClock.maxFutureSkew))
        let old = SensorClock.wallDate(
            bootOffset: now.timeIntervalSince1970 - SensorClock.maxDeliveryLag, sensorTimestamp: 0, now: now
        )
        #expect(old == now.addingTimeInterval(-SensorClock.maxDeliveryLag))
    }
}
