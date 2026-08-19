import Foundation
import Testing
@testable import RpplCore

@Suite("WorkoutMetadataKeys")
struct WorkoutMetadataKeysTests {
    @Test func keysAreNonEmptyAndStable() {
        #expect(!WorkoutMetadataKeys.sessionId.isEmpty)
        #expect(!WorkoutMetadataKeys.detectionCode.isEmpty)
        #expect(!WorkoutMetadataKeys.rideCount.isEmpty)
        #expect(!WorkoutMetadataKeys.totalDistanceMeters.isEmpty)
        #expect(WorkoutMetadataKeys.sessionId.hasPrefix("nl.dcsbl.rppl."))
    }
}
