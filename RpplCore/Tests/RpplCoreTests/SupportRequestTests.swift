import Testing
@testable import RpplCore

@Suite("Support request mail")
struct SupportRequestTests {
    private let request = SupportRequest(
        appVersion: "2026.10.1-beta.2 (312)",
        deviceModel: "iPhone17,1",
        systemVersion: "26.0"
    )

    @Test func subjectIsEnglish() {
        #expect(SupportRequest.subject == "I have a question or comment about Rppl")
    }

    @Test func bodyListsDetailsBelowWritingSpace() throws {
        let body = request.body
        #expect(body.contains("App version: 2026.10.1-beta.2 (312)"))
        #expect(body.contains("Device: iPhone17,1"))
        #expect(body.contains("iOS version: 26.0"))
        let prompt = try #require(body.range(of: "Please describe"))
        let details = try #require(body.range(of: "App version:"))
        #expect(prompt.lowerBound < details.lowerBound)
    }
}
