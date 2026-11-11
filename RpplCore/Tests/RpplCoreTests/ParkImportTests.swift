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
        #expect(ParkImportMerge.questions(items: [], park: bare) == [.missing(.phone), .missing(.email), .missing(.address), .missing(.opening)])
        let items = ParkImportMerge.items(from: candidates(), in: bare, grounding: ParkImportGrounding(pages: [Self.page]))
        #expect(ParkImportMerge.questions(items: items, park: bare) == [.missing(.opening)])
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

    // MARK: Opening hours

    private static let hoursPage = ParkSourceExtractor.extract(
        html: """
        <html><head><title>Openingstijden | Project 7</title></head><body>
        <h1>Openingstijden</h1>
        <h2>April</h2><table>
        <tr><td>Maandag t/m vrijdag</td><td>Gesloten</td></tr>
        <tr><td>Zaterdag en zondag</td><td>12:30 - 17:00 uur</td></tr></table>
        <h2>Mei t/m september</h2>
        <p>Ma - vr: 13.00 tot 21.00 uur</p><p>Za, zo 10:00-21:00</p>
        </body></html>
        """,
        url: "https://www.project7cablepark.nl/openingstijden/"
    )

    @Test func openingHoursAreReadIntoRules() {
        let finding = ParkOpeningReader.read([Self.hoursPage])
        #expect(finding?.rules == [
            ParkOpeningRule(months: [4], days: ["weekend"], open: "12:30", close: "17:00"),
            ParkOpeningRule(months: [5, 6, 7, 8, 9], days: ["weekdays"], open: "13:00", close: "21:00"),
            ParkOpeningRule(months: [5, 6, 7, 8, 9], days: ["weekend"], open: "10:00", close: "21:00"),
        ])
        #expect(finding?.sourceURL == "https://www.project7cablepark.nl/openingstijden/")
        #expect(finding?.lines.count == 3)
    }

    @Test func timesNeedMinutesOrAWordForHours() {
        func read(_ line: String) -> [String] {
            ParkOpeningReader.timeRanges(in: line).map { "\($0.open)-\($0.close)" }
        }
        #expect(read("10-12-2025").isEmpty)
        #expect(read("10 - 18 uur") == ["10:00-18:00"])
        #expect(read("12h30 - 17h00") == ["12:30-17:00"])
        #expect(read("10:00 - 12:00 en 13:00 - 17:00") == ["10:00-12:00", "13:00-17:00"])
        #expect(read("Mo-Fr 9.00 bis 18.00 Uhr") == ["09:00-18:00"])
        #expect(read("25:00 - 26:00").isEmpty)
    }

    @Test func daysAndMonthsAreReadInThreeLanguages() {
        #expect(ParkOpeningReader.days(in: "Zaterdag en zondag") == ["weekend"])
        #expect(ParkOpeningReader.days(in: "Montag bis Freitag") == ["weekdays"])
        #expect(ParkOpeningReader.days(in: "Mon, Wed and Fri") == ["mon", "wed", "fri"])
        #expect(ParkOpeningReader.days(in: "ma t/m zo") == nil)
        #expect(ParkOpeningReader.days(in: "dagelijks") == nil)
        #expect(ParkOpeningReader.days(in: "wij zijn zo open") == nil)
        #expect(ParkOpeningReader.months(in: "oktober - maart") == [1, 2, 3, 10, 11, 12])
        #expect(ParkOpeningReader.months(in: "Mai bis September") == [5, 6, 7, 8, 9])
        #expect(ParkOpeningReader.months(in: "it may be fine") == [])
    }

    @Test func timesOnAnUnrelatedPageAreNotHours() {
        let page = ParkSourcePage(
            url: "https://park.nl/lessen",
            blocks: [ParkSourceBlock(heading: "Lessen", text: "Zaterdag 10:00 - 11:00 beginnersles")]
        )
        #expect(ParkOpeningReader.read([page]) == nil)
        let loose = ParkSourcePage(
            url: "https://park.nl/info",
            blocks: [ParkSourceBlock(heading: "Openingstijden", text: "Elke dag in de zomer 10:00 tot 18:00")]
        )
        #expect(ParkOpeningReader.read([loose])?.rules.count == 1)
        #expect(ParkOpeningReader.hoursText([loose]) == "Elke dag in de zomer 10:00 tot 18:00")
    }

    @Test func openingHoursAreProposedAsOneItemAndApplied() {
        var found = ParkImportCandidates()
        found.opening = ParkOpeningReader.read([Self.hoursPage])
        let items = ParkImportMerge.items(from: found, in: park(), grounding: ParkImportGrounding(pages: [Self.hoursPage]))
        #expect(items.map(\.id) == ["opening"])
        #expect(items.first?.level == .verified)
        let result = ParkImportMerge.apply(items, to: park())
        #expect(result.opening?.rules?.count == 3)
        #expect(result.opening?.sourceURL == "https://www.project7cablepark.nl/openingstijden/")
        #expect(ParkImportMerge.items(from: found, in: result, grounding: ParkImportGrounding(pages: [])).isEmpty)
    }

    // MARK: Where to look next

    @Test func theNextPageIsLinkedBeforeItIsGuessed() {
        let pages = [Self.page]
        let missing: [ParkImportTopic] = [.opening, .prices, .contact]
        let first = ParkImportAgent.next(pages: pages, missing: missing, visited: [], guessesUsed: 0)
        #expect(first == ParkImportTarget(url: "https://www.breakout-grunopark.nl/prijzen", topic: .prices, isGuess: false))
        let second = ParkImportAgent.next(pages: pages, missing: missing, visited: [first?.url ?? ""], guessesUsed: 0)
        #expect(second?.url == "https://www.breakout-grunopark.nl/contact")
        let guess = ParkImportAgent.next(pages: pages, missing: [.opening], visited: [], guessesUsed: 0)
        #expect(guess == ParkImportTarget(url: "https://www.breakout-grunopark.nl/openingstijden", topic: .opening, isGuess: true))
        #expect(ParkImportAgent.next(pages: pages, missing: [.opening], visited: [], guessesUsed: ParkImportAgent.maxGuesses) == nil)
        let full = Array(repeating: Self.page, count: ParkImportAgent.maxPages)
        #expect(ParkImportAgent.next(pages: full, missing: missing, visited: [], guessesUsed: 0) == nil)
    }

    @Test func missingTopicsFollowTheParkAndTheFindings() {
        #expect(ParkImportAgent.missingTopics(candidates: ParkImportCandidates(), park: park()) == [.opening, .contact, .events])
        var bare = park()
        bare.prices = nil
        #expect(ParkImportAgent.missingTopics(candidates: ParkImportCandidates(), park: bare) == [.opening, .prices, .contact, .events])
        var done = ParkImportCandidates()
        done.opening = ParkOpeningReader.read([Self.hoursPage])
        done.address = "Hoofdweg 163"
        #expect(ParkImportAgent.missingTopics(candidates: done, park: park()) == [.events])
    }

    // MARK: Rescanning a known park

    @Test func aRescanAsksForEverythingEvenWhenTheParkHasIt() {
        let done = park()
        #expect(ParkImportAgent.missingTopics(candidates: ParkImportCandidates(), park: done, refreshing: true)
            == [.opening, .prices, .contact, .events])
    }

    @Test func rescanStartsAtTheRememberedPagesBeforeTheWebsite() {
        var known = park()
        known.website = "https://www.breakout-grunopark.nl"
        known.opening = ParkOpening(sourceURL: "https://breakout-grunopark.nl/openingstijden")
        known.sources = ["breakout-grunopark.nl/prijzen", "https://www.breakout-grunopark.nl/", "mailto:info@park.nl"]
        #expect(ParkImportAgent.startAddresses(for: known) == [
            "https://breakout-grunopark.nl/openingstijden",
            "https://breakout-grunopark.nl/prijzen",
            "https://www.breakout-grunopark.nl/",
        ])
        known.website = nil
        known.opening = nil
        known.sources = nil
        #expect(ParkImportAgent.startAddresses(for: known).isEmpty)
    }

    @Test func rememberedSourcesAreAddedOnceAndTidiedOnSave() {
        var known = park()
        known.sources = ["https://www.breakout-grunopark.nl/prijzen"]
        known = ParkImportAgent.remember(["https://breakout-grunopark.nl/prijzen/", "https://www.breakout-grunopark.nl/contact"], in: known)
        #expect(known.sources == ["https://www.breakout-grunopark.nl/prijzen", "https://www.breakout-grunopark.nl/contact"])
        known.sources = (known.sources ?? []) + ["nonsense", " https://www.breakout-grunopark.nl/contact "]
        #expect(ParkDraft.finalized(known).sources == ["https://www.breakout-grunopark.nl/prijzen", "https://www.breakout-grunopark.nl/contact"])
    }

    // MARK: Sitemap

    @Test func sitemapAddressesAreRead() {
        let xml = """
        <?xml version="1.0"?><urlset>
        <url><loc>https://www.breakout-grunopark.nl/</loc></url>
        <url>
          <loc> https://www.breakout-grunopark.nl/openingstijden?a=1&amp;b=2 </loc>
        </url>
        </urlset>
        """
        #expect(ParkSitemap.locations(in: xml).pages == [
            "https://www.breakout-grunopark.nl/", "https://www.breakout-grunopark.nl/openingstijden?a=1&b=2",
        ])
        let index = "<sitemapindex><sitemap><loc>https://x.nl/a.xml</loc></sitemap><sitemap><loc>https://x.nl/b.xml</loc></sitemap></sitemapindex>"
        let found = ParkSitemap.locations(in: index)
        #expect(found.pages.isEmpty)
        #expect(found.sitemaps == ["https://x.nl/a.xml", "https://x.nl/b.xml"])
        #expect(ParkSitemap.sitemaps(inRobots: "User-agent: *\nSitemap: https://x.nl/sm.xml\nDisallow: /a") == ["https://x.nl/sm.xml"])
        #expect(ParkSitemap.usualAddress(forSite: "https://www.x.nl/a/b") == "https://www.x.nl/sitemap.xml")
        #expect(ParkSitemap.usualAddress(forSite: "screenshot") == nil)
    }

    @Test func aSitemapPageComesBeforeAGuess() {
        let sitemap = ParkSitemap.links([
            "https://www.breakout-grunopark.nl/over-ons", "https://www.breakout-grunopark.nl/nl/openingstijden-en-tijden",
            "https://other.nl/openingstijden",
        ])
        let target = ParkImportAgent.next(pages: [Self.page], missing: [.opening], visited: [], guessesUsed: 0, sitemap: sitemap)
        #expect(target == ParkImportTarget(url: "https://www.breakout-grunopark.nl/nl/openingstijden-en-tijden", topic: .opening, isGuess: false))
        let none = ParkImportAgent.next(pages: [Self.page], missing: [.opening], visited: [], guessesUsed: 0)
        #expect(none?.isGuess == true)
    }

    // MARK: Structured and model-read hours

    @Test func schemaOrgHoursAreReadWithoutReadingText() {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[{"@type":"SportsActivityLocation","openingHoursSpecification":[
          {"@type":"OpeningHoursSpecification","dayOfWeek":["https://schema.org/Monday","Tuesday"],"opens":"10:00:00","closes":"18:00:00"},
          {"dayOfWeek":"Saturday","opens":"09:00","closes":"18:00"},
          {"dayOfWeek":"Sunday","opens":"09:00","closes":"18:00"},
          {"dayOfWeek":"Friday","opens":"10:00","closes":"22:00","validFrom":"2026-12-24"}]},
          {"openingHours":["We-Th 12:00-20:00"]}]}
        </script></head><body><p>Welkom</p></body></html>
        """
        let page = ParkSourceExtractor.extract(html: html, url: "https://www.example-park.nl/")
        let found = ParkOpeningReader.read([page])
        #expect(found?.rules.count == 3)
        #expect(found?.rules.first == ParkOpeningRule(days: ["mon", "tue"], open: "10:00", close: "18:00"))
        #expect(found?.rules.contains(ParkOpeningRule(days: ["weekend"], open: "09:00", close: "18:00")) == true)
        #expect(found?.rules.contains(ParkOpeningRule(days: ["wed", "thu"], open: "12:00", close: "20:00")) == true)
        #expect(found?.isVerified == true)
    }

    @Test func hoursStringsHandleRangesAndSeveralTimes() {
        let rules = ParkStructuredHours.rules(in: [#"{"openingHours":"Mo-Fr 10:00-12:00,13:00-17:00"}"#, "not json"]).rules
        #expect(rules.map(\.open) == ["10:00", "13:00"])
        #expect(rules.allSatisfy { $0.days == ["weekdays"] })
        #expect(ParkStructuredHours.clock("24:00") == "24:00")
        #expect(ParkStructuredHours.clock("25:00") == nil)
    }

    @Test func modelHoursAreCheckedAgainstTheText() {
        let page = ParkSourceExtractor.extract(
            html: "<h2>Openingstijden</h2><p>Dinsdag tot en met zondag van 10 tot 18 uur, maandag gesloten</p>",
            url: "https://www.example-park.nl/tijden"
        )
        #expect(ParkOpeningReader.modelHoursText([page])?.contains("maandag gesloten") == true)
        let good = ParkOpeningReader.finding(
            from: [ParkModelHours(days: "dinsdag t/m zondag", months: "", open: "10:00", close: "18:00")], pages: [page]
        )
        #expect(good?.isVerified == true)
        #expect(good?.rules.first?.days == ["weekend", "tue", "wed", "thu", "fri"])
        #expect(good?.sourceURL == "https://www.example-park.nl/tijden")
        let invented = ParkOpeningReader.finding(
            from: [ParkModelHours(days: "", months: "", open: "09:00", close: "18:00")], pages: [page]
        )
        #expect(invented?.isVerified == false)
        let broken = ParkOpeningReader.finding(
            from: [ParkModelHours(days: "", months: "", open: "late", close: "18:00"), ParkModelHours(days: "", months: "", open: "18:00", close: "10:00")],
            pages: [page]
        )
        #expect(broken == nil)
    }

    @Test func timesAreFoundInTheirUsualWritings() {
        #expect(ParkOpeningReader.timeStandsInText("12:30", "open 12.30 - 17.00 Uhr"))
        #expect(ParkOpeningReader.timeStandsInText("08:00", "van 8 tot 12 uur"))
        #expect(!ParkOpeningReader.timeStandsInText("18:00", "van 8 tot 12 uur"))
        #expect(!ParkOpeningReader.timeStandsInText("10:15", "van 10:45"))
    }
}
