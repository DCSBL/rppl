import Foundation
import Testing
@testable import RpplCore

@Suite("SessionAnalysisPrep")
struct SessionAnalysisPrepTests {
    @Test("default selection clamps to span for short sessions")
    func shortSessionSelection() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(180)
        let span = start...end
        let selection = SessionAnalysisPrep.defaultSelection(span: span)
        #expect(selection.lowerBound == start)
        #expect(selection.upperBound == end)
        #expect(selection.upperBound.timeIntervalSince(selection.lowerBound) >= 60)
    }

    @Test("clippedBand rejects inverted ranges")
    func clippedBand() {
        let range = Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 200)
        #expect(
            SessionAnalysisPrep.clippedBand(
                start: Date(timeIntervalSince1970: 50),
                end: Date(timeIntervalSince1970: 60),
                range: range
            ) == nil
        )
        let band = SessionAnalysisPrep.clippedBand(
            start: Date(timeIntervalSince1970: 150),
            end: Date(timeIntervalSince1970: 250),
            range: range
        )
        #expect(band == Date(timeIntervalSince1970: 150)...Date(timeIntervalSince1970: 200))
    }
}
