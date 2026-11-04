import Foundation

// Tower review: the app shows the detector's tower guesses for a park on the satellite map and the
// reviewer judges them (tower / no tower / not visible / unsure) or adds towers by hand. A tower is
// placed by laying the map under a fixed frame: the wheel in the frame's ring, the tower's arm along
// the frame, so the label also records the arm's direction and length on the image. The verdicts go into
// `tower-labels.json`, which the cable-tracer's training-set export reads: a confirmed tower trains
// the tower net like a traced bend does, and a rejected detection is a hard negative.

/// One reviewed tower position: where the detector (or the reviewer) put it and the verdict.
public struct TowerLabel: Codable, Equatable, Sendable, Identifiable {
    public enum Verdict: String, Codable, Sendable, CaseIterable {
        case tower
        case notTower = "none"
        /// A tower stands here (the reviewer knows the park) but the imagery does not show it:
        /// blurred, outdated or a ghost copy from another imagery layer. Training leaves the spot alone.
        case notVisible
        case unsure

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Files shared before the rename (2026-11-03) wrote "mast".
            guard let verdict = Verdict(rawValue: raw == "mast" ? "tower" : raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown verdict \(raw)"))
            }
            self = verdict
        }
    }

    public enum Source: String, Codable, Sendable {
        case detector, manual
    }

    /// The tower's arm as it lies on the satellite image, from the wheel to the foot.
    public struct Arm: Codable, Equatable, Sendable {
        /// Compass bearing from the wheel to the foot, degrees clockwise from north, 0..<360.
        public var bearingDeg: Double
        public var lengthM: Double

        public init(bearingDeg: Double, lengthM: Double) {
            self.bearingDeg = bearingDeg
            self.lengthM = lengthM
        }

        /// The arm between the wheel and the foot, or nil when they are less than a metre apart.
        public init?(wheel: ParkCoordinate, foot: ParkCoordinate) {
            let length = wheel.meters(to: foot)
            guard length >= 1 else { return nil }
            let lat1 = wheel.lat * .pi / 180, lat2 = foot.lat * .pi / 180
            let dLon = (foot.lon - wheel.lon) * .pi / 180
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            let bearing = atan2(y, x) * 180 / .pi
            self.init(bearingDeg: (bearing + 360).truncatingRemainder(dividingBy: 360), lengthM: length)
        }
    }

    public var id: UUID
    /// The tower itself for `.tower` (after the reviewer centred it); the detector's peak for `.notTower` and `.unsure`.
    public var coordinate: ParkCoordinate
    public var verdict: Verdict
    public var source: Source
    /// Detector confidence, when the detector proposed it.
    public var probability: Double?
    /// Where the detector put the peak when the reviewer moved the tower; nil when within a metre.
    public var detected: ParkCoordinate?
    /// The arm along the review frame, for `.tower` labels placed with the frame; nil for older labels.
    public var arm: Arm?
    /// yyyy-MM-dd, UTC.
    public var reviewedAt: String

    public init(id: UUID = UUID(), coordinate: ParkCoordinate, verdict: Verdict, source: Source, probability: Double? = nil, detected: ParkCoordinate? = nil, arm: Arm? = nil, reviewedAt: String = TowerLabelStore.today()) {
        self.id = id
        self.coordinate = coordinate
        self.verdict = verdict
        self.source = source
        self.probability = probability
        self.detected = detected
        self.arm = arm
        self.reviewedAt = reviewedAt
    }
}

/// Every park's tower labels in one JSON file (`tower-labels.json`), written after every verdict so
/// a review session can stop at any time. The app shares this file; the tracer reads it.
public struct TowerLabelStore: Codable, Equatable, Sendable {
    public var version = 1
    public var parks: [String: [TowerLabel]] = [:]

    public init() {}

    public static let fileName = "tower-labels.json"
    /// The name before the rename (2026-11-03); still read when no `fileName` exists yet.
    public static let legacyFileName = "mast-labels.json"

    public static func load(from url: URL) throws -> TowerLabelStore {
        guard FileManager.default.fileExists(atPath: url.path) else { return TowerLabelStore() }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> TowerLabelStore {
        try JSONDecoder().decode(TowerLabelStore.self, from: data)
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

    public func labels(for parkID: String) -> [TowerLabel] { parks[parkID] ?? [] }

    public var reviewedParkIDs: Set<String> { Set(parks.filter { !$0.value.isEmpty }.keys) }

    public var labelCount: Int { parks.values.reduce(0) { $0 + $1.count } }

    public func count(_ verdict: TowerLabel.Verdict, in parkID: String) -> Int {
        labels(for: parkID).filter { $0.verdict == verdict }.count
    }

    public mutating func add(_ label: TowerLabel, to parkID: String) {
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

/// The satellite close-up a review ran on, saved next to the labels so the training set can be
/// built from the phone's own images (no Mac needed to render them again). The image itself is
/// `<file stem>.jpg`; this is `<file stem>.json` beside it.
public struct TowerReviewSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var parkID: String
    /// Coordinate of the image centre.
    public var center: ParkCoordinate
    public var metersPerPixel: Double
    public var widthPx: Int
    public var heightPx: Int
    /// ISO 8601, UTC.
    public var takenAt: String

    public init(parkID: String, image: DetectionImage, takenAt: Date = Date()) {
        self.parkID = parkID
        center = image.center
        metersPerPixel = image.metersPerPixel
        widthPx = image.width
        heightPx = image.height
        self.takenAt = ISO8601DateFormatter().string(from: takenAt)
    }

    /// File stem for this snapshot: park id plus the time it was taken, so several looks at one park all stay.
    public var fileStem: String {
        "\(parkID)-\(takenAt.filter { $0.isNumber })"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Which parks to review, handed to the app as `tower-review-request.json`. Without a request the
/// app offers every park that has no traced cable.
public struct TowerReviewRequest: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        /// Shown when the park is not on this phone (an id the app does not know).
        public var name: String?
        /// Why this park is on the list, e.g. "no cable traced" or "detector found 2 of 5 towers".
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

    public init(createdAt: String = TowerLabelStore.today(), note: String? = nil, parks: [Item]) {
        self.createdAt = createdAt
        self.note = note
        self.parks = parks
    }

    public static func decode(_ data: Data) throws -> TowerReviewRequest {
        try JSONDecoder().decode(TowerReviewRequest.self, from: data)
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
public struct TowerReviewSession: Equatable, Sendable {
    public struct Candidate: Identifiable, Equatable, Sendable {
        public var id: Int
        public var coordinate: ParkCoordinate
        public var probability: Double
    }

    /// Detections below this are not worth a look; the app's own cut-off is higher.
    public static let minimumProbability = 0.3
    /// A "Tower" or "Not visible" verdict takes the crosshair position when it is this close to the
    /// detection, so the reviewer can centre the tower; further away the reviewer looked at something else.
    public static let maximumCorrectionM = 90.0

    public let parkID: String
    public private(set) var candidates: [Candidate]
    public private(set) var currentIndex: Int?

    public init(parkID: String, detected: [DetectedTower], image: DetectionImage, labels: TowerLabelStore, minimumProbability: Double = TowerReviewSession.minimumProbability) {
        self.parkID = parkID
        candidates = detected.enumerated()
            .compactMap { index, tower -> Candidate? in
                guard tower.probability >= minimumProbability else { return nil }
                let coordinate = image.coordinate(fromLocal: tower.xy)
                guard !labels.isReviewed(coordinate, in: parkID) else { return nil }
                return Candidate(id: index, coordinate: coordinate, probability: tower.probability)
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

    /// Records the verdict for the current candidate and moves on. A tower (or a tower that is not
    /// visible) is saved where the crosshair is when the reviewer moved it onto the tower; the other
    /// verdicts keep the detection. `arm` is kept only on a tower placed at the crosshair.
    public mutating func judge(_ verdict: TowerLabel.Verdict, crosshair: ParkCoordinate?, arm: TowerLabel.Arm? = nil, reviewedAt: String = TowerLabelStore.today()) -> TowerLabel? {
        guard let index = currentIndex else { return nil }
        let candidate = candidates[index]
        var coordinate = candidate.coordinate
        var detected: ParkCoordinate?
        var keptArm: TowerLabel.Arm?
        if verdict == .tower || verdict == .notVisible, let crosshair, crosshair.meters(to: candidate.coordinate) <= Self.maximumCorrectionM {
            coordinate = crosshair
            if crosshair.meters(to: candidate.coordinate) > 1 { detected = candidate.coordinate }
            if verdict == .tower { keptArm = arm }
        }
        candidates.remove(at: index)
        currentIndex = candidates.isEmpty ? nil : index % candidates.count
        return TowerLabel(coordinate: coordinate, verdict: verdict, source: .detector, probability: candidate.probability, detected: detected, arm: keptArm, reviewedAt: reviewedAt)
    }

    /// A tower the detector missed, placed by the reviewer.
    public static func manualTower(at coordinate: ParkCoordinate, arm: TowerLabel.Arm? = nil, reviewedAt: String = TowerLabelStore.today()) -> TowerLabel {
        TowerLabel(coordinate: coordinate, verdict: .tower, source: .manual, arm: arm, reviewedAt: reviewedAt)
    }

    /// A tower the reviewer knows stands here although the imagery does not show it.
    public static func manualNotVisible(at coordinate: ParkCoordinate, reviewedAt: String = TowerLabelStore.today()) -> TowerLabel {
        TowerLabel(coordinate: coordinate, verdict: .notVisible, source: .manual, reviewedAt: reviewedAt)
    }
}
