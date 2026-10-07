import Foundation
import Testing
@testable import RpplCore

struct ParkLanguageTests {
    private let variants = ["nl": "per 2 uur", "fr": "pour 2 heures", "en": "per 2 hours"]

    @Test func baseDropsRegionAndCase() {
        #expect(ParkLanguage.base("fr-BE") == "fr")
        #expect(ParkLanguage.base("NL_be") == "nl")
        #expect(ParkLanguage.base("en") == "en")
    }

    @Test func readerLanguageWinsExactThenSameLanguage() {
        #expect(ParkLanguage.resolve(variants, fallback: nil, readerLanguages: ["fr-BE"], parkLanguages: ["nl"]) == "pour 2 heures")
        let regional = ["fr-BE": "BE", "fr": "plain"]
        #expect(ParkLanguage.resolve(regional, fallback: nil, readerLanguages: ["fr-BE"], parkLanguages: nil) == "BE")
    }

    @Test func fallsBackToParkMainThenEnglishThenPlainText() {
        let dutchEnglish = ["nl": "per uur", "en": "per hour"]
        #expect(ParkLanguage.resolve(dutchEnglish, fallback: nil, readerLanguages: ["de"], parkLanguages: ["nl", "en"]) == "per uur")
        #expect(ParkLanguage.resolve(dutchEnglish, fallback: nil, readerLanguages: ["de"], parkLanguages: nil) == "per hour")
        #expect(ParkLanguage.resolve(["nl": "per uur"], fallback: "x", readerLanguages: ["de"], parkLanguages: nil) == "x")
        #expect(ParkLanguage.resolve(nil, fallback: "per hour", readerLanguages: ["nl"], parkLanguages: ["nl"]) == "per hour")
    }

    @Test func tagValidation() {
        #expect(ParkLanguage.isValidTag("nl-BE"))
        #expect(ParkLanguage.isValidTag("en"))
        #expect(!ParkLanguage.isValidTag(""))
        #expect(!ParkLanguage.isValidTag("english language"))
    }

    private func park(prices: String, languages: String = "[nl-BE, fr-BE, en]") throws -> Park {
        let yaml = """
        version: 1
        id: p
        name: P
        languages: \(languages)
        location: { lat: 50.85, lon: 4.35 }
        prices:
          - name: Skis
            options:
              - \(prices)
        """
        return try ParkCatalog.parse(yaml: yaml, fallbackId: "p")
    }

    @Test func plainStringStaysPlain() throws {
        let parsed = try park(prices: "{ amount: '10', currency: EUR, per: hour }")
        let option = try #require(parsed.prices?.first?.options.first)
        #expect(option.per == "hour")
        #expect(option.perByLanguage == nil)
        #expect(try ParkCatalog.encode(parsed).contains("per: hour"))
    }

    @Test func mapDecodesKeepsEnglishAsPlainAndRoundTrips() throws {
        let parsed = try park(prices: "{ amount: '15', currency: EUR, per: { nl: per 2 uur, fr: pour 2 heures, en: per 2 hours }, note: { nl: kinderen, en: kids } }")
        let option = try #require(parsed.prices?.first?.options.first)
        #expect(option.per == "per 2 hours")
        #expect(option.perByLanguage?["fr"] == "pour 2 heures")
        #expect(option.resolvedPer(readerLanguages: ["nl-NL"], parkLanguages: parsed.languages) == "per 2 uur")
        #expect(option.resolvedNote(readerLanguages: ["fr"], parkLanguages: ["nl-BE", "en"]) == "kinderen")
        #expect(option.resolvedNote(readerLanguages: ["de"], parkLanguages: nil) == "kids")
        let again = try ParkCatalog.parse(yaml: try ParkCatalog.encode(parsed), fallbackId: "p")
        #expect(again == parsed)
    }

    @Test func parkLanguagesRoundTrip() throws {
        let parsed = try park(prices: "{ amount: '1', currency: EUR }")
        #expect(parsed.languages == ["nl-BE", "fr-BE", "en"])
    }

    @Test func finalizedDropsBlankVariantsAndBadTags() {
        var park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 50.85, lon: 4.35))
        park.languages = ["nl", "en"]
        park.prices = [ParkPrice(name: "Skis", options: [
            ParkPriceOption(amount: "15", per: "per 2 hours", perByLanguage: ["nl": "per 2 uur", "en": "per 2 hours", "xx yy": "bad", "fr": "  "]),
        ])]
        let option = ParkDraft.finalized(park).prices?.first?.options.first
        #expect(option?.perByLanguage == ["nl": "per 2 uur", "en": "per 2 hours"])
    }
}
