import FoundationModels
import Observation
import RpplCore
import UIKit
import Vision

/// The on-device model, as far as the import is concerned. Nothing here ever goes to a server: the
/// Apple Intelligence model runs on the phone, and the only network request is the page the person names.
enum ParkImportAvailability {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}

// MARK: - What the model may answer

/// Small on purpose: every property is tokens in a 4096 token window. Each one is a field of the park.
@Generable
nonisolated struct ImportedPrice {
    @Guide(description: "What the price is for, as written, for example 'Day pass'")
    var name: String
    @Guide(description: "The amount as written, for example '24' or '12,50'")
    var amount: String
    @Guide(description: "The unit as written (hour, day, session, person) or empty")
    var per: String
    @Guide(description: "Who or what it applies to, as written, or empty")
    var note: String
    @Guide(description: "The exact words copied from the text")
    var quote: String
}

@Generable
nonisolated struct ImportedPrices {
    @Guide(description: "All prices in the text", .maximumCount(12))
    var prices: [ImportedPrice]
}

@Generable
nonisolated struct ImportedAddress {
    @Guide(description: "Street, number, postal code and town as written, or empty")
    var address: String
}

@Generable
nonisolated struct ImportedFacilities {
    @Guide(description: "Facilities the park offers, each a short word from the text", .maximumCount(12))
    var facilities: [String]
}

// MARK: - The import

/// One page (or screenshot) the import looked at, and what it found there.
struct ParkImportTraceEntry: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var found: [ParkImportField]
    var failed: Bool
    /// The page was not linked anywhere; it is a usual address of the site.
    var isGuess: Bool
    /// The address of a page that was read; nil when it could not be opened.
    var url: String?
}

@Observable
final class ParkImportModel {
    enum Phase: Equatable {
        case idle
        case fetching(String)
        case recognizing
        case reading(part: Int, of: Int)
    }

    enum Note: Hashable {
        case badAddress, unreadablePage, unreadableImage, modelSkipped
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [ParkImportItem] = []
    private(set) var questions: [ParkImportQuestion] = []
    private(set) var notes: [Note] = []
    /// The pages read so far, in order: what the search did.
    private(set) var trace: [ParkImportTraceEntry] = []
    /// A source was read, so an empty list of suggestions means "nothing new" and not "nothing yet".
    private(set) var hasRead = false
    var selected: Set<String> = []

    private let session: ParkEditorSession
    private var pages: [ParkSourcePage] = []
    /// Pages named by the site's sitemap, read once per search.
    private var sitemap: [ParkSourceLink] = []
    private var candidates = ParkImportCandidates()

    init(session: ParkEditorSession) {
        self.session = session
    }

    var isWorking: Bool { phase != .idle }

    // MARK: Sources

    /// Reads a website like a person would: the page given first, then the pages that should hold what is
    /// still missing (opening hours, prices, contact), following links and, as a last resort, usual
    /// addresses of the same site. Stops when nothing is missing, nothing is left to try, or at
    /// `ParkImportAgent.maxPages` pages.
    func searchWebsite(_ text: String) async {
        guard !isWorking else { return }
        guard let address = ParkText.normalizedWebAddress(text) else {
            addNote(.badAddress)
            return
        }
        await search(from: [address], refreshing: false)
    }

    /// The addresses a rescan of this park starts from: where its data came from before.
    var knownSources: [String] {
        session.editsParkID == nil ? [] : ParkImportAgent.startAddresses(for: session.park)
    }

    /// Reads every remembered source of an existing park again, then looks further for what is still missing.
    /// Unlike a first import, what the park already has does not count as found: it may be out of date.
    func rescan() async {
        guard !isWorking, !knownSources.isEmpty else { return }
        await search(from: knownSources, refreshing: true)
    }

    private func search(from addresses: [String], refreshing: Bool) async {
        defer {
            phase = .idle
            refresh()
        }
        sitemap = []
        var triedSitemap = false
        var visited = Set(addresses)
        var queue = addresses[...]
        var guesses = 0
        var target = queue.popFirst().map { ParkImportTarget(url: $0, topic: .contact, isGuess: false) }
        while let current = target {
            phase = .fetching(Self.label(current.url))
            let before = candidates.fields
            if let page = await fetchPage(current.url, quiet: current.isGuess) {
                visited.insert(page.url)
                await read(page)
                let added = ParkImportField.allCases.filter { candidates.fields.contains($0) && !before.contains($0) }
                trace.append(ParkImportTraceEntry(
                    label: Self.label(page.url), found: added, failed: false, isGuess: current.isGuess, url: page.url
                ))
            } else if !current.isGuess {
                trace.append(ParkImportTraceEntry(label: Self.label(current.url), found: [], failed: true, isGuess: false, url: nil))
            }
            // The sitemap is read once, after the first page of the site was read.
            if !triedSitemap, let site = pages.first?.url {
                triedSitemap = true
                phase = .fetching("sitemap")
                sitemap = await fetchSitemap(forSite: site)
            }
            // Every remembered source is read; only after that the missing topics decide where to look.
            if let next = queue.popFirst() {
                target = ParkImportTarget(url: next, topic: .contact, isGuess: false)
                continue
            }
            let missing = ParkImportAgent.missingTopics(candidates: candidates, park: session.park, refreshing: refreshing)
            guard !missing.isEmpty else { break }
            target = ParkImportAgent.next(pages: pages, missing: missing, visited: visited, guessesUsed: guesses, sitemap: sitemap)
            if let next = target {
                visited.insert(next.url)
                if next.isGuess { guesses += 1 }
            }
        }
    }

    /// Reads the text of a screenshot (an Instagram post, a page of a PDF) on the phone.
    func addScreenshot(_ image: UIImage) async {
        guard !isWorking else { return }
        defer {
            phase = .idle
            refresh()
        }
        phase = .recognizing
        guard let cgImage = image.cgImage else {
            addNote(.unreadableImage)
            return
        }
        let orientation = image.imageOrientation
        let text = await Task.detached(priority: .userInitiated) {
            Self.recognizeText(in: cgImage, orientation: orientation)
        }.value
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addNote(.unreadableImage)
            return
        }
        let before = candidates.fields
        await read(ParkSourceExtractor.extract(plainText: text, label: "screenshot"))
        let added = ParkImportField.allCases.filter { candidates.fields.contains($0) && !before.contains($0) }
        trace.append(ParkImportTraceEntry(label: "screenshot", found: added, failed: false, isGuess: false, url: nil))
    }

    /// Writes the chosen suggestions into the park being edited and remembers the pages that gave
    /// something, so a later rescan starts there.
    func apply() {
        let chosen = items.filter { selected.contains($0.id) }
        let sources = trace.compactMap { $0.found.isEmpty ? nil : $0.url }
        session.park = ParkImportAgent.remember(sources, in: ParkImportMerge.apply(chosen, to: session.park))
        items = []
        selected = []
        refresh()
    }

    // MARK: Steps

    private func addNote(_ note: Note) {
        if !notes.contains(note) { notes.append(note) }
    }

    /// Today as `yyyy-MM-dd` in the park's time zone.
    private static func today(in zone: TimeZone) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: zone, from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// The address as a short label: the path, or the host for the front page.
    private static func label(_ address: String) -> String {
        guard let components = URLComponents(string: address) else { return address }
        let path = components.path
        return path.isEmpty || path == "/" ? (components.host ?? address) : path
    }

    private func fetchPage(_ address: String, quiet: Bool) async -> ParkSourcePage? {
        do {
            guard let url = URL(string: address) else { throw URLError(.badURL) }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
            guard data.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return ParkSourceExtractor.extract(html: html, url: response.url?.absoluteString ?? address)
        } catch {
            WakeLog.error(.ui, "park import fetch: \(error.localizedDescription)")
            if !quiet { addNote(.unreadablePage) }
            return nil
        }
    }

    /// The pages the site's sitemap lists (`/sitemap.xml`, else the `Sitemap:` line of robots.txt; an index
    /// is followed one level). Empty when the site has none: the search then falls back to links and guesses.
    private func fetchSitemap(forSite address: String) async -> [ParkSourceLink] {
        var files = ParkSitemap.usualAddress(forSite: address).map { [$0] } ?? []
        var pages: [String] = []
        var triedRobots = false
        while let file = files.first, pages.count < ParkSitemap.maxPages {
            files.removeFirst()
            guard ParkImportCrawler.siteHost(file) == ParkImportCrawler.siteHost(address) else { continue }
            if let xml = await fetchText(file) {
                let found = ParkSitemap.locations(in: xml)
                pages += found.pages
                files += found.sitemaps
            } else if !triedRobots, let site = URLComponents(string: address), let scheme = site.scheme, let host = site.host {
                triedRobots = true
                if let robots = await fetchText("\(scheme)://\(host)/robots.txt") { files += ParkSitemap.sitemaps(inRobots: robots) }
            }
        }
        return ParkSitemap.links(Array(pages.prefix(ParkSitemap.maxPages)))
    }

    /// A text file of the site; nil when it is not there. Misses are normal and stay out of the notes.
    private func fetchText(_ address: String) async -> String? {
        guard let url = URL(string: address) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard data.count <= 2_000_000 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Plain code first (phone, email, social links, opening hours), then the model, one chunk at a time.
    private func read(_ page: ParkSourcePage) async {
        // A usual address that answers with the front page again adds nothing.
        guard !pages.contains(where: { $0.blocks == page.blocks }) else { return }
        pages.append(page)
        hasRead = true
        candidates.merge(ParkImportCandidates(page: page))
        candidates.opening = ParkOpeningReader.read(pages)
        candidates.openingNote = candidates.opening == nil ? ParkOpeningReader.hoursText(pages) : nil
        candidates.events = ParkEventReader.read(pages, today: Self.today(in: session.park.resolvedTimeZone))
        let chunks = ParkImportChunker.chunks(for: [page], topics: topicsToAsk())
        for (index, chunk) in chunks.enumerated() {
            phase = .reading(part: index + 1, of: chunks.count)
            await ask(chunk)
        }
        refresh()
    }

    /// The model is only asked for what code cannot read, and only for what is still missing.
    private func topicsToAsk() -> [ParkImportTopic] {
        var topics: [ParkImportTopic] = [.facilities]
        if candidates.prices.isEmpty { topics.append(.prices) }
        if candidates.address == nil { topics.append(.contact) }
        return topics
    }

    private func ask(_ chunk: ParkImportChunk) async {
        let prompt = "Text:\n\(chunk.text)"
        let base = "You read text from a cable park website. Use only what the text says. Never guess. Use empty values when the text does not say."
        do {
            switch chunk.topic {
            case .prices:
                let currency = ParkImportCandidates.currency(
                    in: chunk.text, fallback: session.park.prices?.first?.options.first?.currency
                )
                var found = try await prices(base, prompt, currency: currency)
                let grounding = ParkImportGrounding(pages: pages)
                let bad = found.filter { grounding.amount($0.price.options.first?.amount ?? "", quote: $0.quote) == .notFound }
                if !bad.isEmpty {
                    // One more try, told what went wrong; what is still not in the text stays flagged.
                    let again = try await prices(
                        base + " An earlier answer had amounts that are not in the text. Copy amounts and quotes exactly.",
                        prompt, currency: currency
                    )
                    let good = found.filter { !bad.contains($0) } + again
                    found = good + bad.filter { stale in !good.contains { ParkImportCandidates.sameName($0.price.name, stale.price.name) } }
                }
                var extra = ParkImportCandidates()
                extra.prices = found
                candidates.merge(extra)
            case .contact:
                let result = try await generate(ImportedAddress.self, instructions: base, prompt: prompt)
                var extra = ParkImportCandidates()
                extra.address = result.address.isEmpty ? nil : result.address
                candidates.merge(extra)
            case .facilities:
                let result = try await generate(ImportedFacilities.self, instructions: base, prompt: prompt)
                var extra = ParkImportCandidates()
                extra.facilities = result.facilities.filter { !$0.isEmpty }
                candidates.merge(extra)
            case .opening, .events:
                break
            }
        } catch {
            WakeLog.error(.ui, "park import model: \(error.localizedDescription)")
            addNote(.modelSkipped)
        }
    }

    private func prices(_ instructions: String, _ prompt: String, currency: String) async throws -> [ParkImportPrice] {
        let result = try await generate(ImportedPrices.self, instructions: instructions, prompt: prompt)
        return result.prices.compactMap {
            ParkImportCandidates.price(
                name: $0.name, amount: $0.amount, per: $0.per, note: $0.note, quote: $0.quote, currency: currency
            )
        }
    }

    /// A new session per chunk: the context window holds one small task, not a conversation.
    private func generate<Content: Generable>(_ type: Content.Type, instructions: String, prompt: String) async throws -> Content {
        let model = LanguageModelSession(instructions: instructions)
        let response = try await model.respond(to: prompt, generating: type, options: GenerationOptions(sampling: .greedy))
        return response.content
    }

    private func refresh() {
        let previous = Set(items.map(\.id))
        items = ParkImportMerge.items(from: candidates, in: session.park, grounding: ParkImportGrounding(pages: pages))
        // What was seen before keeps the person's choice; new suggestions start on only when verified.
        selected = Set(items.filter { previous.contains($0.id) ? selected.contains($0.id) : $0.level == .verified }.map(\.id))
        questions = pages.isEmpty ? [] : ParkImportMerge.questions(items: items, park: session.park)
    }

    // MARK: Text in images

    private nonisolated static func recognizeText(in image: CGImage, orientation: UIImage.Orientation) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, orientation: imageOrientation(orientation), options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private nonisolated static func imageOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
