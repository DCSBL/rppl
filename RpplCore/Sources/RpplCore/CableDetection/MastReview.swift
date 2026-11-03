import Foundation

// Mast review: the app shows the detector's mast guesses for a park on the satellite map and the
// reviewer judges them (mast / no mast / unsure) or adds masts by hand. The verdicts go into
// `mast-labels.json`, which the cable-tracer's training-set export reads: a confirmed mast trains
// the mast net like a traced bend does, and a rejected detection is a hard negative.

/// One reviewed mast position: where the detector (or the reviewer) put it and the verdict.
public struct MastLabel: Codable, Equatable, Sendable, Identifiable {
    public enum Verdict: String, Codable, Sendable, CaseIterable {
        case mast
        case notMast = "none"
        case unsure
    }

    public enum Source: String, Codable, Sendable {
        case detector, manual
    }

    public var id: UUID
    /// The mast itself for `.mast` (after the reviewer centred it); the detector's peak for `.notMast` and `.unsure`.
    public var coordinate: ParkCoordinate
    public var verdict: Verdict
    public var source: Source
    /// Detector confidence, when the detector proposed it.
    public var probability: Double?
    /// Where the detector put the peak when the reviewer moved the mast; nil when within a metre.
    public var detected: ParkCoordinate?
    /// yyyy-MM-dd, UTC.
    public var reviewedAt: String

    public init(id: UUID = UUID(), coordinate: ParkCoordinate, verdict: Verdict, source: Source, probability: Double? = nil, detected: ParkCoordinate? = nil, reviewedAt: String = MastLabelStore.today()) {
        self.id = id
        self.coordinate = coordinate
        self.verdict = verdict
        self.source = source
        self.probability = probability
        self.detected = detected
        self.reviewedAt = reviewedAt
    }
}

/// Every park's mast labels in one JSON file (`mast-labels.json`), written after every verdict so
/// a review session can stop at any time. The app shares this file; the tracer reads it.
public struct MastLabelStore: Codable, Equatable, Sendable {
    public var version = 1
    public var parks: [String: [MastLabel]] = [:]

    public init() {}

    public static let fileName = "mast-labels.json"

    public static func load(from url: URL) throws -> MastLabelStore {
        guard FileManager.default.fileExists(atPath: url.path) else { return MastLabelStore() }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> MastLabelStore {
        try JSONDecoder().decode(MastLabelStore.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    public func labels(for parkID: String) -> [MastLabel] { parks[parkID] ?? [] }

    public var reviewedParkIDs: Set<String> { Set(parks.filter { !$0.value.isEmpty }.keys) }

    public var labelCount: Int { parks.values.reduce(0) { $0 + $1.count } }

    public func count(_ verdict: MastLabel.Verdict, in parkID: String) -> Int {
        labels(for: parkID).filter { $0.verdict == verdict }.count
    }

    public mutating func add(_ label: MastLabel, to parkID: String) {
        parks[parkID, default: []].append(label)
    }

    public mutating func remove(_ id: UUID, from parkID: String) {
        parks[parkID]?.removeAll { $0.id == id }
        if parks[parkID]?.isEmpty == true { parks[parkID] = nil }
    }

    /// Whether a detection this close to an existing label (or to where that label was detected) was already judged.
    public func isReviewed(_ coordinate: ParkCoordinate, in parkID: String, withinM radius: Double = 12) -> Bool {
        labels(for: parkID).contains { label in
            coordinate.meters(to: label.coordinate) <= radius || (label.detected.map { coordinate.meters(to: $0) <= radius } ?? false)
        }
    }

    public static func today(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

/// Which parks to review, handed to the app as `mast-review-request.json`. Without a request the
/// app offers every park that has no traced cable.
public struct MastReviewRequest: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        /// Shown when the park is not on this phone (an id the app does not know).
        public var name: String?
        /// Why this park is on the list, e.g. "no cable traced" or "detector found 2 of 5 masts".
        public var reason: String?

        public init(id: String, name: String? = nil, reason: String? = nil) {
            self.id = id
            self.name = name
            self.reason = reason
        }
    }

    public var version = 1
    /// yyyy-MM-dd.
    public var createdAt: String
    public var note: String?
    public var parks: [Item]

    public init(createdAt: String = MastLabelStore.today(), note: String? = nil, parks: [Item]) {
        self.createdAt = createdAt
        self.note = note
        self.parks = parks
    }

    public static func decode(_ data: Data) throws -> MastReviewRequest {
        try JSONDecoder().decode(MastReviewRequest.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// The detector's unreviewed tower guesses for one park, judged one at a time: the most confident
/// first, then always the nearest remaining guess, so the map moves in short hops along the shore.
/// Pure state so the review flow can be tested without a map.
public struct MastReviewSession: Equatable, Sendable {
    public struct Candidate: Identifiable, Equatable, Sendable {
        public var id: Int
        public var coordinate: ParkCoordinate
        public var probability: Double
    }

    /// Detections below this are not worth a look; the app's own cut-off is higher.
    public static let minimumProbability = 0.3
    /// A "Mast" verdict takes the crosshair position when it is this close to the detection,
    /// so the reviewer can centre the mast; further away the reviewer looked at something else.
    public static let maximumCorrectionM = 90.0

    public let parkID: String
    public private(set) var candidates: [Candidate]
    public private(set) var currentIndex: Int?

    public init(parkID: String, detected: [DetectedMast], image: DetectionImage, labels: MastLabelStore, minimumProbability: Double = MastReviewSession.minimumProbability) {
        self.parkID = parkID
        candidates = detected.enumerated()
            .compactMap { index, mast -> Candidate? in
                guard mast.probability >= minimumProbability else { return nil }
                let coordinate = image.coordinate(fromLocal: mast.xy)
                guard !labels.isReviewed(coordinate, in: parkID) else { return nil }
                return Candidate(id: index, coordinate: coordinate, probability: mast.probability)
            }
        candidates = Self.nearestNeighbourOrder(candidates)
        currentIndex = candidates.isEmpty ? nil : 0
    }

    /// Starts at the most confident guess and walks to the nearest unvisited one each time.
    static func nearestNeighbourOrder(_ candidates: [Candidate]) -> [Candidate] {
        guard let first = candidates.indices.max(by: { candidates[$0].probability < candidates[$1].probability }) else { return [] }
        var remaining = candidates
        var ordered = [remaining.remove(at: first)]
        while !remaining.isEmpty, let last = ordered.last {
            let next = remaining.indices.min { last.coordinate.meters(to: remaining[$0].coordinate) < last.coordinate.meters(to: remaining[$1].coordinate) }!
            ordered.append(remaining.remove(at: next))
        }
        return ordered
    }

    public var current: Candidate? { currentIndex.map { candidates[$0] } }
    public var remaining: Int { candidates.count }
    /// 1-based position of the current candidate, for "3 of 9".
    public var position: Int? { currentIndex.map { $0 + 1 } }

    /// Leaves the current candidate for later and shows the next one (wrapping around).
    public mutating func skip() {
        guard let index = currentIndex, candidates.count > 1 else { return }
        currentIndex = (index + 1) % candidates.count
    }

    /// Records the verdict for the current candidate and moves on. A mast is saved where the
    /// crosshair is when the reviewer moved it onto the mast; the other verdicts keep the detection.
    public mutating func judge(_ verdict: MastLabel.Verdict, crosshair: ParkCoordinate?, reviewedAt: String = MastLabelStore.today()) -> MastLabel? {
        guard let index = currentIndex else { return nil }
        let candidate = candidates[index]
        var coordinate = candidate.coordinate
        var detected: ParkCoordinate?
        if verdict == .mast, let crosshair, crosshair.meters(to: candidate.coordinate) <= Self.maximumCorrectionM {
            coordinate = crosshair
            if crosshair.meters(to: candidate.coordinate) > 1 { detected = candidate.coordinate }
        }
        candidates.remove(at: index)
        currentIndex = candidates.isEmpty ? nil : index % candidates.count
        return MastLabel(coordinate: coordinate, verdict: verdict, source: .detector, probability: candidate.probability, detected: detected, reviewedAt: reviewedAt)
    }

    /// A mast the detector missed, placed by the reviewer.
    public static func manualMast(at coordinate: ParkCoordinate, reviewedAt: String = MastLabelStore.today()) -> MastLabel {
        MastLabel(coordinate: coordinate, verdict: .mast, source: .manual, reviewedAt: reviewedAt)
    }
}
