import Foundation
import Testing
@testable import RpplCore

@Suite("SessionImportLimits")
struct SessionImportLimitsTests {
    @Test func rejectsOversizedTransferJSON() {
        let oversize = SessionImportLimits.maxTransferJSONBytes + 1
        let json = Data(repeating: UInt8(ascii: " "), count: oversize)
        #expect(throws: SessionStoreError.importTooLarge(oversize)) {
            try SessionImportLimits.decodeTransferPackage(from: json)
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
