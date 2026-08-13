import Foundation
import Testing
@testable import RpplCore

@Suite("SessionExportLoader")
struct SessionExportLoaderTests {
    @Test("loads trimmed short-session fixture")
    func loadsFixture() throws {
        let url = try #require(Bundle.module.url(
            forResource: "short-session-export",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let package = try SessionExportLoader.load(fromFile: url)
        #expect(package.manifest.sessionId == "0158167A-A54E-45D4-8245-3AAD743F7979")
        #expect(package.locations.count == 32)
        #expect(package.assumptions.count == 1)
        #expect(package.assumptions[0].code == LabelCodes.waiting)
        // Test export omitted speed on GPS samples — must still decode.
        #expect(package.locations.allSatisfy { $0.speed == nil })
    }

    @Test("loads real Exports short session when present")
    func loadsRealExportIfPresent() throws {
        let url = URL(fileURLWithPath:
            "/Users/ducosebel/Development/rppl/Exports/0158167A-A54E-45D4-8245-3AAD743F7979.json"
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let package = try SessionExportLoader.load(fromFile: url)
        #expect(package.locations.count == 32)
        #expect(package.assumptions.count == 1)
        let span = SessionAnalysisPrep.sessionSpan(
            manifest: package.manifest,
            locations: package.locations,
            assumptions: package.assumptions
        )
        #expect(span.upperBound.timeIntervalSince(span.lowerBound) >= 60)
        let segments = SessionAnalysisPrep.segments(
            assumptions: package.assumptions,
            sessionEnd: span.upperBound
        )
        #expect(segments.count == 1)
        #expect(segments[0].end > segments[0].start)
    }
}
