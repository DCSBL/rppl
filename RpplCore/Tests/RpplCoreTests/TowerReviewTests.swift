import Foundation
import Testing
@testable import RpplCore

struct TowerReviewTests {
    private let almere = ParkCoordinate(lat: 52.3581295, lon: 5.2152087)
    private let tower = ParkCoordinate(lat: 52.3585546998476, lon: 5.21501871403023)

    private var image: DetectionImage {
        DetectionImage(width: 2, height: 2, rgb: [UInt8](repeating: 0, count: 12), metersPerPixel: 1, center: almere, origin: almere)
    }

    @Test func storeRoundTripsAndFindsReviewedDetections() throws {
        var store = TowerLabelStore()
        let peak = ParkCoordinate(lat: 52.35856, lon: 5.21509)  // 5 m from the tower
        store.add(TowerLabel(coordinate: tower, verdict: .tower, source: .detector, probability: 0.8, detected: peak, reviewedAt: "2026-11-03"), to: "view-almere")
        store.add(TowerLabel(coordinate: almere, verdict: .notTower, source: .detector, probability: 0.6, reviewedAt: "2026-11-03"), to: "view-almere")
        #expect(store.isReviewed(peak, in: "view-almere"))
        #expect(store.isReviewed(almere, in: "view-almere"))
        #expect(!store.isReviewed(ParkCoordinate(lat: 52.3599809561145, lon: 5.22001190227344), in: "view-almere"))
        #expect(!store.isReviewed(peak, in: "other-park"))
        #expect(store.labelCount == 2)
        #expect(store.count(.tower, in: "view-almere") == 1)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tower-labels-\(UUID().uuidString).json")
        try store.save(to: url)
        let loaded = try TowerLabelStore.load(from: url)
        #expect(loaded == store)
        #expect(loaded.reviewedParkIDs == ["view-almere"])
        #expect(try TowerLabelStore.load(from: url.appendingPathExtension("missing")) == TowerLabelStore())

        let json = try #require(try JSONSerialization.jsonObject(with: store.encoded()) as? [String: Any])
        let parks = try #require(json["parks"] as? [String: [[String: Any]]])
        #expect(parks["view-almere"]?.map { $0["verdict"] as? String } == ["tower", "none"])

        var removed = loaded
        for label in loaded.labels(for: "view-almere") { removed.remove(label.id, from: "view-almere") }
        #expect(removed.parks.isEmpty)
    }

    @Test func filesFromBeforeTheRenameStillLoad() throws {
        let json = """
        {"version": 1, "parks": {"p": [{"id": "6BCC5008-98E5-4C1B-8B44-BF46D8FB97EC", "coordinate": {"lat": 52.1, "lon": 5.2},
          "verdict": "mast", "source": "detector", "probability": 0.9, "reviewedAt": "2026-11-03"}]}}
        """
        let store = try TowerLabelStore.decode(Data(json.utf8))
        #expect(store.labels(for: "p").map(\.verdict) == [.tower])
        let reencoded = try #require(try JSONSerialization.jsonObject(with: store.encoded()) as? [String: Any])
        let parks = try #require(reencoded["parks"] as? [String: [[String: Any]]])
        #expect(parks["p"]?.first?["verdict"] as? String == "tower")
    }

    @Test func requestRoundTrips() throws {
        let request = TowerReviewRequest(createdAt: "2026-11-03", note: "Untraced parks", parks: [
            TowerReviewRequest.Item(id: "view-almere", name: "VIEW Almere", reason: "no cable traced"),
            TowerReviewRequest.Item(id: "other"),
        ])
        let decoded = try TowerReviewRequest.decode(try request.encoded())
        #expect(decoded == request)
        #expect(decoded.parks.map(\.id) == ["view-almere", "other"])
    }

    @Test func sessionOrdersSkipsAndJudgesCandidates() {
        var labels = TowerLabelStore()
        labels.add(TowerLabel(coordinate: image.coordinate(fromLocal: SIMD2(100, 0)), verdict: .notTower, source: .detector, reviewedAt: "2026-11-03"), to: "p")
        let detected = [
            DetectedTower(xy: SIMD2(0, 0), probability: 0.4),
            DetectedTower(xy: SIMD2(100, 0), probability: 0.9),  // already judged
            DetectedTower(xy: SIMD2(0, 100), probability: 0.7),
            DetectedTower(xy: SIMD2(50, 50), probability: 0.2),  // below the cut-off
        ]
        var session = TowerReviewSession(parkID: "p", detected: detected, image: image, labels: labels)
        #expect(session.remaining == 2)
        #expect(session.position == 1)
        #expect(session.current?.probability == 0.7)

        session.skip()
        #expect(session.current?.probability == 0.4)
        session.skip()
        #expect(session.current?.probability == 0.7)

        // Tower, with the crosshair 5 m off: the label moves and remembers the detection.
        let crosshair = image.coordinate(fromLocal: SIMD2(0, 105))
        let judged = session.judge(.tower, crosshair: crosshair, reviewedAt: "2026-11-03")
        #expect(judged?.verdict == .tower)
        #expect(judged?.source == .detector)
        #expect(judged?.probability == 0.7)
        #expect(judged?.coordinate == crosshair)
        #expect((judged?.detected.map { image.coordinate(fromLocal: SIMD2(0, 100)).meters(to: $0) } ?? 99) < 0.1)
        #expect(session.remaining == 1)
        #expect(session.current?.probability == 0.4)

        // Not a tower, with the crosshair far away: the detection itself is the label.
        let rejected = session.judge(.notTower, crosshair: image.coordinate(fromLocal: SIMD2(300, 300)), reviewedAt: "2026-11-03")
        #expect(rejected?.verdict == .notTower)
        #expect(rejected?.detected == nil)
        #expect((rejected.map { almere.meters(to: $0.coordinate) } ?? 99) < 0.1)
        #expect(session.current == nil)
        let nothing = session.judge(.unsure, crosshair: nil)
        #expect(nothing == nil)
    }

    @Test func guessesFollowTheNearestRemainingOne() {
        // Most confident in the middle; the walk then hops to the nearest each time, not by confidence.
        let detected = [
            DetectedTower(xy: SIMD2(0, 0), probability: 0.9),
            DetectedTower(xy: SIMD2(300, 0), probability: 0.8),
            DetectedTower(xy: SIMD2(-50, 0), probability: 0.4),
            DetectedTower(xy: SIMD2(-120, 0), probability: 0.6),
            DetectedTower(xy: SIMD2(200, 0), probability: 0.5),
        ]
        var session = TowerReviewSession(parkID: "p", detected: detected, image: image, labels: TowerLabelStore())
        #expect(session.candidates.map(\.probability) == [0.9, 0.4, 0.6, 0.5, 0.8])
        _ = session.judge(.notTower, crosshair: nil)
        #expect(session.current?.probability == 0.4)
        session.skip()
        #expect(session.current?.probability == 0.6)
    }

    @Test func towerVerdictIgnoresACrosshairThatWanderedOff() {
        var session = TowerReviewSession(parkID: "p", detected: [DetectedTower(xy: SIMD2(0, 0), probability: 0.5)], image: image, labels: TowerLabelStore())
        let label = session.judge(.tower, crosshair: image.coordinate(fromLocal: SIMD2(0, 200)))
        #expect((label.map { almere.meters(to: $0.coordinate) } ?? 99) < 0.1)
        #expect(label?.detected == nil)
        #expect(TowerReviewSession.manualTower(at: almere).source == .manual)
    }

    @Test func armRunsFromTheWheelToTheFoot() throws {
        let south = ParkCoordinate(lat: almere.lat - 15 / 111_320, lon: almere.lon)
        let arm = try #require(TowerLabel.Arm(wheel: almere, foot: south))
        #expect(abs(arm.bearingDeg - 180) < 0.5)
        #expect(abs(arm.lengthM - 15) < 0.2)
        let west = ParkCoordinate(lat: almere.lat, lon: almere.lon - 10 / (111_320 * cos(almere.lat * .pi / 180)))
        #expect(abs((TowerLabel.Arm(wheel: almere, foot: west)?.bearingDeg ?? 0) - 270) < 0.5)
        #expect(TowerLabel.Arm(wheel: almere, foot: almere) == nil)
    }

    @Test func frameVerdictsKeepTheArmOnlyOnATower() throws {
        let detected = [DetectedTower(xy: SIMD2(0, 0), probability: 0.8), DetectedTower(xy: SIMD2(0, 30), probability: 0.6), DetectedTower(xy: SIMD2(0, 60), probability: 0.5)]
        var session = TowerReviewSession(parkID: "p", detected: detected, image: image, labels: TowerLabelStore())
        let arm = TowerLabel.Arm(bearingDeg: 205, lengthM: 15)
        let crosshair = image.coordinate(fromLocal: SIMD2(2, 0))
        let tower = session.judge(.tower, crosshair: crosshair, arm: arm, reviewedAt: "2026-11-04")
        #expect(tower?.arm == arm)
        #expect(tower?.coordinate == crosshair)

        // Not visible: saved where the reviewer says it stands, without an arm.
        let hidden = session.judge(.notVisible, crosshair: image.coordinate(fromLocal: SIMD2(0, 36)), arm: arm, reviewedAt: "2026-11-04")
        #expect(hidden?.verdict == .notVisible)
        #expect(hidden?.arm == nil)
        #expect((hidden.map { image.coordinate(fromLocal: SIMD2(0, 36)).meters(to: $0.coordinate) } ?? 99) < 0.1)

        let rejected = session.judge(.notTower, crosshair: crosshair, arm: arm, reviewedAt: "2026-11-04")
        #expect(rejected?.arm == nil)

        var store = TowerLabelStore()
        for label in [tower, hidden, rejected].compactMap({ $0 }) { store.add(label, to: "p") }
        store.add(TowerReviewSession.manualNotVisible(at: almere, reviewedAt: "2026-11-04"), to: "p")
        let decoded = try TowerLabelStore.decode(store.encoded())
        #expect(decoded == store)
        #expect(decoded.count(.notVisible, in: "p") == 2)
        let json = try #require(try JSONSerialization.jsonObject(with: store.encoded()) as? [String: Any])
        let parks = try #require(json["parks"] as? [String: [[String: Any]]])
        #expect(parks["p"]?.map { $0["verdict"] as? String } == ["tower", "notVisible", "none", "notVisible"])
        let encodedArm = try #require(parks["p"]?.first?["arm"] as? [String: Any])
        #expect((encodedArm["bearingDeg"] as? NSNumber)?.doubleValue == 205)
    }

    @Test func snapshotDescribesTheImageItRanOn() throws {
        let image = DetectionImage(width: 2, height: 2, rgb: [UInt8](repeating: 0, count: 12), metersPerPixel: 0.293, center: tower, origin: almere)
        let snapshot = TowerReviewSnapshot(parkID: "view-almere", image: image, takenAt: Date(timeIntervalSince1970: 1_793_900_000))
        #expect(snapshot.center == tower)
        #expect(snapshot.widthPx == 2)
        #expect(snapshot.fileStem.hasPrefix("view-almere-2026"))
        #expect(snapshot.fileStem.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        let decoded = try JSONDecoder().decode(TowerReviewSnapshot.self, from: snapshot.encoded())
        #expect(decoded == snapshot)
    }
}
