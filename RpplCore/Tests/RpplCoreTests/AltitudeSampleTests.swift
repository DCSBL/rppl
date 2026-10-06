import Foundation
import Testing
@testable import RpplCore

@Suite("AltitudeSample", .serialized)
struct AltitudeSampleTests {
    @Test func encodesCompactKeysAtSensorResolution() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let sample = AltitudeSample(
            timestamp: Samples.time(0),
            relativeAltitudeMeters: 1.234_567,
            pressureKPa: 101.325_678
        )

        let line = try #require(String(data: try encoder.encode(sample), encoding: .utf8))

        #expect(line.contains("\"a\":1.23"))
        #expect(line.contains("\"p\":101.326"))
        #expect(!line.contains("relativeAltitudeMeters"))
        // A day of 1 Hz samples stays small enough to need no compression.
        #expect(line.utf8.count < 60)
    }

    @Test func roundTripsThroughStoreAndTransferPackage() throws {
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        defer { session.cleanup() }
        let id = session.sessionId
        try session.store.appendAltitudeSamples((0..<5).map { Samples.altitude($0) }, sessionId: id)

        let stored = try session.store.readAltitudeSamples(sessionId: id)
        #expect(stored.map(\.timestamp) == (0..<5).map { Samples.time($0) })

        let package = try session.store.buildTransferPackage(sessionId: id)
        #expect(package.altitude.count == 5)

        let phoneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rppl-altitude-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: phoneRoot) }
        try session.store.importTransferPackage(package, intoPhoneStore: phoneRoot)
        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readAltitudeSamples(sessionId: id).count == 5)
    }

    @Test func packageWithoutAltitudeStillDecodes() throws {
        let session = try TempSession.make(endedAt: Samples.time(60), state: .readyToTransfer)
        defer { session.cleanup() }
        let package = try session.store.buildTransferPackage(sessionId: session.sessionId)
        #expect(package.altitude.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try #require(String(data: try encoder.encode(package), encoding: .utf8))
        #expect(!json.contains("\"altitude\""))
        let decoded = try SessionImportLimits.decodeTransferPackage(from: Data(json.utf8))
        #expect(decoded.altitude.isEmpty)
    }

    @Test func lastRecordedTimestampCountsAltitude() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        try session.store.appendAltitudeSamples([Samples.altitude(42)], sessionId: session.sessionId)

        #expect(session.store.lastRecordedTimestamp(sessionId: session.sessionId) == Samples.time(42))
    }
}
