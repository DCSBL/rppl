import Testing
@testable import RpplCore

struct BeaufortScaleTests {
    @Test func mapsKnownSpeedsToKnownForces() {
        #expect(BeaufortScale.number(forKmh: 0) == 0)
        #expect(BeaufortScale.number(forKmh: 0.9) == 0)
        #expect(BeaufortScale.number(forKmh: 5) == 1)
        #expect(BeaufortScale.number(forKmh: 18) == 3)
        #expect(BeaufortScale.number(forKmh: 40) == 6)
        #expect(BeaufortScale.number(forKmh: 61) == 7)
        #expect(BeaufortScale.number(forKmh: 200) == 12)
    }

    @Test func boundariesRoundUpToTheHigherForce() {
        #expect(BeaufortScale.number(forKmh: 5.9) == 1)
        #expect(BeaufortScale.number(forKmh: 6) == 2)
        #expect(BeaufortScale.number(forKmh: 117.9) == 11)
        #expect(BeaufortScale.number(forKmh: 118) == 12)
    }

    @Test func labelIncludesTheNumber() {
        #expect(BeaufortScale.label(forKmh: 18).contains("3"))
    }
}
