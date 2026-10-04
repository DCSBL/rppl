import Foundation
import Testing
@testable import RpplCore

struct ParkPriceParserTests {
    private func price(_ text: String) -> ParsedPrice? {
        if case .price(let parsed) = ParkPriceParser.parse(text) { return parsed }
        return nil
    }

    @Test func readsCommonWritings() {
        #expect(price("€12,34") == ParsedPrice(amount: 12.34, currency: "EUR"))
        #expect(price("12.34") == ParsedPrice(amount: 12.34))
        #expect(price("€ 25") == ParsedPrice(amount: 25, currency: "EUR"))
        #expect(price("EUR 25,50") == ParsedPrice(amount: 25.5, currency: "EUR"))
        #expect(price("25 chf") == ParsedPrice(amount: 25, currency: "CHF"))
        #expect(price("$12.5") == ParsedPrice(amount: 12.5, currency: "USD"))
        #expect(price("£7") == ParsedPrice(amount: 7, currency: "GBP"))
        #expect(price("7,5") == ParsedPrice(amount: 7.5))
    }

    @Test func readsThousandsMarks() {
        #expect(price("€ 1.234,56") == ParsedPrice(amount: 1234.56, currency: "EUR"))
        #expect(price("1,234.56") == ParsedPrice(amount: 1234.56))
        #expect(price("€1.234") == ParsedPrice(amount: 1234, currency: "EUR"))
        #expect(price("1 234,50") == ParsedPrice(amount: 1234.5))
        #expect(price("1\u{00A0}234") == ParsedPrice(amount: 1234))
        #expect(price("1'234") == ParsedPrice(amount: 1234))
        #expect(price("12.345") == ParsedPrice(amount: 12345))
    }

    @Test func dutchWholeAmountsWithDash() {
        #expect(price("12,-") == ParsedPrice(amount: 12))
        #expect(price("€ 12,--") == ParsedPrice(amount: 12, currency: "EUR"))
        #expect(price("€12.=") == ParsedPrice(amount: 12, currency: "EUR"))
    }

    @Test func negativeAmountsAreDiscounts() {
        #expect(price("-€3") == ParsedPrice(amount: -3, currency: "EUR"))
        #expect(price("€-3") == ParsedPrice(amount: -3, currency: "EUR"))
        #expect(price("\u{2212} € 2") == ParsedPrice(amount: -2, currency: "EUR"))
        #expect(price("–2,50") == ParsedPrice(amount: -2.5))
        #expect(price("+5") == ParsedPrice(amount: 5))
    }

    @Test func readsUnits() {
        #expect(price("€7 pp") == ParsedPrice(amount: 7, currency: "EUR", per: ParkPriceUnit.person))
        #expect(price("-€3 pp") == ParsedPrice(amount: -3, currency: "EUR", per: ParkPriceUnit.person))
        #expect(price("€7 p.p.") == ParsedPrice(amount: 7, currency: "EUR", per: ParkPriceUnit.person))
        #expect(price("€7 per persoon") == ParsedPrice(amount: 7, currency: "EUR", per: ParkPriceUnit.person))
        #expect(price("7/person") == ParsedPrice(amount: 7, per: ParkPriceUnit.person))
        #expect(price("€10 per hour") == ParsedPrice(amount: 10, currency: "EUR", per: ParkPriceUnit.hour))
        #expect(price("€10/h") == ParsedPrice(amount: 10, currency: "EUR", per: ParkPriceUnit.hour))
        #expect(price("€10 per uur") == ParsedPrice(amount: 10, currency: "EUR", per: ParkPriceUnit.hour))
        #expect(price("€25 per day") == ParsedPrice(amount: 25, currency: "EUR", per: ParkPriceUnit.day))
        #expect(price("€25 per dag") == ParsedPrice(amount: 25, currency: "EUR", per: ParkPriceUnit.day))
        #expect(price("€25 per session") == ParsedPrice(amount: 25, currency: "EUR", per: ParkPriceUnit.session))
    }

    @Test func rejectsWhatIsNotOnePrice() {
        #expect(ParkPriceParser.parse("") == .empty)
        #expect(ParkPriceParser.parse("   ") == .empty)
        #expect(ParkPriceParser.parse("free") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("€") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("€ 5 / € 7,50 / € 10") == .invalid(.severalAmounts))
        #expect(ParkPriceParser.parse("5 7") == .invalid(.severalAmounts))
        #expect(ParkPriceParser.parse("€1,234.567") == .invalid(.tooManyDecimals))
        #expect(ParkPriceParser.parse("12,345678") == .invalid(.tooManyDecimals))
        #expect(ParkPriceParser.parse("999999") == .invalid(.tooLarge))
        #expect(ParkPriceParser.parse("12abc") == .invalid(.unreadable))
        #expect(ParkPriceParser.parse("1,,2") == .invalid(.unreadable))
    }

    @Test func pricePerHourFromDurationOrUnit() {
        #expect(ParkPrice(name: "Block", amount: 29, minutes: 90).amountPerHour.map { ($0 * 100).rounded() / 100 } == 19.33)
        #expect(ParkPrice(name: "Rental", amount: 6, per: ParkPriceUnit.hour).amountPerHour == 6)
        #expect(ParkPrice(name: "Day pass", amount: 55, per: ParkPriceUnit.day).amountPerHour == nil)
        #expect(ParkPrice(name: "Draft").amountPerHour == nil)
    }

    @Test func decimalAmountIsRoundedToCents() {
        #expect(ParkPrice(name: "A", amount: 12.34).decimalAmount == Decimal(string: "12.34"))
        #expect(ParkPrice(name: "A", amount: 0.1 + 0.2).decimalAmount == Decimal(string: "0.3"))
        #expect(ParkPrice(name: "A").decimalAmount == nil)
        #expect(ParkPrice(name: "A", amount: -3).isDiscount)
        #expect(!ParkPrice(name: "A", amount: 3).isDiscount)
    }

    @Test func pricesRoundTripThroughYAMLAsNumbers() throws {
        var park = Park(id: "p", name: "P", location: ParkCoordinate(lat: 52, lon: 4))
        park.prices = [
            ParkPrice(name: "Day pass", amount: 25, currency: "EUR", per: ParkPriceUnit.person, minutes: 90, note: "Adults"),
            ParkPrice(name: "Group", amount: -3.5, currency: "EUR"),
            ParkPrice(name: "Draft"),
        ]
        let yaml = try ParkCatalog.encode(park)
        #expect(!yaml.contains("price:"))
        let decoded = try ParkCatalog.parse(yaml: yaml, fallbackId: "p")
        #expect(decoded.prices == park.prices)
        let whole = try ParkCatalog.parse(
            yaml: "version: 1\nid: a\nname: A\nlocation: { lat: 1, lon: 2 }\nprices:\n  - { name: Pass, amount: 25, currency: EUR }\n",
            fallbackId: "a"
        )
        #expect(whole.prices?.first?.amount == 25)
    }

    @Test func everyBundledPriceIsNumeric() {
        for park in ParkCatalog.loadBundled() {
            for price in park.prices ?? [] {
                #expect(price.amount != nil, "\(park.id): \(price.name)")
                #expect(price.currency == "EUR", "\(park.id): \(price.name)")
            }
        }
    }
}
