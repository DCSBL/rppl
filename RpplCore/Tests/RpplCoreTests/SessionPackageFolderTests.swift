import Foundation
import Testing
@testable import RpplCore

@Suite("SessionPackageNaming")
struct SessionPackageNamingTests {
    @Test func baseFolderNameUsesLocalDateTimeAndCity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1, hour: 14, minute: 32)
        )!
        let name = SessionPackageNaming.baseFolderName(
            startedAt: date,
            cityName: "Rotterdam",
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        #expect(name == "2026-06-01 14-32 - Rotterdam")
    }

    @Test func emptyCityBecomesUnknown() {
        #expect(SessionPackageNaming.displayCity(nil) == "Unknown")
        #expect(SessionPackageNaming.displayCity("  ") == "Unknown")
        #expect(SessionPackageNaming.displayCity("New/York") == "New York")
    }

    @Test func uniqueFolderNameAddsSuffixOnCollision() {
        let existing: Set<String> = [
            "2026-06-01 14-32 - Rotterdam",
            "2026-06-01 14-32 - Rotterdam (2)",
        ]
        #expect(
            SessionPackageNaming.uniqueFolderName(
                base: "2026-06-01 14-32 - Rotterdam",
                existingNames: existing
            ) == "2026-06-01 14-32 - Rotterdam (3)"
        )
    }

    @Test func appGeneratedPatterns() {
        #expect(SessionPackageNaming.isAppGenerated("2026-06-01 14-32 - Rotterdam"))
        #expect(SessionPackageNaming.isAppGenerated("2026-06-01 14-32 - Rotterdam (2)"))
        #expect(SessionPackageNaming.isAppGenerated("2026-06-01 - Rotterdam")) // date-only legacy
        #expect(SessionPackageNaming.isAppGenerated(UUID().uuidString))
        #expect(!SessionPackageNaming.isAppGenerated("My park day"))
    }
}

@Suite("SessionPackageFolders", .serialized)
struct SessionPackageFolderTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-folders-\(UUID().uuidString)", isDirectory: true)
    }

    private func emptyStats(startedAt: Date, duration: TimeInterval) -> SessionStats {
        SessionStats(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            totalDuration: duration,
            totalDistanceMeters: 0,
            activeEnergyKilocalories: nil,
            setCount: 0,
            ridingDuration: 0,
            inactiveDuration: duration,
            ridingInactiveRatio: 0,
            sets: []
        )
    }

    @Test func createSessionUsesHumanReadableFolderWithoutUUID() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let started = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "11111111-1111-1111-1111-111111111111",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Watch7,1",
            systemVersion: "26.0",
            startedAt: started
        )
        let dir = try store.createSession(manifest: manifest)
        let expected = SessionPackageNaming.baseFolderName(
            startedAt: started,
            cityName: nil
        )
        #expect(dir.lastPathComponent == expected)
        #expect(dir.lastPathComponent != manifest.sessionId)
        #expect(try store.listSessionIDs() == [manifest.sessionId])
        #expect(
            try store.sessionDirectory(for: manifest.sessionId).resolvingSymlinksInPath()
                == dir.resolvingSymlinksInPath()
        )
    }

    @Test func sameMinuteCollisionGetsNumericSuffix() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let started = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let store = SessionFileStore(rootURL: root)

        let first = SessionManifest(
            sessionId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: started
        )
        let second = SessionManifest(
            sessionId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: started
        )
        let dir1 = try store.createSession(manifest: first)
        let dir2 = try store.createSession(manifest: second)
        let base = SessionPackageNaming.baseFolderName(startedAt: started, cityName: nil)
        #expect(dir1.lastPathComponent == base)
        #expect(dir2.lastPathComponent == "\(base) (2)")
    }

    @Test func differentStartMinutesGetDistinctFolders() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 0)
        )!
        let afternoon = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1, hour: 15, minute: 30)
        )!
        let store = SessionFileStore(rootURL: root)

        let first = SessionManifest(
            sessionId: "12121212-1212-1212-1212-121212121212",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: morning
        )
        let second = SessionManifest(
            sessionId: "34343434-3434-3434-3434-343434343434",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: afternoon
        )
        let dir1 = try store.createSession(manifest: first)
        let dir2 = try store.createSession(manifest: second)
        #expect(dir1.lastPathComponent == SessionPackageNaming.baseFolderName(startedAt: morning, cityName: nil))
        #expect(dir2.lastPathComponent == SessionPackageNaming.baseFolderName(startedAt: afternoon, cityName: nil))
        #expect(!dir2.lastPathComponent.contains(" (2)"))
    }

    @Test func cityUpdateRenamesAppGeneratedFolder() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let started = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10))!
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: started
        )
        _ = try store.createSession(manifest: manifest)
        try store.writeDerivedView(
            DerivedSessionView(stats: emptyStats(startedAt: started, duration: 60)),
            sessionId: manifest.sessionId
        )
        try store.updateDerivedCityName("Rotterdam", sessionId: manifest.sessionId)
        let dir = try store.sessionDirectory(for: manifest.sessionId)
        let expected = SessionPackageNaming.baseFolderName(
            startedAt: started,
            cityName: "Rotterdam"
        )
        #expect(dir.lastPathComponent == expected)
    }

    @Test func userRenamedFolderIsPreservedOnCityUpdate() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            sessionId: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0"
        )
        let created = try store.createSession(manifest: manifest)
        let custom = root.appendingPathComponent("My park day", isDirectory: true)
        try FileManager.default.moveItem(at: created, to: custom)

        let store2 = SessionFileStore(rootURL: root)
        try store2.writeDerivedView(
            DerivedSessionView(
                stats: emptyStats(startedAt: manifest.startedAt, duration: 30),
                cityName: "Unknown"
            ),
            sessionId: manifest.sessionId
        )
        try store2.updateDerivedCityName("Rotterdam", sessionId: manifest.sessionId)
        let dir = try store2.sessionDirectory(for: manifest.sessionId)
        #expect(dir.lastPathComponent == "My park day")
        #expect(try store2.listSessionIDs() == [manifest.sessionId])
    }

    @Test func migratesLegacyBareUUIDFolder() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let started = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 9))!
        let sessionId = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        let legacy = root.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let manifest = SessionManifest(
            sessionId: sessionId,
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "W",
            systemVersion: "26.0",
            startedAt: started
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: legacy.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let derivedDir = legacy.appendingPathComponent("derived", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
        let view = DerivedSessionView(
            stats: emptyStats(startedAt: started, duration: 120),
            cityName: "Utrecht"
        )
        try encoder.encode(view).write(
            to: derivedDir.appendingPathComponent("view.json"),
            options: [.atomic]
        )

        let store = SessionFileStore(rootURL: root)
        let migrated = try store.migratePackageFolderNamesIfNeeded()
        #expect(migrated == [sessionId])
        let dir = try store.sessionDirectory(for: sessionId)
        let expected = SessionPackageNaming.baseFolderName(
            startedAt: started,
            cityName: "Utrecht"
        )
        #expect(dir.lastPathComponent == expected)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }
}
