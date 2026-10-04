import Foundation

/// What the About footer shows, read from Info.plist values.
///
/// The release build stamps `RpplReleaseTag` (the GitHub release tag without a leading `v`, for
/// example `2026.10.1-beta.2`) and `RpplGitCommit` (short SHA) into the CI checkout only, see
/// Docs/Release.md. Local builds leave them empty and fall back to the marketing version.
public struct AppVersionInfo: Equatable, Sendable {
    public static let missing = "-"

    /// Source repository. Private for now; the link 404s until the repo goes public.
    public static let repositoryURL = URL(string: "https://github.com/DCSBL/rppl")!

    public var marketingVersion: String
    public var build: String
    public var buildDate: String
    public var releaseTag: String?
    public var gitCommit: String?

    public init(infoDictionary: [String: Any]?) {
        marketingVersion = Self.value(infoDictionary, "CFBundleShortVersionString") ?? Self.missing
        build = Self.value(infoDictionary, "CFBundleVersion") ?? Self.missing
        buildDate = Self.value(infoDictionary, "RpplBuildDate") ?? Self.missing
        releaseTag = Self.value(infoDictionary, "RpplReleaseTag")
        gitCommit = Self.value(infoDictionary, "RpplGitCommit")
    }

    /// `2026.10.1-beta.2 (312)`: the release tag when stamped, else the marketing version.
    public var headline: String {
        "\(releaseTag ?? marketingVersion) (\(build))"
    }

    /// `abc1234 · 2026-10-04`; the commit is left out on local builds.
    public var detail: String {
        [gitCommit, buildDate].compactMap { $0 }.joined(separator: " · ")
    }

    /// The commit page on GitHub when a commit is stamped, else the repository root.
    public var sourceURL: URL {
        guard let gitCommit else { return Self.repositoryURL }
        return Self.repositoryURL
            .appendingPathComponent("commit")
            .appendingPathComponent(gitCommit)
    }

    private static func value(_ dictionary: [String: Any]?, _ key: String) -> String? {
        guard let raw = dictionary?[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
