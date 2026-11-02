import XCTest
import RpplCore
@testable import CableTracerCore

final class CableTracerCoreTests: XCTestCase {
    let almere = ParkCoordinate(lat: 52.3581295, lon: 5.2152087)

    /// VIEW Almere, main cable, as traced in the repo.
    var almereLoop: ParkCable {
        ParkCable(name: "Grote baan", direction: .counterClockwise, points: [
            ParkCablePoint(lat: 52.3585546998476, lon: 5.21501871403023),
            ParkCablePoint(lat: 52.358864713801, lon: 5.21908686853842),
            ParkCablePoint(lat: 52.3599809561145, lon: 5.22001190227344),
            ParkCablePoint(lat: 52.3604782564784, lon: 5.21877488269814),
            ParkCablePoint(lat: 52.35914944718, lon: 5.21479179321656),
        ])
    }

    var almereTwoPointZero: ParkCable {
        ParkCable(name: "Alta Twin", direction: .twoPointZero, lengthM: 200, points: [
            ParkCablePoint(lat: 52.3582029191082, lon: 5.21550000719344),
            ParkCablePoint(lat: 52.358431785598, lon: 5.21836969075431),
        ])
    }

    func testProjectionRoundTrips() {
        let projection = LocalProjection(origin: almere)
        let point = ParkCoordinate(lat: 52.3604782564784, lon: 5.21877488269814)
        let back = projection.coordinate(projection.xy(point))
        XCTAssertEqual(back.lat, point.lat, accuracy: 1e-9)
        XCTAssertEqual(back.lon, point.lon, accuracy: 1e-9)
        XCTAssertEqual(projection.xy(point).length, almere.meters(to: point), accuracy: 0.5)
    }

    func testLoopGeometryMatchesRepoLength() {
        let geometry = CableGeometry(cable: almereLoop, parkLocation: almere)
        XCTAssertEqual(geometry.kind, .loop)
        XCTAssertTrue(geometry.isClosed)
        XCTAssertEqual(geometry.segmentLengthsM.count, 5)
        XCTAssertEqual(geometry.pathLengthM, almereLoop.computedLengthM!, accuracy: 1)
        XCTAssertGreaterThan(geometry.axes.lengthM, 300)
        XCTAssertGreaterThan(geometry.axes.widthM, 50)
        XCTAssertFalse(geometry.isSelfIntersecting)
        XCTAssertEqual(geometry.turnAnglesDeg.count, 5)
    }

    func testStraightGeometry() {
        let geometry = CableGeometry(cable: almereTwoPointZero, parkLocation: almere)
        XCTAssertEqual(geometry.kind, .straight)
        XCTAssertFalse(geometry.isClosed)
        XCTAssertEqual(geometry.pathLengthM, 197, accuracy: 3)
        XCTAssertEqual(geometry.axes.widthM, 0, accuracy: 0.01)
        XCTAssertTrue(geometry.turnAnglesDeg.isEmpty)
    }

    func testCleanParkHasNoFindings() {
        let park = Park(id: "almere", name: "VIEW", location: almere, cables: [almereLoop, almereTwoPointZero])
        XCTAssertEqual(CableLint.check(park), [])
    }

    func testLintFlagsImplausibleShapes() {
        var tiny = almereLoop
        tiny.points = [
            ParkCablePoint(lat: 52.3585, lon: 5.2150),
            ParkCablePoint(lat: 52.3586, lon: 5.2151),
            ParkCablePoint(lat: 52.3587, lon: 5.2150),
            ParkCablePoint(lat: 52.3586, lon: 5.2149),
        ]
        let findings = CableLint.check(tiny, index: 0, parkLocation: almere)
        XCTAssertTrue(findings.contains { $0.severity == .error && $0.message.contains("not a cable-park size") })

        var far = almereTwoPointZero
        far.points?[1] = ParkCablePoint(lat: 52.40, lon: 5.30)
        let farFindings = CableLint.check(far, index: 1, parkLocation: almere)
        XCTAssertTrue(farFindings.contains { $0.severity == .error && $0.message.contains("from the park location") })

        var crossed = almereLoop
        crossed.points?.swapAt(1, 2)
        XCTAssertTrue(CableLint.check(crossed, index: 0, parkLocation: almere).contains { $0.message.contains("crosses itself") })

        var mislabeled = almereTwoPointZero
        mislabeled.direction = .counterClockwise
        XCTAssertTrue(CableLint.check(mislabeled, index: 0, parkLocation: almere).contains { $0.message.contains("is this a 2.0") })
    }

    func testPriorAndTemplates() {
        let park = Park(id: "almere", name: "VIEW", location: almere, cables: [almereLoop, almereTwoPointZero])
        let prior = CablePrior.learn(from: [park])
        XCTAssertEqual(prior.loop.sampleCount, 1)
        XCTAssertEqual(prior.loop.pathLengthM, almereLoop.computedLengthM!, accuracy: 1)
        XCTAssertEqual(prior.straight.pathLengthM, 197, accuracy: 3)

        let loop = CableTemplate.loop(at: almere, prior: prior.loop, headingDegrees: 30)
        XCTAssertEqual(loop.points?.count, 4)
        XCTAssertEqual(loop.points?.first?.start, true)
        let geometry = CableGeometry(cable: loop, parkLocation: almere)
        XCTAssertEqual(geometry.axes.lengthM, prior.loop.extentLengthM, accuracy: 0.5)
        XCTAssertEqual(geometry.axes.widthM, prior.loop.extentWidthM, accuracy: 0.5)
        XCTAssertEqual(geometry.axes.headingDegrees, 30, accuracy: 0.5)
        XCTAssertFalse(geometry.isSelfIntersecting)
        XCTAssertEqual(CableLint.check(loop, index: 0, parkLocation: almere).filter { $0.severity == .error }, [])

        let turned = CableTemplate.rotated(loop, by: 45, parkLocation: almere)
        XCTAssertEqual(CableGeometry(cable: turned, parkLocation: almere).axes.headingDegrees, 75, accuracy: 0.5)

        let straight = CableTemplate.straight(at: almere, prior: prior.straight, headingDegrees: 90)
        XCTAssertEqual(CableGeometry(cable: straight, parkLocation: almere).pathLengthM, prior.straight.pathLengthM, accuracy: 0.5)
    }

    func testTrainingRowsSkipUntracedParks() throws {
        let traced = Park(id: "a", name: "A", location: almere, cables: [almereLoop])
        let untraced = Park(id: "b", name: "B", location: almere, cables: [ParkCable(name: "Cable")])
        let rows = TrainingSet.rows(parks: [traced, untraced])
        XCTAssertEqual(rows.map(\.parkID), ["a"])
        XCTAssertEqual(TrainingSet.rows(parks: [traced, untraced], tracedOnly: false).count, 2)
        let data = try TrainingSet.encode(rows)
        let decoded = try JSONDecoder().decode([TrainingRow].self, from: data)
        XCTAssertEqual(decoded, rows)
    }
}
