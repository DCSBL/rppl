import Foundation
import Testing
@testable import RpplCore

@Suite("SessionShareMail")
struct SessionShareMailTests {
    private static func bytes(_ count: Int) -> Data {
        Data((0..<count).map { UInt8($0 % 251) })
    }

    @Test func mailAvailableAttachesTheFileWhateverItsSize() {
        #expect(SessionShareMail.route(canSendMail: true, fileByteCount: 0) == .attachment)
        #expect(SessionShareMail.route(canSendMail: true, fileByteCount: 50_000_000) == .attachment)
    }

    @Test func withoutMailASmallFileGoesInTheBodyAsBase64() {
        #expect(SessionShareMail.route(canSendMail: false, fileByteCount: 10_000) == .base64Body)
    }

    @Test func withoutMailABigFileGoesToTheShareSheet() {
        #expect(SessionShareMail.route(canSendMail: false, fileByteCount: 5_000_000) == .shareSheet)
    }

    @Test func bodyLimitIsInclusive() {
        // Largest byte count whose body still fits, and the next one up.
        var fits = 0
        while SessionShareMail.base64BodyLength(forByteCount: fits + 1) <= SessionShareMail.maxBase64BodyLength {
            fits += 1
        }
        #expect(SessionShareMail.route(canSendMail: false, fileByteCount: fits) == .base64Body)
        #expect(SessionShareMail.route(canSendMail: false, fileByteCount: fits + 1) == .shareSheet)
    }

    @Test(arguments: [1, 2, 3, 57, 58, 100, 1_000, 12_345, 60_000])
    func base64BodyRoundTripsAndStaysWithinTheEstimate(byteCount: Int) throws {
        let data = Self.bytes(byteCount)
        let body = SessionShareMail.base64Body(for: data)
        #expect(body.utf8.count <= SessionShareMail.base64BodyLength(forByteCount: byteCount))
        let decoded = try #require(Data(base64Encoded: body, options: .ignoreUnknownCharacters))
        #expect(decoded == data)
        for line in body.split(separator: "\n") {
            #expect(line.count <= 76)
        }
    }

    @Test func mailtoLinkCarriesSubjectAndBodyIntact() throws {
        let subject = "Rppl session — 3 sets & 5 laps"
        let body = "Hi Rppl,\n\nbase64: a+b/c==\nüñí"
        let url = try #require(
            SessionShareMail.mailtoURL(recipient: "rppl@dcsbl.nl", subject: subject, body: body)
        )
        #expect(url.scheme == "mailto")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "rppl@dcsbl.nl")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == subject)
        #expect(items["body"] == body)
    }

    /// Some mail apps read a raw `+` as a space, which would corrupt base64.
    @Test func mailtoLinkNeverCarriesARawPlus() throws {
        let url = try #require(
            SessionShareMail.mailtoURL(recipient: "rppl@dcsbl.nl", subject: "a+b", body: "++//==")
        )
        let text = url.absoluteString
        #expect(!text.contains("+"))
        #expect(text.contains("%2B%2B%2F%2F%3D%3D"))
    }

    @Test func mailtoLinkOfABase64BodyRoundTrips() throws {
        let data = Self.bytes(2_000)
        let body = SessionShareMail.base64Body(for: data)
        let url = try #require(SessionShareMail.mailtoURL(recipient: "rppl@dcsbl.nl", subject: "s", body: body))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let received = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(Data(base64Encoded: received, options: .ignoreUnknownCharacters) == data)
    }
}
