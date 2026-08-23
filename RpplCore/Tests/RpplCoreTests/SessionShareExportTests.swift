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
        #expect(text.hasPrefix("{\n"))

        let manifestKey = text.range(of: "\"manifest\"")
        let detectionsKey = text.range(of: "\"detections\"")
        let locationsKey = text.range(of: "\"locations\"")
        #expect(manifestKey != nil)
        #expect(detectionsKey != nil)
        #expect(locationsKey != nil)
        if let manifestKey, let detectionsKey, let locationsKey {
            #expect(manifestKey.lowerBound < detectionsKey.lowerBound)
            #expect(manifestKey.lowerBound < locationsKey.lowerBound)
        }

        // sortedKeys would put "detections" before "manifest".
        #expect(text.contains("\n  \"manifest\""))
    }
}
