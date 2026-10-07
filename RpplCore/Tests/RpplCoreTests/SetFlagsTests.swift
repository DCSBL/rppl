import Foundation
import Testing
@testable import RpplCore

@Suite("Set flags", .serialized)
struct SetFlagsTests {
    @Test func kindsGroupPresetsAndTreatUnknownAsCustom() {
        #expect(SetFlags.kind(of: "clean_start") == .start)
        #expect(SetFlags.kind(of: "clean_exit") == .exit)
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

    @Test func startAndExitAllowOnlyOneEachWhileTricksStack() {
        var flags = SetFlags.toggling("clean_start", in: [])
        flags = SetFlags.toggling("sit_start", in: flags)
        #expect(flags == ["sit_start"])
        flags = SetFlags.toggling("wipeout", in: flags)
        flags = SetFlags.toggling("dry_exit", in: flags)
        flags = SetFlags.toggling("rail", in: flags)
        flags = SetFlags.toggling("backroll", in: flags)
        #expect(flags == ["sit_start", "dry_exit", "backroll", "rail"])
        flags = SetFlags.toggling("sit_start", in: flags)
        #expect(flags == ["dry_exit", "backroll", "rail"])
    }

    @Test func catchAllSortsLastAndCableStoppedIsAnExit() {
        let ordered = SetFlags.ordered(["other_start", "slide_start", "clean_start", "tantrum"])
        #expect(ordered == ["clean_start", "slide_start", "other_start", "tantrum"])
        #expect(SetFlags.kind(of: "cable_stopped") == .exit)
        let flags = SetFlags.toggling("cable_stopped", in: ["dry_exit"])
        #expect(flags == ["cable_stopped"])
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

    @Test func removeEverywhereTakesLabelOffAllSets() {
        var draft = SetFlagDraft(saved: ["1": ["Tail grab", "rail"], "2": ["tail grab"], "3": ["wipeout"]])
        #expect(draft.isUsed("Tail grab"))
        draft.removeEverywhere("Tail grab")
        #expect(!draft.isUsed("Tail grab"))
        #expect(draft.result == ["1": ["rail"], "3": ["wipeout"]])
        #expect(draft.isDirty)
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

    @Test func trimmedKeepsOnlySetsWithinCount() {
        let flags = ["1": ["wipeout"], "3": ["new_trick"], "4": ["rail"], "2": []]
        #expect(SetFlags.trimmed(flags, toSetCount: 3) == ["1": ["wipeout"], "3": ["new_trick"]])
        #expect(SetFlags.trimmed(flags, toSetCount: 0).isEmpty)
    }
}
