import Testing
@testable import RpplCore

struct AppVersionInfoTests {
    private let stamped: [String: Any] = [
        "CFBundleShortVersionString": "2026.10.1",
        "CFBundleVersion": "312",
        "RpplBuildDate": "2026-10-04",
        "RpplReleaseTag": "2026.10.1-beta.2",
        "RpplGitCommit": "abc1234"
    ]

    @Test func stampedReleaseShowsTagBuildAndCommit() {
        let info = AppVersionInfo(infoDictionary: stamped)
        #expect(info.headline == "2026.10.1-beta.2 (312)")
        #expect(info.detail == "abc1234 · 2026-10-04")
    }

    @Test func localBuildFallsBackToMarketingVersionWithoutCommit() {
        var local = stamped
        local["RpplReleaseTag"] = ""
        local["RpplGitCommit"] = ""
        let info = AppVersionInfo(infoDictionary: local)
        #expect(info.headline == "2026.10.1 (312)")
        #expect(info.detail == "2026-10-04")
    }

    @Test func stampedCommitLinksToItsCommitPage() {
        let info = AppVersionInfo(infoDictionary: stamped)
        #expect(info.sourceURL.absoluteString == "https://github.com/DCSBL/rppl/commit/abc1234")
    }

    @Test func localBuildLinksToRepository() {
        var local = stamped
        local["RpplGitCommit"] = ""
        let info = AppVersionInfo(infoDictionary: local)
        #expect(info.sourceURL == AppVersionInfo.repositoryURL)
        #expect(info.sourceURL.absoluteString == "https://github.com/DCSBL/rppl")
    }

    @Test func missingKeysAreNotHiddenBehindEmptyText() {
        let info = AppVersionInfo(infoDictionary: nil)
        #expect(info.headline == "- (-)")
        #expect(info.detail == "-")
    }

    @Test func whitespaceOnlyStampsCountAsMissing() {
        var padded = stamped
        padded["RpplGitCommit"] = "  \n"
        padded["RpplReleaseTag"] = " 2026.10.1 "
        let info = AppVersionInfo(infoDictionary: padded)
        #expect(info.gitCommit == nil)
        #expect(info.releaseTag == "2026.10.1")
    }
}
