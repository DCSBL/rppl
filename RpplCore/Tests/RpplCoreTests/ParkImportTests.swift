import Foundation
import Testing
@testable import RpplCore

struct ParkImportTests {
    private static let html = """
    <!DOCTYPE html><html lang="nl"><head><title>Break Out &amp; Grunopark</title>
    <meta name="description" content="Waterskiën in Groningen">
    <script>var x = "<b>€ 99</b>";</script><style>p { color: red }</style></head>
    <body><nav><a href="/prijzen">Prijzen</a> <a href="/contact">Contact</a></nav>
    <h1>Welkom</h1><p>Kom skiën!</p>
    <h2>Prijzen</h2><table><tr><td>Waterskiën 1 uur</td><td>&euro; 24,-</td></tr>
    <tr><td>Dagkaart</td><td>€ 58,00</td></tr></table>
    <h2>Contact</h2><p>Hoofdweg 163, 9614 AD Harkstede</p>
    <p>Tel: <a href="tel:0505411706">050 - 541 17 06</a></p>
    <a href="mailto:info@breakout-grunopark.nl?subject=Hi">mail</a>
    <a href="https://www.instagram.com/breakoutgrunopark/#top">Instagram</a>
    <footer>KvK NL123456789B01</footer></body></html>
    """

    private static let page = ParkSourceExtractor.extract(html: html, url: "https://www.breakout-grunopark.nl/")

    // MARK: Reading a page

    @Test func pageIsReadIntoTitleBlocksAndFacts() {
        let page = Self.page
        #expect(page.title == "Break Out & Grunopark")
        #expect(page.blocks.first?.text == "Waterskiën in Groningen")
        #expect(!page.evidenceText.contains("99"))
        #expect(!page.evidenceText.contains("color"))
        let prices = page.blocks.first { $0.heading == "Prijzen" }
        #expect(prices?.text == "Waterskiën 1 uur | € 24,-\nDagkaart | € 58,00")
        #expect(page.phones.count == 1)
        #expect(page.emails == ["info@breakout-grunopark.nl"])
        #expect(page.links.contains(ParkSourceLink(url: "https://www.breakout-grunopark.nl/prijzen", label: "Prijzen")))
        #expect(page.links.contains { $0.url == "https://www.instagram.com/breakoutgrunopark/" })
    }

    @Test func navigationIsLeftOutOfTheText() {
        #expect(!Self.page.blocks.contains { $0.text.contains("Prijzen") && $0.heading.isEmpty })
    }

    @Test func registrationNumbersAreNoPhoneNumbers() {
        #expect(ParkSourceFacts.phones(in: "KvK NL123456789B01").isEmpty)
        #expect(ParkSourceFacts.phones(in: "Tel +31 (0)50 541 17 06").count == 1)
        #expect(ParkSourceFacts.phones(in: "Open 10.00-17.00 op 2026-10-05").isEmpty)
        #expect(ParkSourceFacts.emails(in: "Mail: Info@Park.nl.") == ["Info@Park.nl"])
        #expect(ParkSourceFacts.emails(in: "logo@2x.png").isEmpty)
    }

    @Test func screenshotTextBecomesParagraphs() {
        let page = ParkSourceExtractor.extract(plainText: "Prijzen\n1 uur € 24\n\nBel 050 541 17 06", label: "screenshot")
        #expect(page.blocks.count == 2)
        #expect(page.phones.count == 1)
    }

    // MARK: Chunks and pages

    @Test func textIsSortedIntoTopicChunks() {
        let chunks = ParkImportChunker.chunks(for: [Self.page])
        #expect(chunks.first { $0.topic == .prices }?.text.contains("Waterskiën 1 uur") == true)
        #expect(chunks.first { $0.topic == .contact }?.text.contains("Hoofdweg 163") == true)
        #expect(chunks.allSatisfy { $0.text.count <= ParkImportChunker.maxCharacters })
    }

    @Test func longTextIsCutIntoBoundedChunks() {
        let line = String(repeating: "Dagkaart € 58,00 ", count: 10)
        let block = ParkSourceBlock(heading: "Prijzen", text: Array(repeating: line, count: 60).joined(separator: "\n"))
        let chunks = ParkImportChunker.chunks(for: [ParkSourcePage(url: "x", blocks: [block])], topics: [.prices])
        #expect(chunks.count == ParkImportChunker.maxChunksPerTopic)
        #expect(chunks.allSatisfy { $0.text.count <= ParkImportChunker.maxCharacters })
    }

    @Test func onlyPagesOfTheSameSiteAreSuggested() {
        let candidates = ParkImportCrawler.candidates(from: Self.page, topics: [.prices], visited: [])
        #expect(candidates.map(\.url) == ["https://www.breakout-grunopark.nl/prijzen"])
        let visited = ParkImportCrawler.candidates(
            from: Self.page, topics: [.prices], visited: ["https://breakout-grunopark.nl/prijzen/"]
        )
        #expect(visited.isEmpty)
        #expect(ParkImportCrawler.siteHost("https://www.Park.nl/x") == "park.nl")
        #expect(ParkImportCrawler.siteHost("mailto:a@b.nl") == nil)
    }

    // MARK: Grounding

    @Test func amountsAreCheckedAgainstTheSource() {
        let grounding = ParkImportGrounding(pages: [Self.page])
        #expect(grounding.amount("24", quote: "Waterskiën 1 uur | € 24,-") == .verified)
        #expect(grounding.amount("58.00", quote: "Dagkaart gratis") == .weak)
        #expect(grounding.amount("25", quote: "Waterskiën 1 uur | € 24,-") == .notFound)
        #expect(grounding.amount("abc", quote: nil) == .notFound)
        #expect(grounding.amount("24", quote: "Waterskiën 1 uur 24 uur") == .weak)
    }

    @Test func contactValuesAreCheckedAgainstTheSource() {
        let grounding = ParkImportGrounding(pages: [Self.page])
        #expect(grounding.phone("+31 50 541 17 06"))
        #expect(!grounding.phone("+31 50 999 99 99"))
        #expect(grounding.email("INFO@breakout-grunopark.nl"))
        #expect(grounding.url("https://instagram.com/breakoutgrunopark"))
        #expect(grounding.text("hoofdweg 163, 9614 ad harkstede"))
        #expect(!grounding.text("Showers"))
    }

    // MARK: Proposals

    private func park() -> Park {
        Park(
            id: "p", name: "Break Out", location: ParkCoordinate(lat: 53.2, lon: 6.6),
            phone: "050 123 45 67",
            prices: [ParkPrice(name: "Dagkaart", options: [ParkPriceOption(amount: "50", currency: "EUR")])],
            links: [ParkLink(kind: "instagram", url: "https://www.instagram.com/breakoutgrunopark/")]
        )
    }

    private func candidates() -> ParkImportCandidates {
        var candidates = ParkImportCandidates(page: Self.page)
        candidates.address = "Hoofdweg 163, 9614 AD Harkstede"
        candidates.prices = [
            ParkImportCandidates.price(
                name: "Waterskiën 1 uur", amount: "€ 24,-", per: "Uur", note: "", quote: "Waterskiën 1 uur | € 24,-", currency: "EUR"
            ),
            ParkImportCandidates.price(
                name: "Dagkaart", amount: "58,00", per: "", note: "", quote: "Dagkaart | € 58,00", currency: "EUR"
            ),
            ParkImportCandidates.price(name: "Gratis", amount: "n/a", per: "", note: "", quote: "", currency: "EUR"),
        ].compactMap { $0 }
        candidates.facilities = ["Showers"]
        return candidates
    }

    @Test func proposalsAreDifferencesWithTheParkAndAreChecked() {
        let items = ParkImportMerge.items(from: candidates(), in: park(), grounding: ParkImportGrounding(pages: [Self.page]))
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["phone"]?.previous == "050 123 45 67")
        #expect(byID["phone"]?.level == .verified)
        #expect(byID["email"]?.level == .verified)
        #expect(byID["website"]?.title == "https://breakout-grunopark.nl")
        #expect(byID["address"]?.level == .verified)
        #expect(byID["link-instagram"] == nil)
        #expect(byID["price-waterskiën 1 uur"]?.level == .verified)
        #expect(byID["price-dagkaart"]?.previous == "Dagkaart: EUR 50")
        #expect(byID["price-gratis"] == nil)
        #expect(byID["facility-showers"]?.level == .notFound)
    }

    @Test func acceptedProposalsAreWrittenIntoThePark() {
        let items = ParkImportMerge.items(from: candidates(), in: park(), grounding: ParkImportGrounding(pages: [Self.page]))
        let result = ParkImportMerge.apply(items.filter { $0.level == .verified }, to: park())
        #expect(result.phone == "050 - 541 17 06")
        #expect(result.prices?.map(\.name) == ["Dagkaart", "Waterskiën 1 uur"])
        #expect(result.prices?.first?.options.first?.amount == "58")
        #expect(result.prices?.last?.options.first?.per == ParkPriceUnit.hour)
        #expect(result.facilities == nil)
        #expect(result.name == "Break Out")
    }

    @Test func questionsStayWithinTheClosedFieldList() {
        var bare = park()
        bare.phone = nil
        #expect(ParkImportMerge.questions(items: [], park: bare) == [.missing(.phone), .missing(.email), .missing(.address)])
        let items = ParkImportMerge.items(from: candidates(), in: bare, grounding: ParkImportGrounding(pages: [Self.page]))
        #expect(ParkImportMerge.questions(items: items, park: bare).isEmpty)
    }

    @Test func candidatesMergeWithoutOverwriting() {
        var first = ParkImportCandidates()
        first.phone = "1"
        var second = ParkImportCandidates()
        second.phone = "2"
        second.email = "a@b.nl"
        first.merge(second)
        #expect(first.phone == "1")
        #expect(first.email == "a@b.nl")
    }

    @Test func currencyAndUnitsAreRead() {
        #expect(ParkImportCandidates.currency(in: "Tickets CHF 20") == "CHF")
        #expect(ParkImportCandidates.currency(in: "€ 5") == "EUR")
        #expect(ParkImportCandidates.currency(in: "5", fallback: "GBP") == "GBP")
        #expect(ParkImportCandidates.unit("Stunde") == ParkPriceUnit.hour)
        #expect(ParkImportCandidates.unit("per season") == "per season")
        #expect(ParkImportCandidates.unit(" ") == nil)
    }
}
