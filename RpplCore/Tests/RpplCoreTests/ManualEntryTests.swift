import Foundation
import Testing
@testable import RpplCore

@Suite("Manual sessions", .serialized)
struct ManualEntryTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let loop = ParkCable(direction: .clockwise, lengthM: 1_000)
    private let twoPointZero = ParkCable(direction: .twoPointZero, lengthM: 400)
    private let unknown = ParkCable(direction: .clockwise)

    private func manifest(
        id: String = UUID().uuidString,
        start: Date? = nil,
        entry: ManualEntry
    ) -> SessionManifest {
        let start = start ?? t0
        return SessionManifest(
            sessionId: id, testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "none",
            systemVersion: "26.0", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            transferState: .acknowledged, parkIdSource: SessionParkSource.manual, manual: entry
        )
    }

    private func makeStore() -> (SessionFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        return (SessionFileStore(rootURL: root), root)
    }

    // MARK: Distance estimate

    @Test func lapLengthLoopIsLengthAndTwoPointZeroIsThereAndBack() {
        #expect(loop.lapLengthM == 1_000)
        #expect(twoPointZero.lapLengthM == 800)
        #expect(unknown.lapLengthM == nil)
    }

    @Test func distanceSumsLapsPerCable() {
        let tallies = [ManualEntry.Tally(sets: 1, laps: 3), .init(sets: 2, laps: 2)]
        #expect(ManualEntry.distanceM(tallies: tallies, cables: [loop, twoPointZero]) == 3 * 1_000 + 2 * 800)
    }

    @Test func distanceIsNilWithoutLengthOrLapsOrCable() {
        let rode = [ManualEntry.Tally(sets: 1, laps: 2)]
        #expect(ManualEntry.distanceM(tallies: rode, cables: [unknown]) == nil)
        #expect(ManualEntry.distanceM(tallies: rode, cables: []) == nil)
        #expect(ManualEntry.distanceM(tallies: [.init(sets: 1, laps: 0)], cables: [loop]) == nil)
        // A cable that was not ridden may lack a length.
        #expect(ManualEntry.distanceM(tallies: [.init(sets: 0, laps: 0), .init(sets: 1, laps: 1)], cables: [unknown, loop]) == 1_000)
    }

    @Test func totalsSumTalliesAndLapsMayBeBelowSets() {
        let entry = ManualEntry(tallies: [.init(sets: 3, laps: 1), .init(sets: 0, laps: 0)])
        #expect(entry.setCount == 3 && entry.lapCount == 1)
    }

    // MARK: Stats and storage

    @Test func statsComeFromTheEntryAndSurviveReanalysis() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = ManualEntry(
            tallies: [.init(sets: 2, laps: 5)], distanceM: 5_000, location: ParkCoordinate(lat: 52, lon: 5)
        )
        let m = manifest(entry: entry)
        try store.saveManual(m, label: "Park A")

        let stats = try store.ensureDerivedView(sessionId: m.sessionId).stats
        #expect(stats.setCount == 2 && stats.totalLapCount == 5 && stats.sets.isEmpty)
        #expect(stats.totalDistanceMeters == 5_000 && stats.totalDuration == 3_600)

        let rebuilt = try store.reanalyzeSession(sessionId: m.sessionId)
        #expect(rebuilt.stats == stats)
        #expect(rebuilt.cityName == "Park A")
        #expect(rebuilt.mapFrame?.centerLatitude == 52 && rebuilt.mapFrame?.centerLongitude == 5)
        #expect(try SessionLoader.load(store: store, sessionId: m.sessionId).stats.setCount == 2)
    }

    @Test func editRewritesCountsDateAndFolder() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        var m = manifest(entry: ManualEntry(tallies: [.init(sets: 1, laps: 1)]))
        try store.saveManual(m, label: "Park A")
        let before = try store.sessionDirectory(for: m.sessionId).lastPathComponent
        #expect(before.hasSuffix("Park A"))

        m = try store.readManifest(sessionId: m.sessionId)
        m.startedAt = t0.addingTimeInterval(-3 * 86_400)
        m.endedAt = m.startedAt.addingTimeInterval(1_800)
        m.manual = ManualEntry(tallies: [.init(sets: 4, laps: 2)])
        try store.saveManual(m, label: nil)

        let stats = try store.ensureDerivedView(sessionId: m.sessionId).stats
        #expect(stats.setCount == 4 && stats.totalLapCount == 2 && stats.totalDuration == 1_800)
        #expect(try store.readDerivedView(sessionId: m.sessionId)?.cityName == nil)
        #expect(try store.sessionDirectory(for: m.sessionId).lastPathComponent != before)
        #expect(try store.listSessionIDs() == [m.sessionId])
    }

    @Test func manifestRoundTripsAndOldManifestsHaveNoEntry() throws {
        let entry = ManualEntry(tallies: [.init(sets: 1, laps: 2)], distanceM: 800, location: ParkCoordinate(lat: 1, lon: 2))
        let m = manifest(entry: entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(SessionManifest.self, from: encoder.encode(m)).manual == entry)

        var tracked = m
        tracked.manual = nil
        let json = try encoder.encode(tracked)
        #expect(String(bytes: json, encoding: .utf8)?.contains("\"manual\":") == false)
        #expect(try decoder.decode(SessionManifest.self, from: json).manual == nil)
    }

    @Test func onlyManualSessionsSkipTheWatchMirror() {
        #expect(manifest(entry: ManualEntry()).mirrorsToWatch == false)
        #expect(SessionManifest(testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "W", systemVersion: "26").mirrorsToWatch)
    }
}
