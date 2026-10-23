import Foundation
import Testing
@testable import RpplCore

private actor FakeFetcher: ParkDataFetching {
    var files: [String: Data]
    private(set) var requested: [String] = []

    init(files: [String: Data]) { self.files = files }

    func fetch(_ path: String, maxBytes: Int) async throws -> Data {
        requested.append(path)
        guard let data = files[path] else { throw ParkDataError.fetchFailed("404 \(path)") }
        return data
    }

    func set(_ path: String, _ data: Data) { files[path] = data }
}

struct ParkDataTests {
    private func yaml(id: String, name: String = "Park", updated: String = "2026-10-20") -> Data {
        Data("""
        version: 1
        id: \(id)
        updated_at: \(updated)
        name: \(name)
        location:
          lat: 52.0
          lon: 5.0
        """.utf8)
    }

    private func makeManifest(
        version: Int, parks: [(String, Data)], enabled: Bool = true, minSchema: Int = 1, maxSchema: Int = 1
    ) -> ParkDataManifest {
        ParkDataManifest(
            dataVersion: version,
            publishedAt: "2026-10-22T12:41:00Z",
            enabled: enabled,
            minAppSchema: minSchema,
            maxAppSchema: maxSchema,
            parks: parks.map { .init(id: $0.0, file: "\($0.0).yaml", sha256: ParkDataHash.sha256Hex($0.1)) }
        )
    }

    private func tempStore() -> ParkDataStore {
        ParkDataStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("park-data-\(UUID().uuidString)", isDirectory: true))
    }

    private func fetcher(_ manifest: ParkDataManifest, _ parks: [(String, Data)]) throws -> FakeFetcher {
        var files = ["manifest.json": try JSONEncoder().encode(manifest)]
        for (id, data) in parks { files["\(id).yaml"] = data }
        return FakeFetcher(files: files)
    }

    // MARK: hash

    @Test func sha256KnownVectors() {
        #expect(ParkDataHash.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(ParkDataHash.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        #expect(ParkDataHash.sha256Hex(long) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    // MARK: manifest validation

    @Test func validManifestPasses() throws {
        let a = yaml(id: "a")
        let manifest = makeManifest(version: 1, parks: [("a", a)])
        let parks = try manifest.validate(files: ["a.yaml": a])
        #expect(parks.map(\.id) == ["a"])
    }

    @Test func hashMismatchIsRejected() {
        let manifest = makeManifest(version: 1, parks: [("a", yaml(id: "a"))])
        #expect(throws: ParkDataError.hashMismatch("a.yaml")) {
            try manifest.validate(files: ["a.yaml": yaml(id: "a", name: "Tampered")])
        }
    }

    @Test func missingFileIsRejected() {
        let manifest = makeManifest(version: 1, parks: [("a", yaml(id: "a"))])
        #expect(throws: ParkDataError.missingFile("a.yaml")) { try manifest.validate(files: [:]) }
    }

    @Test func idMismatchBetweenFileAndManifestIsRejected() {
        let wrong = yaml(id: "b")
        let manifest = makeManifest(version: 1, parks: [("a", wrong)])
        #expect(throws: ParkDataError.self) { try manifest.validate(files: ["a.yaml": wrong]) }
    }

    @Test func invalidYAMLIsRejected() {
        let junk = Data("not: [valid".utf8)
        let manifest = makeManifest(version: 1, parks: [("a", junk)])
        #expect(throws: ParkDataError.self) { try manifest.validate(files: ["a.yaml": junk]) }
    }

    @Test func pathTraversalAndDuplicatesAreRejected() {
        var manifest = makeManifest(version: 1, parks: [("a", yaml(id: "a"))])
        manifest.parks[0].id = "../evil"
        manifest.parks[0].file = "../evil.yaml"
        #expect(throws: ParkDataError.self) { try manifest.validateHeader() }

        let a = yaml(id: "a")
        let dup = makeManifest(version: 1, parks: [("a", a), ("a", a)])
        #expect(throws: ParkDataError.self) { try dup.validateHeader() }
    }

    @Test func schemaRangeIsChecked() {
        let tooNew = makeManifest(version: 1, parks: [], minSchema: Park.currentVersion + 1, maxSchema: Park.currentVersion + 1)
        #expect(throws: ParkDataError.appUpdateRequired(minSchema: Park.currentVersion + 1)) {
            try tooNew.validateHeader()
        }
        let tooOld = makeManifest(version: 1, parks: [], minSchema: 1, maxSchema: 1)
        #expect(throws: ParkDataError.schemaOutOfRange) { try tooOld.validateHeader(appSchema: 2) }
    }

    @Test func unknownFormatIsRejected() {
        var manifest = makeManifest(version: 1, parks: [])
        manifest.format = 99
        #expect(throws: ParkDataError.unsupportedFormat(99)) { try manifest.validateHeader() }
    }

    // MARK: store

    @Test func installSwitchesPointerAndRemovesOldVersions() throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a1 = yaml(id: "a", name: "One")
        try store.install(manifest: makeManifest(version: 1, parks: [("a", a1)]), files: ["a.yaml": a1])
        #expect(store.pointer()?.dataVersion == 1)

        let a2 = yaml(id: "a", name: "Two")
        try store.install(manifest: makeManifest(version: 2, parks: [("a", a2)]), files: ["a.yaml": a2])
        #expect(store.pointer()?.dataVersion == 2)
        #expect(store.installedFile("a.yaml") == a2)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.root.path)) ?? []
        #expect(names.sorted() == ["current.json", "v2"])
    }

    @Test func failedInstallKeepsCurrentData() throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a1 = yaml(id: "a", name: "One")
        try store.install(manifest: makeManifest(version: 1, parks: [("a", a1)]), files: ["a.yaml": a1])

        let bad = makeManifest(version: 2, parks: [("a", yaml(id: "a", name: "Two"))])
        #expect(throws: ParkDataError.self) { try store.install(manifest: bad, files: ["a.yaml": Data("garbage".utf8)]) }
        #expect(store.pointer()?.dataVersion == 1)
        #expect(store.installedFile("a.yaml") == a1)
    }

    @Test func killSwitchHidesActiveDirectoryButKeepsFiles() throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a")
        try store.install(manifest: makeManifest(version: 1, parks: [("a", a)]), files: ["a.yaml": a])
        #expect(store.activeDirectory() != nil)
        try store.setEnabled(false)
        #expect(store.activeDirectory() == nil)
        #expect(store.installedDirectory() != nil)
        try store.setEnabled(true)
        #expect(store.activeDirectory() != nil)
    }

    // MARK: updater

    @Test func updaterInstallsThenReportsUpToDate() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a")
        let manifest = makeManifest(version: 3, parks: [("a", a)])
        let fake = try fetcher(manifest, [("a", a)])
        let updater = ParkDataUpdater(store: store)

        #expect(try await updater.update(using: fake) == .updated(dataVersion: 3))
        #expect(try await updater.update(using: fake) == .alreadyCurrent(dataVersion: 3))
        #expect(await fake.requested.filter { $0 == "a.yaml" }.count == 1)
    }

    @Test func updaterOnlyDownloadsChangedFiles() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a"), b1 = yaml(id: "b", name: "B1"), b2 = yaml(id: "b", name: "B2")
        let updater = ParkDataUpdater(store: store)
        _ = try await updater.update(using: fetcher(makeManifest(version: 1, parks: [("a", a), ("b", b1)]), [("a", a), ("b", b1)]))

        let second = try fetcher(makeManifest(version: 2, parks: [("a", a), ("b", b2)]), [("a", a), ("b", b2)])
        #expect(try await updater.update(using: second) == .updated(dataVersion: 2))
        let requested = await second.requested
        #expect(requested.contains("b.yaml"))
        #expect(!requested.contains("a.yaml"))
        #expect(store.installedFile("b.yaml") == b2)
    }

    @Test func updaterRollsBackWhenVersionGoesDown() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a")
        let updater = ParkDataUpdater(store: store)
        _ = try await updater.update(using: fetcher(makeManifest(version: 5, parks: [("a", a)]), [("a", a)]))
        let outcome = try await updater.update(using: fetcher(makeManifest(version: 4, parks: [("a", a)]), [("a", a)]))
        #expect(outcome == .updated(dataVersion: 4))
        #expect(store.pointer()?.dataVersion == 4)
    }

    @Test func updaterHonoursKillSwitchAndReEnables() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a")
        let updater = ParkDataUpdater(store: store)
        _ = try await updater.update(using: fetcher(makeManifest(version: 1, parks: [("a", a)]), [("a", a)]))

        let off = try fetcher(makeManifest(version: 1, parks: [("a", a)], enabled: false), [("a", a)])
        #expect(try await updater.update(using: off) == .disabled)
        #expect(store.activeDirectory() == nil)

        let on = try fetcher(makeManifest(version: 1, parks: [("a", a)]), [("a", a)])
        #expect(try await updater.update(using: on) == .alreadyCurrent(dataVersion: 1))
        #expect(store.activeDirectory() != nil)
    }

    @Test func updaterReportsAppUpdateRequired() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let manifest = makeManifest(version: 1, parks: [], minSchema: 99, maxSchema: 99)
        #expect(try await ParkDataUpdater(store: store).update(using: fetcher(manifest, [])) == .appUpdateRequired)
        #expect(store.pointer() == nil)
    }

    @Test func updaterFailureLeavesInstalledDataAlone() async throws {
        let store = tempStore()
        defer { store.removeAll() }
        let a = yaml(id: "a")
        let updater = ParkDataUpdater(store: store)
        _ = try await updater.update(using: fetcher(makeManifest(version: 1, parks: [("a", a)]), [("a", a)]))

        let b = yaml(id: "b")
        let broken = try fetcher(makeManifest(version: 2, parks: [("a", a), ("b", b)]), [("a", a)]) // b.yaml 404
        await #expect(throws: ParkDataError.self) { try await updater.update(using: broken) }
        #expect(store.pointer()?.dataVersion == 1)
    }

    // MARK: catalog layering

    @Test func catalogLayersBundledOtaAndUserFiles() throws {
        let bundled = try #require(ParkCatalog.loadBundled().first)
        let ota = tempStore()
        let userRoot = FileManager.default.temporaryDirectory.appendingPathComponent("park-user-\(UUID().uuidString)")
        defer { ota.removeAll(); try? FileManager.default.removeItem(at: userRoot) }

        let renamed = yaml(id: bundled.id, name: "OTA Name", updated: "2999-01-01")
        let added = yaml(id: "ota-only-park", name: "New Park")
        try ota.install(
            manifest: makeManifest(version: 1, parks: [(bundled.id, renamed), ("ota-only-park", added)]),
            files: ["\(bundled.id).yaml": renamed, "ota-only-park.yaml": added]
        )
        let dir = try #require(ota.activeDirectory())

        let entries = Dictionary(uniqueKeysWithValues: ParkCatalog.loadWithOrigin(userRoot: nil, otaDirectory: dir).map { ($0.id, $0) })
        #expect(entries[bundled.id]?.park.name == "OTA Name")
        #expect(entries[bundled.id]?.origin == .ota)
        #expect(entries["ota-only-park"]?.origin == .ota)

        // A user edit wins over OTA and flags a newer base.
        var mine = try #require(entries[bundled.id]?.park)
        mine.name = "My Name"
        try ParkCatalog.save(mine, to: userRoot, bundledBase: entries[bundled.id]?.park)
        let withUser = ParkCatalog.loadWithOrigin(userRoot: userRoot, otaDirectory: dir).first { $0.id == bundled.id }
        #expect(withUser?.park.name == "My Name")
        #expect(withUser?.origin == .edited)
        #expect(withUser?.hasNewerBundled == false)
        #expect(ParkCatalog.load(userRoot: userRoot, otaDirectory: dir).first { $0.id == bundled.id }?.name == "My Name")
    }

    @Test func newerBundledDataBeatsOlderOta() throws {
        let bundled = try #require(ParkCatalog.loadBundled().first { $0.updatedAt != nil })
        let ota = tempStore()
        defer { ota.removeAll() }
        let stale = yaml(id: bundled.id, name: "Stale OTA", updated: "2000-01-01")
        try ota.install(manifest: makeManifest(version: 1, parks: [(bundled.id, stale)]), files: ["\(bundled.id).yaml": stale])
        let loaded = ParkCatalog.load(userRoot: nil, otaDirectory: ota.activeDirectory()).first { $0.id == bundled.id }
        #expect(loaded?.name == bundled.name)
    }

    @Test func permanentlyClosedParkIsKeptButNotListed() throws {
        let text = """
        version: 1
        id: gone
        name: Gone
        permanently_closed: true
        location:
          lat: 52.0
          lon: 5.0
        """
        let park = try ParkCatalog.parse(yaml: text, fallbackId: "gone")
        #expect(park.permanentlyClosed == true)
        #expect(!park.isListed)
        #expect(Park(id: "x", name: "X", location: park.location).isListed)
    }
}
