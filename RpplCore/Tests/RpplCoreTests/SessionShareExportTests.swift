import Foundation
import Testing
@testable import RpplCore

struct SessionShareExportTests {
    @Test func fileNameUsesTimestampAndLocation() {
        let started = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z
        let name = SessionShareExport.fileName(startedAt: started, locationName: "Utrecht")
        #expect(name == "rppl_2024-01-01T00-00-00Z_Utrecht.json")
    }

    @Test func fileNameSanitizesLocationAndFallsBack() {
        let started = Date(timeIntervalSince1970: 0)
        #expect(
            SessionShareExport.fileName(startedAt: started, locationName: "Dutch Water Dreams")
                == "rppl_1970-01-01T00-00-00Z_Dutch-Water-Dreams.json"
        )
        #expect(
            SessionShareExport.fileName(startedAt: started, locationName: "  ")
                == "rppl_1970-01-01T00-00-00Z_unknown.json"
        )
        #expect(
            SessionShareExport.fileName(startedAt: started, locationName: nil)
                == "rppl_1970-01-01T00-00-00Z_unknown.json"
        )
    }

    @Test func anonymizedFileNameHasNoPlaceName() {
        let started = Date(timeIntervalSince1970: 1_704_067_200)
        #expect(
            SessionShareExport.anonymizedFileName(startedAt: started)
                == "rppl_2024-01-01T00-00-00Z_anonymized.json"
        )
    }

    @Test func sanitizeLocationCollapsesSeparators() {
        #expect(SessionShareExport.sanitizeLocation("A  /  B") == "A-B")
        #expect(SessionShareExport.sanitizeLocation("@@@") == "unknown")
    }

    @Test func encodeIsPrettyPrintedWithManifestFirst() throws {
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                sessionId: "export-test",
                testerId: "tester",
                appVersion: "1.0",
                buildNumber: "1",
                watchModel: "Watch",
                systemVersion: "26.0",
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200),
                transferState: .acknowledged
            ),
            detections: [],
            locations: [],
            health: []
        )

        let data = try SessionShareExport.encode(package)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\n"))
        #expect(text.hasPrefix("{\n  \"manifest\""))

        let manifestKey = try #require(text.range(of: "\"manifest\""))
        let detectionsKey = try #require(text.range(of: "\"detections\""))
        let locationsKey = try #require(text.range(of: "\"locations\""))
        #expect(manifestKey.lowerBound < detectionsKey.lowerBound)
        #expect(manifestKey.lowerBound < locationsKey.lowerBound)

        // JSONEncoder key order is unstable without sortedKeys; sortedKeys puts
        // "detections" before "manifest". Encode must force manifest-first.
        let again = try SessionShareExport.encode(package)
        let againText = try #require(String(data: again, encoding: .utf8))
        #expect(againText.hasPrefix("{\n  \"manifest\""))
    }

    @Test func encodeIncludesBatteryWhenPresent() throws {
        let package = SessionTransferPackage(
            manifest: SessionManifest(
                sessionId: "export-battery",
                testerId: "tester",
                appVersion: "1.0",
                buildNumber: "1",
                watchModel: "Watch",
                systemVersion: "26.0",
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 200),
                transferState: .acknowledged
            ),
            detections: [],
            locations: [],
            health: [],
            battery: [
                BatterySample(
                    timestamp: Date(timeIntervalSince1970: 150),
                    level: 0.9123,
                    state: BatteryStateCodes.unplugged
                ),
            ]
        )
        let text = try #require(String(data: try SessionShareExport.encode(package), encoding: .utf8))
        #expect(text.contains("\"battery\""))
        #expect(text.contains("0.9123"))
        #expect(text.contains(BatteryStateCodes.unplugged))
        let healthKey = try #require(text.range(of: "\"health\""))
        let batteryKey = try #require(text.range(of: "\"battery\""))
        #expect(healthKey.lowerBound < batteryKey.lowerBound)
    }
}
