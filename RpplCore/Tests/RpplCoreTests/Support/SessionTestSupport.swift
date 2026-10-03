import Foundation
@testable import RpplCore

/// A throwaway session store for tests. Call `cleanup()` in a `defer`.
struct TempSession {
    let store: SessionFileStore
    let root: URL
    let sessionId: String

    static func make(
        startedAt: Date = Samples.t0,
        endedAt: Date? = nil,
        state: SessionManifest.TransferState = .recording
    ) throws -> TempSession {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1",
            buildNumber: "1",
            watchModel: "Watch7,12",
            systemVersion: "26.0",
            startedAt: startedAt,
            endedAt: endedAt,
            transferState: state
        )
        _ = try store.createSession(manifest: manifest)
        return TempSession(store: store, root: root, sessionId: manifest.sessionId)
    }

    var directory: URL {
        get throws { try store.sessionDirectory(for: sessionId) }
    }

    func file(_ name: String) throws -> URL {
        try directory.appendingPathComponent(name)
    }

    /// Make a stream file unwritable, like a Watch that cannot open it for append.
    func makeUnwritable(_ name: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file(name).path)
    }

    func makeWritable(_ name: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file(name).path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Deterministic samples: one per second from `t0`.
enum Samples {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func time(_ second: Int) -> Date { t0.addingTimeInterval(TimeInterval(second)) }

    static func location(_ second: Int, speed: Double? = 7) -> LocationSample {
        LocationSample(
            timestamp: time(second),
            latitude: 51.98 + Double(second) * 1e-5,
            longitude: 4.58,
            horizontalAccuracy: 5,
            speed: speed
        )
    }

    static func health(_ second: Int) -> HealthMetricSample {
        HealthMetricSample(timestamp: time(second), heartRateBPM: 120 + Double(second % 40))
    }

    static func water(_ second: Int) -> WaterTemperatureSample {
        WaterTemperatureSample(timestamp: time(second), celsius: 18.2)
    }

    static func battery(_ second: Int) -> BatterySample {
        BatterySample(timestamp: time(second), level: 0.9, state: "unplugged")
    }

    static func motion(_ second: Int) -> MotionSample {
        MotionSample(
            timestamp: time(second),
            userAccelX: 0.01, userAccelY: 0.02, userAccelZ: 0.03,
            rotationX: 0, rotationY: 0, rotationZ: 0,
            pitch: 0, roll: 0, yaw: 0
        )
    }

    static func detection(_ code: String, second: Int, detectorId: String = "test") -> DetectionEvent {
        DetectionEvent(code: code, timestamp: time(second), reason: detectorId, detectorId: detectorId)
    }
}
