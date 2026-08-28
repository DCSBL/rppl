import Foundation
import Testing
@testable import RpplCore

@Suite("SessionImportLimits")
struct SessionImportLimitsTests {
    @Test func rejectsOversizedTransferJSONOnDisk() throws {
        let limit = 1024
        let oversize = limit + 1
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-limit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("package.json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(oversize))
        try handle.close()

        #expect(throws: SessionStoreError.importTooLarge(oversize)) {
            _ = try SessionImportLimits.readBoundedFile(at: url, maxBytes: limit)
        }
    }

    @Test func validateArrayCountRejectsOverLimit() {
        let over = Array(repeating: 0, count: SessionImportLimits.maxLocations + 1)
        #expect(throws: SessionStoreError.self) {
            try SessionImportLimits.validateArrayCount(over, limit: SessionImportLimits.maxLocations, label: "locations")
        }
    }

    @Test func rejectsExcessiveHeatmapTracks() throws {
        let tracks = Array(
            repeating: [MapCoordinate(latitude: 1, longitude: 2)],
            count: SessionImportLimits.maxHeatmapTrackCount + 1
        )
        let payload = SessionMapTrackData(start: MapCoordinate(latitude: 52, longitude: 5), heatmapTracks: tracks)
        let data = try JSONEncoder().encode(payload)
        #expect(throws: SessionStoreError.self) {
            try JSONDecoder().decode(SessionMapTrackData.self, from: data)
        }
    }
}
