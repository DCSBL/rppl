import Testing
@testable import RpplCore

struct ParkDiffTests {
    @Test func lineDiffReportsRemovedAndAdded() {
        let diff = ParkDiff.lineDiff(from: "a\nb\nc", to: "a\nx\nc\nd")
        #expect(diff.removed == [.init(number: 2, text: "b")])
        #expect(diff.added == [.init(number: 2, text: "x"), .init(number: 4, text: "d")])
        #expect(diff.patchText == "-2: b\n+2: x\n+4: d")
    }

    @Test func lineDiffOfIdenticalTextIsEmpty() {
        #expect(ParkDiff.lineDiff(from: "a\nb", to: "a\nb").isEmpty)
    }
}
