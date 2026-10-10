import Foundation
import Testing
@testable import RpplCore

@Suite("SetTelemetry")
struct SetTelemetryTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    private func location(_ second: Double, speed: Double?, altitude: Double?) -> LocationSample {
        LocationSample(
            timestamp: t0.addingTimeInterval(second),
            latitude: 52, longitude: 5, altitude: altitude,
            horizontalAccuracy: 5, speed: speed
        )
    }

    private func motion(_ second: Double, x: Double, y: Double = 0, z: Double = 0) -> MotionSample {
        MotionSample(
            timestamp: t0.addingTimeInterval(second),
            userAccelX: x, userAccelY: y, userAccelZ: z,
            rotationX: 0, rotationY: 0, rotationZ: 0, pitch: 0, roll: 0, yaw: 0
        )
    }

    @Test func convertsSpeedAndRebasesAltitude() {
        let telemetry = SetTelemetryBuilder.build(
            locations: [
                location(-5, speed: 99, altitude: 50),
                location(1, speed: 10, altitude: 12),
                location(2, speed: -1, altitude: 14),
                location(3, speed: 5, altitude: 11),
            ],
            motion: [],
            from: t0,
            to: t0.addingTimeInterval(10)
        )
        #expect(telemetry.speedKmh.map(\.value) == [36, 18])
        #expect(telemetry.altitudeMeters.map(\.value) == [0, 2, -1])
        #expect(telemetry.altitudeMeters.first?.offset == 1)
    }

    @Test func gForceKeepsPeakPerBucket() {
        let telemetry = SetTelemetryBuilder.build(
            locations: [],
            motion: [motion(0.1, x: 0.3), motion(0.2, x: 3, y: 4), motion(9, x: 1)],
            from: t0,
            to: t0.addingTimeInterval(10),
            maxPoints: 2
        )
        #expect(telemetry.gForce.map(\.value) == [5, 1])
    }

    @Test func downsamplesToMaxPointsKeepingEnds() {
        let locations = (0..<100).map { location(Double($0), speed: Double($0), altitude: nil) }
        let telemetry = SetTelemetryBuilder.build(
            locations: locations, motion: [], from: t0, to: t0.addingTimeInterval(100), maxPoints: 10
        )
        #expect(telemetry.speedKmh.count == 10)
        #expect(telemetry.speedKmh.first?.offset == 0)
        #expect(telemetry.speedKmh.last?.offset == 99)
    }

    @Test func emptyWindowGivesEmptyTelemetry() {
        #expect(SetTelemetryBuilder.build(locations: [], motion: [], from: t0, to: t0).isEmpty)
    }
}
