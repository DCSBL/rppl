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

@Observable
final class ParkImportModel {
    enum Phase: Equatable {
        case idle
        case fetching
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
    /// A source was read, so an empty list of suggestions means "nothing new" and not "nothing yet".
    private(set) var hasRead = false
    var selected: Set<String> = []

    private let session: ParkEditorSession
    private var pages: [ParkSourcePage] = []
    private var candidates = ParkImportCandidates()

    init(session: ParkEditorSession) {
        self.session = session
    }

    var isWorking: Bool { phase != .idle }

    // MARK: Sources

    /// Reads a website, and when something is still missing, the pages of the same site that look like
    /// they hold it (prices, contact). Never more than `ParkImportCrawler.maxPages` pages.
    func addWebsite(_ text: String) async {
        guard !isWorking else { return }
        guard let address = ParkText.normalizedWebAddress(text) else {
            notes.append(.badAddress)
            return
        }
        defer { phase = .idle }
        phase = .fetching
        guard let first = await fetchPage(address) else { return }
        await read(first)
        var visited: Set<String> = [first.url, address]
        while pages.count < ParkImportCrawler.maxPages {
            let missing = missingTopics()
            guard !missing.isEmpty,
                  let next = ParkImportCrawler.candidates(from: first, topics: missing, visited: visited).first else { break }
            visited.insert(next.url)
            phase = .fetching
            guard let page = await fetchPage(next.url) else { continue }
            await read(page)
        }
    }

    /// Reads the text of a screenshot (an Instagram post, a page of a PDF) on the phone.
    func addScreenshot(_ image: UIImage) async {
        guard !isWorking else { return }
        defer { phase = .idle }
        phase = .recognizing
        guard let cgImage = image.cgImage else {
            notes.append(.unreadableImage)
            return
        }
        let orientation = image.imageOrientation
        let text = await Task.detached(priority: .userInitiated) {
            Self.recognizeText(in: cgImage, orientation: orientation)
        }.value
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notes.append(.unreadableImage)
            return
        }
        await read(ParkSourceExtractor.extract(plainText: text, label: "screenshot"))
    }

    /// Writes the chosen suggestions into the park being edited.
    func apply() {
        session.park = ParkImportMerge.apply(items.filter { selected.contains($0.id) }, to: session.park)
        items = []
        selected = []
        refresh()
    }

    // MARK: Steps

    private func fetchPage(_ address: String) async -> ParkSourcePage? {
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
            notes.append(.unreadablePage)
            return nil
        }
    }

    /// Plain code first (phone, email, social links, site address), then the model, one chunk at a time.
    private func read(_ page: ParkSourcePage) async {
        pages.append(page)
        hasRead = true
        candidates.merge(ParkImportCandidates(page: page))
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

    private func missingTopics() -> [ParkImportTopic] {
        var missing: [ParkImportTopic] = []
        if candidates.prices.isEmpty, (session.park.prices ?? []).isEmpty { missing.append(.prices) }
        if candidates.address == nil, (session.park.address ?? "").isEmpty { missing.append(.contact) }
        return missing
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
            }
        } catch {
            WakeLog.error(.ui, "park import model: \(error.localizedDescription)")
            if !notes.contains(.modelSkipped) { notes.append(.modelSkipped) }
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
        let handler = VNImageRequestHandler(cgImage: image, orientation: CGImagePropertyOrientation(orientation), options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
