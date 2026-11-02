import Foundation
import Testing
@testable import RpplCore

@Suite("ParkWalkRouteBuilder")
struct ParkWalkRouteBuilderTests {
    private let latPerMeter = 1.0 / 110_574
    private var lonPerMeter: Double { 1.0 / (111_320 * cos(52.0 * .pi / 180)) }

    /// Deterministic jitter in [-amplitude, amplitude].
    private struct Noise {
        var state: UInt64
        mutating func next(_ amplitude: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double(state >> 11) / Double(1 << 53) * 2 - 1) * amplitude
        }
    }

    /// A walk east along y = 0 from `from` to `to` meters, a fix every 8 m, jittered.
    private func walk(from: Double, to: Double, seed: UInt64, offsetNorth: Double = 0) -> [MapCoordinate] {
        var noise = Noise(state: seed)
        return stride(from: from, through: to, by: 8).map { east in
            MapCoordinate(
                latitude: 52.0 + (offsetNorth + noise.next(3)) * latPerMeter,
                longitude: 5.0 + (east + noise.next(3)) * lonPerMeter
            )
        }
    }

    private func meters(_ a: MapCoordinate, _ b: MapCoordinate) -> Double {
        GeoDistance.meters(fromLat: a.latitude, fromLon: a.longitude, toLat: b.latitude, toLon: b.longitude)
    }

    private func length(_ line: [MapCoordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + meters($1.0, $1.1) }
    }

    @Test func parallelWalksBundleIntoOneLine() throws {
        let sessions: [[[MapCoordinate]]] = (0..<5).map { session in
            [walk(from: 0, to: 200, seed: UInt64(session + 1), offsetNorth: Double(session) - 2)]
        }
        let sections = ParkWalkRouteBuilder.sections(sessionTracks: sessions)

        #expect(sections.count == 1)
        let line = try #require(sections.first)
        #expect(length(line) > 150)
        #expect(length(line) < 230)
        // Every averaged point sits on the shared line, not on one session's offset.
        for point in line {
            #expect(abs(point.latitude - 52.0) / latPerMeter < 6)
        }
    }

    @Test func separateWalksBecomeSeparateSections() {
        let near = (0..<4).map { [walk(from: 0, to: 120, seed: UInt64($0 + 10))] }
        let far = (0..<4).map { [walk(from: 0, to: 120, seed: UInt64($0 + 20), offsetNorth: 300)] }
        let sections = ParkWalkRouteBuilder.sections(sessionTracks: zip(near, far).map { $0 + $1 })
        #expect(sections.count == 2)
    }

    @Test func tooFewPointsGiveNothing() {
        #expect(ParkWalkRouteBuilder.sections(sessionTracks: []).isEmpty)
        #expect(ParkWalkRouteBuilder.sections(sessionTracks: [[walk(from: 0, to: 16, seed: 3)]]).isEmpty)
    }

    @Test func oneSessionAloneStillGetsARoute() {
        // Below the multi-session minimum a single walk, passed twice (there and back), is enough.
        let there = walk(from: 0, to: 160, seed: 5)
        let back = Array(walk(from: 0, to: 160, seed: 6).reversed())
        let sections = ParkWalkRouteBuilder.sections(sessionTracks: [[there, back]])
        #expect(sections.count == 1)
    }
}
