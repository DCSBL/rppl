import Foundation
import Testing
@testable import RpplCore

@Suite("ExampleSession")
struct ExampleSessionTests {
    /// A real multi-set park day as a raw export: detections replayed from its GPS, plus health
    /// and water the compiled form drops.
    private func rawPackage() throws -> SessionTransferPackage {
        let fixture = try SessionFixture.load("project7-2026-10-04")
        let start = fixture.locations.map(\.timestamp).min() ?? fixture.manifest.startedAt
        return SessionTransferPackage(
            manifest: fixture.manifest,
            detections: DetectionEngine.replay(locations: fixture.locations),
            locations: fixture.locations,
            health: [HealthMetricSample(timestamp: start, heartRateBPM: 120)],
            water: [WaterTemperatureSample(timestamp: start, celsius: 18)],
            battery: [BatterySample(timestamp: start, level: 0.9, state: BatteryStateCodes.unplugged)]
        )
    }

    private func roundTrip(_ package: SessionTransferPackage) throws -> SessionTransferPackage {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try SessionImportLimits.decodeTransferPackage(from: encoder.encode(package))
    }

    @Test func compileKeepsOnlyWhatTheDetailDraws() throws {
        let raw = try rawPackage()
        let compiled = ExampleSessionCompiler.compile(raw)
        let derived = try #require(compiled.derived)

        #expect(derived.isCurrentAnalyzer)
        #expect(derived.stats.sets.count > 1)
        #expect(derived.mapFrame == nil)
        #expect(derived.cityName == nil)
        #expect(compiled.manifest == raw.manifest)
        #expect(compiled.detections == raw.detections)
        #expect(compiled.health.isEmpty)
        #expect(compiled.water.isEmpty)
        #expect(compiled.battery.isEmpty)
        #expect(compiled.motion.isEmpty)
        #expect(compiled.motionFramesZlib == nil)

        // Only GPS inside a set, at most the budget per set, time ordered.
        #expect(compiled.locations.count < raw.locations.count)
        for set in derived.stats.sets {
            let inSet = SetLocationFilter.samples(in: compiled.locations, from: set.startedAt, to: set.endedAt)
            #expect(inSet.count <= ExampleSessionCompiler.setPointBudget)
        }
        #expect(compiled.locations.map(\.timestamp) == compiled.locations.map(\.timestamp).sorted())
    }

    @Test func compiledLoadMatchesAnalyzingTheRawExport() throws {
        let raw = try rawPackage()
        let compiled = try roundTrip(ExampleSessionCompiler.compile(raw))
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let analyzed = try SessionLoader.loadExample(package: raw, now: now)
        let precompiled = try SessionLoader.loadExample(package: compiled, now: now)

        #expect(precompiled.stats == analyzed.stats)
        #expect(precompiled.manifest == analyzed.manifest)
        #expect(precompiled.detections == analyzed.detections)
        #expect(precompiled.manifest.endedAt == now)
        #expect(precompiled.stats.endedAt == now)
        #expect(precompiled.locations.count < analyzed.locations.count)
    }

    @Test func staleDerivedIsAnalyzedFromTheRawStreams() throws {
        var raw = try rawPackage()
        let marker = SessionStats(
            startedAt: raw.manifest.startedAt,
            endedAt: raw.manifest.startedAt,
            totalDuration: 0,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            setCount: 99,
            ridingDuration: 0,
            inactiveDuration: 0,
            ridingInactiveRatio: 0,
            sets: []
        )
        raw.derived = DerivedSessionView(analyzerVersion: SessionAnalyzer.version + 1, stats: marker)

        let bundle = try SessionLoader.loadExample(package: raw, now: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(bundle.stats.setCount != 99)
        #expect(bundle.stats.sets.count > 1)
    }

    @Test func preloadShiftsEachLoadToItsOwnNow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExampleSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("example.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ExampleSessionCompiler.compile(rawPackage())).write(to: url)

        let preload = ExampleSessionPreload(packageURL: url)
        let first = try await preload.load(now: Date(timeIntervalSince1970: 2_000_000_000))
        let later = try await preload.load(now: Date(timeIntervalSince1970: 2_000_003_600))

        #expect(first.manifest.endedAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(later.manifest.endedAt == Date(timeIntervalSince1970: 2_000_003_600))
        #expect(later.stats.sets.map(\.duration) == first.stats.sets.map(\.duration))
        #expect(later.stats.startedAt.timeIntervalSince(first.stats.startedAt) == 3_600)
    }

    @Test func preloadWithoutBundledFileThrows() async {
        let preload = ExampleSessionPreload(packageURL: nil)
        await #expect(throws: SessionStoreError.self) {
            _ = try await preload.load()
        }
    }

    // MARK: - Bundled assets

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RpplCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RpplCore
            .deletingLastPathComponent() // repo root
    }

    private static func bundledData(_ target: String) throws -> Data {
        let url = repoRoot
            .appendingPathComponent("\(target)/Resources/Exports/\(ExampleSessionPreload.resourceName).json")
        return try Data(contentsOf: url)
    }

    @Test func bundledExampleIsCompiledForTheCurrentAnalyzer() throws {
        let package = try SessionImportLimits.decodeTransferPackage(from: Self.bundledData("Rppl"))
        let derived = try #require(
            package.derived,
            "Bundled example is not compiled. Run scripts/prepare-example-session.sh"
        )

        #expect(
            derived.isCurrentAnalyzer,
            "SessionAnalyzer.version changed. Re-run scripts/prepare-example-session.sh"
        )
        #expect(package.manifest.activityCode == "Example session")
        #expect(!derived.stats.sets.isEmpty)
        #expect(package.locations.count <= ExampleSessionCompiler.setPointBudget * derived.stats.sets.count)
        #expect(package.health.isEmpty)
        #expect(package.motionFramesZlib == nil)
    }

    @Test func watchBundlesTheSameExampleAsThePhone() throws {
        #expect(try Self.bundledData("RpplWatch") == Self.bundledData("Rppl"))
    }
}
