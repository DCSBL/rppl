import Testing
@testable import RpplCore

struct CompassDirection8Tests {
    @Test func mapsCardinalDegreesExactly() {
        #expect(CompassDirection8(degrees: 0) == .north)
        #expect(CompassDirection8(degrees: 45) == .northeast)
        #expect(CompassDirection8(degrees: 90) == .east)
        #expect(CompassDirection8(degrees: 135) == .southeast)
        #expect(CompassDirection8(degrees: 180) == .south)
        #expect(CompassDirection8(degrees: 225) == .southwest)
        #expect(CompassDirection8(degrees: 270) == .west)
        #expect(CompassDirection8(degrees: 315) == .northwest)
    }

    @Test func roundsToNearestWedge() {
        #expect(CompassDirection8(degrees: 20) == .north)
        #expect(CompassDirection8(degrees: 26) == .northeast)
        #expect(CompassDirection8(degrees: 359) == .north)
    }

    @Test func wrapsNegativeAndOverflowingDegrees() {
        #expect(CompassDirection8(degrees: -10) == .north)
        #expect(CompassDirection8(degrees: -90) == .west)
        #expect(CompassDirection8(degrees: 405) == .northeast)
        #expect(CompassDirection8(degrees: 720) == .north)
    }

    @Test func abbreviationsAreShort() {
        for direction in CompassDirection8.allCases {
            #expect(direction.abbreviation.count <= 2)
            #expect(!direction.name.isEmpty)
        }
    }
}
