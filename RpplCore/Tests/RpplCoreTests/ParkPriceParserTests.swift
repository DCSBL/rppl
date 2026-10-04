import Foundation
import Testing
@testable import RpplCore

struct ParkPriceParserTests {
    private func text(_ input: String) -> String? {
        if case .amount(let parsed) = ParkPriceParser.parse(input) { return parsed.text }
        return nil
    }

    @Test func readsCommonWritings() {
        #expect(text("12,34") == "12.34")
        #expect(text("12.34") == "12.34")
        #expect(text("25") == "25")
        #expect(text("7,5") == "7.50")
        #expect(text("007") == "7")
        #expect(text("25,00") == "25")
        #expect(text("0,5") == "0.50")
    }

    @Test func ignoresCurrencySigns() {
        #expect(text("€12,34") == "12.34")
        #expect(text("€ 25") == "25")
        #expect(text("$12.5") == "12.50")
        #expect(text("12 £") == "12")
    }

    @Test func readsThousandsMarks() {
        #expect(text("1.234,56") == "1234.56")
        #expect(text("1,234.56") == "1234.56")
        #expect(text("1.234") == "1234")
        #expect(text("1 234,50") == "1234.50")
        #expect(text("1\u{00A0}234") == "1234")
        #expect(text("1'234") == "1234")
        #expect(text("12.345") == "12345")
    }

    @Test func dutchWholeAmountsWithDash() {
        #expect(text("12,-") == "12")
        #expect(text("€ 12,--") == "12")
        #expect(text("12.=") == "12")
    }

    @Test func negativeAmountsAreDiscounts() {
        #expect(text("-3") == "-3")
        #expect(text("-€3") == "-3")
        #expect(text("€-3") == "-3")
        #expect(text("\u{2212} 2") == "-2")
        #expect(text("–2,50") == "-2.50")
        #expect(text("+5") == "5")
        #expect(text("-0") == "0")
    }

    @Test func rejectsWhatIsNotOneAmount() {
        #expect(ParkPriceParser.parse("") == .empty)
        #expect(ParkPriceParser.parse("   ") == .empty)
        #expect(ParkPriceParser.parse("€") == .empty)
        #expect(ParkPriceParser.parse("free") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("-") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("5 / 7,50") == .invalid(.severalAmounts))
        #expect(ParkPriceParser.parse("5 7") == .invalid(.severalAmounts))
        #expect(ParkPriceParser.parse("€1,234.567") == .invalid(.tooManyDecimals))
        #expect(ParkPriceParser.parse("12,345678") == .invalid(.tooManyDecimals))
        #expect(ParkPriceParser.parse("999999") == .invalid(.tooLarge))
        #expect(ParkPriceParser.parse("12abc") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("1,,2") == .invalid(.unreadable))
    }

    @Test func canonicalTextFromANumber() {
        #expect(ParkPriceParser.canonicalText(for: 25) == "25")
        #expect(ParkPriceParser.canonicalText(for: 12.5) == "12.50")
        #expect(ParkPriceParser.canonicalText(for: -3) == "-3")
        #expect(ParkPriceParser.canonicalText(for: 0.1 + 0.2) == "0.30")
    }

    @Test func optionHelpers() {
        let option = ParkPriceOption(amount: "12.34", currency: "EUR")
        #expect(option.decimal == Decimal(string: "12.34"))
        #expect(option.value == 12.34)
        #expect(!option.isDiscount)
        #expect(ParkPriceOption(amount: "-3").isDiscount)
        #expect(ParkPriceOption().isBlank)
        #expect(ParkPriceOption(per: "per season").isBlank == false)
        #expect(ParkPriceOption().decimal == nil)
    }

    @Test func pricesRoundTripThroughYAMLAsText() throws {
        var park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 52, lon: 4))
        park.prices = [
            ParkPrice(name: "Skis", options: [
                ParkPriceOption(amount: "10", currency: "EUR", per: "1 hour"),
                ParkPriceOption(amount: "15", currency: "EUR", per: "2 hours", note: "own gear"),
            ]),
            ParkPrice(name: "Group discount", options: [ParkPriceOption(amount: "-3.50", currency: "EUR", per: ParkPriceUnit.person)]),
            ParkPrice(name: "Draft"),
        ]
        let yaml = try ParkCatalog.encode(park)
        #expect(yaml.contains("-3.50"))
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "p")
        #expect(decoded.prices == park.prices)
    }

    @Test func aPlainYAMLNumberReadsAsAmount() throws {
        let park = try ParkCatalog.parse(
            yaml: "version: 1\nid: a\nname: A\nlocation: { lat: 1, lon: 2 }\nprices:\n  - name: Pass\n    options:\n      - { amount: 25, currency: EUR }\n      - { amount: 7.5, currency: EUR }\n",
            fallbackId: "a"
        )
        #expect(park.prices?.first?.options.map(\.amount) == ["25", "7.50"])
    }

    @Test func everyBundledPriceHasAnAmountAndCurrency() {
        var count = 0
        for park in ParkCatalog.loadBundled() {
            for price in park.prices ?? [] {
                #expect(!price.options.isEmpty, "\(park.id): \(price.name)")
                for option in price.options {
                    count += 1
                    if case .amount = ParkPriceParser.parse(option.amount ?? "") {} else {
                        Issue.record("\(park.id): \(price.name) has no readable amount")
                    }
                    #expect(option.currency == "EUR", "\(park.id): \(price.name)")
                }
            }
        }
        #expect(count > 100)
    }

    @Test func similarPricesAreGroupedInBundledData() throws {
        let park = try #require(ParkCatalog.loadBundled().first { $0.id == "downunder-nieuwegein" })
        let wetsuit = try #require(park.prices?.first { $0.name == "Wetsuit rental" })
        #expect(wetsuit.options.map(\.amount) == ["5", "7.50", "10"])
        #expect(wetsuit.options.map(\.per) == ["1 hour", "2 hours", ParkPriceUnit.day])
        #expect(park.prices?.filter { $0.name == "Wetsuit rental" }.count == 1)
    }
}
