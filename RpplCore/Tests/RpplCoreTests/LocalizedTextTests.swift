import Foundation
import Testing
@testable import RpplCore

struct LocalizedTextTests {
    private let perTwoHours = LocalizedText(
        "per 2 hours", variants: ["nl": "per 2 uur", "fr": "pour 2 heures", "en": "per 2 hours"]
    )

    @Test func readerLanguageMatchesOnLanguageCode() {
        #expect(perTwoHours.resolved(parkLanguages: ["nl"], readerLanguages: ["fr-BE"]) == "pour 2 heures")
        #expect(perTwoHours.resolved(parkLanguages: nil, readerLanguages: ["NL_be"]) == "per 2 uur")
    }

    @Test func fallsBackToParkMainThenEnglishThenText() {
        let dutchEnglish = LocalizedText("per hour", variants: ["nl": "per uur", "en": "per hour"])
        #expect(dutchEnglish.resolved(parkLanguages: ["nl", "en"], readerLanguages: ["de"]) == "per uur")
        #expect(dutchEnglish.resolved(parkLanguages: nil, readerLanguages: ["de"]) == "per hour")
        #expect(LocalizedText("x", variants: ["nl": "per uur"]).resolved(parkLanguages: nil, readerLanguages: ["de"]) == "x")
        #expect(LocalizedText("per hour").resolved(parkLanguages: ["nl"], readerLanguages: ["nl"]) == "per hour")
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
        #expect(option.per?.variants.isEmpty == true)
        #expect(try ParkCatalog.encode(parsed).contains("per: hour"))
    }

    @Test func mapDecodesKeepsEnglishAsTextAndRoundTrips() throws {
        let parsed = try park(prices: "{ amount: '15', currency: EUR, per: { nl: per 2 uur, fr: pour 2 heures, en: per 2 hours }, note: { nl: kinderen, en: kids } }")
        let option = try #require(parsed.prices?.first?.options.first)
        #expect(option.per?.text == "per 2 hours")
        #expect(option.per?.variants["fr"] == "pour 2 heures")
        #expect(option.per?.resolved(parkLanguages: parsed.languages, readerLanguages: ["nl-NL"]) == "per 2 uur")
        #expect(option.note?.resolved(parkLanguages: ["nl-BE", "en"], readerLanguages: ["fr"]) == "kinderen")
        #expect(option.note?.resolved(parkLanguages: nil, readerLanguages: ["de"]) == "kids")
        let again = try ParkCatalog.parse(yaml: try ParkCatalog.encode(parsed), fallbackId: "p")
        #expect(again == parsed)
    }

    @Test func parkLanguagesDecode() throws {
        #expect(try park(prices: "{ amount: '1', currency: EUR }").languages == ["nl-BE", "fr-BE", "en"])
    }

    @Test func bundledDutchParksShowEnglishToEnglishReaders() throws {
        for id in ["betuwestrand-beesd", "deberendonck-wijchen"] {
            let park = try #require(ParkCatalog.loadBundled().first { $0.id == id })
            #expect(park.languages == ["nl", "en"])
            let withVariants = (park.prices ?? []).flatMap(\.options).compactMap(\.per).filter { !$0.variants.isEmpty }
            #expect(!withVariants.isEmpty)
            for per in withVariants {
                #expect(per.resolved(parkLanguages: park.languages, readerLanguages: ["nl-NL"]) == per.variants["nl"])
                #expect(per.resolved(parkLanguages: park.languages, readerLanguages: ["en-GB"]) == per.variants["en"])
            }
        }
    }

    @Test func finalizedCleansTextAndDropsBlankVariants() {
        var park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 50.85, lon: 4.35))
        park.prices = [ParkPrice(name: "Skis", options: [
            ParkPriceOption(amount: "15", per: LocalizedText(" per 2  hours ", variants: ["nl": "per 2 uur", "fr": "  "])),
        ])]
        let per = ParkDraft.finalized(park).prices?.first?.options.first?.per
        #expect(per == LocalizedText("per 2 hours", variants: ["nl": "per 2 uur"]))
    }
}
