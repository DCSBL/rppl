import Foundation
import Testing
@testable import RpplCore

@Suite("App identifier overrides")
struct AppConstantsTests {
    @Test func missingKeyFallsBackToProd() {
        #expect(AppConstants.resolvedIdentifier(infoValue: nil, fallback: "group.nl.dcsbl.rppl") == "group.nl.dcsbl.rppl")
    }

    @Test func nonStringOrBlankFallsBack() {
        #expect(AppConstants.resolvedIdentifier(infoValue: 42, fallback: "x") == "x")
        #expect(AppConstants.resolvedIdentifier(infoValue: "  ", fallback: "x") == "x")
    }

    @Test func unexpandedPlaceholderFallsBack() {
        #expect(AppConstants.resolvedIdentifier(infoValue: "$(RPPL_APP_GROUP_ID)", fallback: "x") == "x")
    }

    @Test func overrideWins() {
        #expect(
            AppConstants.resolvedIdentifier(infoValue: "group.nl.dcsbl.rppl.dev", fallback: "group.nl.dcsbl.rppl")
                == "group.nl.dcsbl.rppl.dev"
        )
    }

    @Test func testHostUsesProdDefaults() {
        #expect(AppConstants.appGroupID == AppConstants.prodAppGroupID)
        #expect(AppConstants.iCloudContainerIdentifier == AppConstants.prodICloudContainerIdentifier)
    }
}
