import Foundation
import Testing
@testable import RpplCore

struct MastReviewTests {
    private let almere = ParkCoordinate(lat: 52.3581295, lon: 5.2152087)
    private let mast = ParkCoordinate(lat: 52.3585546998476, lon: 5.21501871403023)

    private var image: DetectionImage {
        DetectionImage(width: 2, height: 2, rgb: [UInt8](repeating: 0, count: 12), metersPerPixel: 1, center: almere, origin: almere)
    }

    @Test func storeRoundTripsAndFindsReviewedDetections() throws {
        var store = MastLabelStore()
        let peak = ParkCoordinate(lat: 52.35856, lon: 5.21509)  // 5 m from the mast
        store.add(MastLabel(coordinate: mast, verdict: .mast, source: .detector, probability: 0.8, detected: peak, reviewedAt: "2026-11-03"), to: "view-almere")
        store.add(MastLabel(coordinate: almere, verdict: .notMast, source: .detector, probability: 0.6, reviewedAt: "2026-11-03"), to: "view-almere")
        #expect(store.isReviewed(peak, in: "view-almere"))
        #expect(store.isReviewed(almere, in: "view-almere"))
        #expect(!store.isReviewed(ParkCoordinate(lat: 52.3599809561145, lon: 5.22001190227344), in: "view-almere"))
        #expect(!store.isReviewed(peak, in: "other-park"))
        #expect(store.labelCount == 2)
        #expect(store.count(.mast, in: "view-almere") == 1)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mast-labels-\(UUID().uuidString).json")
        try store.save(to: url)
        let loaded = try MastLabelStore.load(from: url)
        #expect(loaded == store)
        #expect(loaded.reviewedParkIDs == ["view-almere"])
        #expect(try MastLabelStore.load(from: url.appendingPathExtension("missing")) == MastLabelStore())

        let json = try #require(try JSONSerialization.jsonObject(with: store.encoded()) as? [String: Any])
        let parks = try #require(json["parks"] as? [String: [[String: Any]]])
        #expect(parks["view-almere"]?.map { $0["verdict"] as? String } == ["mast", "none"])

        var removed = loaded
        for label in loaded.labels(for: "view-almere") { removed.remove(label.id, from: "view-almere") }
        #expect(removed.parks.isEmpty)
    }

    @Test func requestRoundTrips() throws {
        let request = MastReviewRequest(createdAt: "2026-11-03", note: "Untraced parks", parks: [
            MastReviewRequest.Item(id: "view-almere", name: "VIEW Almere", reason: "no cable traced"),
            MastReviewRequest.Item(id: "other"),
        ])
        let decoded = try MastReviewRequest.decode(try request.encoded())
        #expect(decoded == request)
        #expect(decoded.parks.map(\.id) == ["view-almere", "other"])
    }

    @Test func sessionOrdersSkipsAndJudgesCandidates() {
        var labels = MastLabelStore()
        labels.add(MastLabel(coordinate: image.coordinate(fromLocal: SIMD2(100, 0)), verdict: .notMast, source: .detector, reviewedAt: "2026-11-03"), to: "p")
        let detected = [
            DetectedMast(xy: SIMD2(0, 0), probability: 0.4),
            DetectedMast(xy: SIMD2(100, 0), probability: 0.9),  // already judged
            DetectedMast(xy: SIMD2(0, 100), probability: 0.7),
            DetectedMast(xy: SIMD2(50, 50), probability: 0.2),  // below the cut-off
        ]
        var session = MastReviewSession(parkID: "p", detected: detected, image: image, labels: labels)
        #expect(session.remaining == 2)
        #expect(session.position == 1)
        #expect(session.current?.probability == 0.7)

        session.skip()
        #expect(session.current?.probability == 0.4)
        session.skip()
        #expect(session.current?.probability == 0.7)

        // Mast, with the crosshair 5 m off: the label moves and remembers the detection.
        let crosshair = image.coordinate(fromLocal: SIMD2(0, 105))
        let judged = session.judge(.mast, crosshair: crosshair, reviewedAt: "2026-11-03")
        #expect(judged?.verdict == .mast)
        #expect(judged?.source == .detector)
        #expect(judged?.probability == 0.7)
        #expect(judged?.coordinate == crosshair)
        #expect((judged?.detected.map { image.coordinate(fromLocal: SIMD2(0, 100)).meters(to: $0) } ?? 99) < 0.1)
        #expect(session.remaining == 1)
        #expect(session.current?.probability == 0.4)

        // Not a mast, with the crosshair far away: the detection itself is the label.
        let rejected = session.judge(.notMast, crosshair: image.coordinate(fromLocal: SIMD2(300, 300)), reviewedAt: "2026-11-03")
        #expect(rejected?.verdict == .notMast)
        #expect(rejected?.detected == nil)
        #expect((rejected.map { almere.meters(to: $0.coordinate) } ?? 99) < 0.1)
        #expect(session.current == nil)
        let nothing = session.judge(.unsure, crosshair: nil)
        #expect(nothing == nil)
    }

    @Test func mastVerdictIgnoresACrosshairThatWanderedOff() {
        var session = MastReviewSession(parkID: "p", detected: [DetectedMast(xy: SIMD2(0, 0), probability: 0.5)], image: image, labels: MastLabelStore())
        let label = session.judge(.mast, crosshair: image.coordinate(fromLocal: SIMD2(0, 200)))
        #expect((label.map { almere.meters(to: $0.coordinate) } ?? 99) < 0.1)
        #expect(label?.detected == nil)
        #expect(MastReviewSession.manualMast(at: almere).source == .manual)
    }
}
