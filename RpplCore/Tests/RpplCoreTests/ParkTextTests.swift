import Foundation
import Testing
@testable import RpplCore

struct ParkTextTests {
    @Test func keepsAnyScriptEmojiAndAccents() {
        for text in ["Café Ünï", "كابل بارك", "שלום עולם", "ケーブルパーク", "🏄‍♂️ Wake 🌊", "👨‍👩‍👧 family", "🇳🇱 NL", "مرحبا Park"] {
            #expect(ParkText.sanitizeTyping(text, field: .name) == text)
            #expect(ParkText.finalize(text, field: .name) == text)
        }
    }

    @Test func keepsScotlandFlagButDropsHiddenTags() {
        let scotland = "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        #expect(ParkText.sanitizeTyping(scotland, field: .name) == scotland)
        #expect(ParkText.sanitizeTyping("hi\u{E0041}\u{E0042}", field: .name) == "hi")
    }

    @Test func stripsControlAndBidiOverrides() {
        #expect(ParkText.sanitizeTyping("a\u{0000}b\u{0007}c\u{001B}d\u{007F}e", field: .name) == "abcde")
        #expect(ParkText.sanitizeTyping("admin\u{202E}gpj.exe", field: .name) == "admingpj.exe")
        #expect(ParkText.sanitizeTyping("\u{FEFF}Park\u{FFFE}", field: .name) == "Park")
        #expect(ParkText.sanitizeTyping("a\u{E000}b", field: .name) == "ab")
        #expect(ParkText.sanitizeTyping("a\u{200F}b", field: .name) == "a\u{200F}b") // right-to-left mark stays
    }

    @Test func lineBreaksFollowTheField() {
        #expect(ParkText.sanitizeTyping("one\ntwo\r\nthree\u{2028}four", field: .name) == "one two three four")
        #expect(ParkText.sanitizeTyping("one\ntwo\r\nthree\u{2028}four", field: .description) == "one\ntwo\nthree\nfour")
        #expect(ParkText.sanitizeTyping("a\tb", field: .name) == "a b")
    }

    @Test func cutsAtTheLimitWithoutSplittingEmoji() {
        let long = String(repeating: "🏄‍♂️", count: 100)
        let cut = ParkText.sanitizeTyping(long, field: .name)
        #expect(cut.count == ParkTextField.name.maxLength)
        #expect(cut == String(repeating: "🏄‍♂️", count: ParkTextField.name.maxLength))
        #expect(ParkText.overflow(long, field: .name) == 20)
        #expect(ParkText.overflow("short", field: .name) == 0)
    }

    @Test func finalizeTrimsAndDropsEmpty() {
        #expect(ParkText.finalize("  Park   North  ", field: .name) == "Park North")
        #expect(ParkText.finalize("   ", field: .name) == nil)
        #expect(ParkText.finalize(nil, field: .name) == nil)
        #expect(ParkText.finalize("\u{0000}\n", field: .description) == nil)
    }

    @Test func markdownKeepsEmphasisAndListsButNotHeadings() {
        let input = """
        # Welcome
        A **bold** and _italic_ start, with *stars*.

        ---
        - rails
        - kickers
        ## Details
        #wakeboard stays
        <script>alert(1)</script>Done
        ===


        Last
        """
        let output = ParkText.finalize(input, field: .description)
        #expect(output == """
        Welcome
        A **bold** and _italic_ start, with *stars*.

        - rails
        - kickers
        Details
        #wakeboard stays
        alert(1)Done

        Last
        """)
    }

    @Test func phoneAndEmailChecks() {
        #expect(ParkText.phoneIssue("") == nil)
        #expect(ParkText.phoneIssue("010 - 2600 110") == nil)
        #expect(ParkText.phoneIssue("+31 (0)10 260 0110") == nil)
        #expect(ParkText.phoneIssue("12345") == .tooFewDigits)
        #expect(ParkText.phoneIssue("call me") == .badCharacters)
        #expect(ParkText.phoneIssue(String(repeating: "1", count: 20)) == .tooManyDigits)
        #expect(ParkText.emailIssue("info@park.nl") == nil)
        #expect(ParkText.emailIssue("info@sub.park.nl") == nil)
        #expect(ParkText.emailIssue("jörg@bücher.de") == nil)
        #expect(ParkText.emailIssue("info.park.nl") == .missingAt)
        #expect(ParkText.emailIssue("a@b@c.nl") == .missingAt)
        #expect(ParkText.emailIssue("@park.nl") == .missingAt)
        #expect(ParkText.emailIssue("info@park") == .missingDomain)
        #expect(ParkText.emailIssue("info@.nl") == .missingDomain)
        #expect(ParkText.emailIssue("in valid@park.nl") == .hasSpaces)
    }

    @Test func webAddresses() {
        #expect(ParkText.normalizedWebAddress("park.nl") == "https://park.nl")
        #expect(ParkText.normalizedWebAddress("www.park.nl/menu") == "https://www.park.nl/menu")
        #expect(ParkText.normalizedWebAddress("http://park.nl") == "http://park.nl")
        #expect(ParkText.normalizedWebAddress("  https://park.nl/a?b=c#d ") == "https://park.nl/a?b=c#d")
        #expect(ParkText.normalizedWebAddress("park.nl:8080/menu") == "https://park.nl:8080/menu")
        #expect(ParkText.normalizedWebAddress("javascript:alert(1)") == nil)
        #expect(ParkText.normalizedWebAddress("mailto:a@b.nl") == nil)
        #expect(ParkText.normalizedWebAddress("ftp://park.nl") == nil)
        #expect(ParkText.normalizedWebAddress("park") == nil)
        #expect(ParkText.normalizedWebAddress("my park.nl") == nil)
        #expect(ParkText.normalizedWebAddress("") == nil)
        #expect(ParkText.normalizedWebAddress("https://" + String(repeating: "a", count: 600) + ".nl") == nil)
    }

    @Test func oddTextSurvivesYAMLRoundTrip() throws {
        let tricky = ["yes", "null", "~", "12:30", "2026-10-04", "- item", "a: b", "# not a comment", "\"quoted\"",
                      "multi\nline", "كابل بارك", "🏄‍♂️", "tab\there", "'single'", "{braces}", "*star", "&anchor", "!tag", "%dir"]
        for text in tricky {
            var park = Park(id: "p", name: text, location: ParkCoordinate(lat: 52, lon: 4))
            park.description = text
            park.facilities = [text]
            park.prices = [ParkPrice(name: text, options: [ParkPriceOption(amount: "1", currency: "EUR", per: LocalizedText(text), note: LocalizedText(text))])]
            let decoded = try ParkCatalog.parse(yaml: ParkCatalog.encode(park), fallbackId: "p")
            #expect(decoded == park, "\(text)")
        }
    }
}
