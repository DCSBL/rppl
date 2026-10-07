import Foundation
import Testing
@testable import RpplCore

@Suite("Set flags", .serialized)
struct SetFlagsTests {
    @Test func kindsGroupPresetsAndTreatUnknownAsCustom() {
        #expect(SetFlags.kind(of: "clean_exit") == .startFinish)
        #expect(SetFlags.kind(of: "new_trick") == .trick)
        #expect(SetFlags.kind(of: "Switch raley") == .custom)
        #expect(SetFlags.kind(of: "future_code") == .custom)
    }

    @Test func normalizedTrimsCapsAndMapsPresetSpelling() {
        #expect(SetFlags.normalized(custom: "  Tail   grab ") == "Tail grab")
        #expect(SetFlags.normalized(custom: "   ") == nil)
        #expect(SetFlags.normalized(custom: "Clean Start") == "clean_start")
        #expect(SetFlags.normalized(custom: String(repeating: "a", count: 60))?.count == SetFlags.maxLength)
    }

    @Test func togglingAddsRemovesAndOrdersByKind() {
        var flags = SetFlags.toggling("new_trick", in: [])
        flags = SetFlags.toggling("Tail grab", in: flags)
        flags = SetFlags.toggling("clean_exit", in: flags)
        #expect(flags == ["clean_exit", "new_trick", "Tail grab"])
        flags = SetFlags.toggling("NEW_TRICK", in: flags)
        #expect(flags == ["clean_exit", "Tail grab"])
    }

    @Test func draftIsDirtyOnlyWhenDifferentAndTogglingBackIsClean() {
        var draft = SetFlagDraft(saved: ["1": ["clean_exit"]])
        #expect(!draft.isDirty)
        draft.toggle("new_trick", forSet: 2)
        #expect(draft.isDirty)
        #expect(draft.flags(forSet: 2) == ["new_trick"])
        draft.toggle("new_trick", forSet: 2)
        #expect(!draft.isDirty)
        draft.toggle("clean_exit", forSet: 1)
        #expect(draft.result.isEmpty)
        draft.discard()
        #expect(draft.flags(forSet: 1) == ["clean_exit"])
    }

    @Test func draftRestoresOverFreshSavedFlags() {
        let draft = SetFlagDraft(saved: ["1": ["wipeout"]], draft: ["1": ["wipeout", "new_trick"], "2": []])
        #expect(draft.isDirty)
        #expect(draft.flags(forSet: 1) == ["wipeout", "new_trick"])
        #expect(!SetFlagDraft(saved: ["1": ["wipeout"]], draft: ["1": ["wipeout"]]).isDirty)
    }

    @Test func draftSurvivesCodableRoundTrip() throws {
        var draft = SetFlagDraft(saved: nil)
        draft.toggle("Tail grab", forSet: 3)
        let data = try JSONEncoder().encode(draft)
        let back = try JSONDecoder().decode(SetFlagDraft.self, from: data)
        #expect(back == draft)
        #expect(back.isDirty)
    }

    @Test func storePersistsFlagsAndUnknownCodesRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t", appVersion: "1", buildNumber: "1", watchModel: "W", systemVersion: "26"
        )
        _ = try store.createSession(manifest: manifest)
        try store.setSetFlags(["1": ["clean_exit", "mystery_code"], "2": []], sessionId: manifest.sessionId)
        #expect(try store.readManifest(sessionId: manifest.sessionId).setFlags == ["1": ["clean_exit", "mystery_code"]])
        try store.setSetFlags([:], sessionId: manifest.sessionId)
        #expect(try store.readManifest(sessionId: manifest.sessionId).setFlags == nil)
    }

    @Test func manualEntryFlagsRoundTrip() throws {
        let entry = ManualEntry(flags: ["new_trick"])
        let back = try JSONDecoder().decode(ManualEntry.self, from: JSONEncoder().encode(entry))
        #expect(back.flags == ["new_trick"])
        #expect(ManualEntry().flags == nil)
    }
}
