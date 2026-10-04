import Foundation
import Testing
@testable import RpplCore

/// Motion is stored as length-prefixed zlib frames. A kill or a full disk in the middle of an
/// append leaves a partial frame at the tail. Like a torn JSONL line, it may cost only itself:
/// before this, the phone import failed with `truncatedFrame` (the session never synced) and
/// every frame appended after it was unreadable.
@Suite("Torn motion frames", .serialized)
struct TornMotionFrameTests {
    private let motionFile = "motion-000.jsonl.zlib"

    private func frame(seconds: Range<Int>) throws -> Data {
        var jsonl = Data()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for second in seconds {
            jsonl.append(try encoder.encode(Samples.motion(second)))
            jsonl.append(0x0A)
        }
        return try CompressedJSONLFrames.makeFrame(jsonlUTF8: jsonl)
    }

    private func writeRaw(_ data: Data, session: TempSession) throws {
        try data.write(to: session.file(motionFile))
    }

    private func motionSeconds(_ session: TempSession) throws -> [Date] {
        try session.store.readMotionSamples(sessionId: session.sessionId).map(\.timestamp)
    }

    // MARK: validPrefixLength

    @Test func prefixOfIntactFramesIsTheWholeFile() throws {
        let data = try frame(seconds: 0..<5) + frame(seconds: 5..<10)
        #expect(CompressedJSONLFrames.validPrefixLength(data) == data.count)
    }

    @Test func emptyDataHasNoPrefix() {
        #expect(CompressedJSONLFrames.validPrefixLength(Data()) == 0)
    }

    @Test(arguments: [1, 3, 4, 5, 20])
    func aFrameCutAnywhereIsDropped(keepBytes: Int) throws {
        let good = try frame(seconds: 0..<5)
        let torn = try frame(seconds: 5..<10).prefix(keepBytes)
        #expect(CompressedJSONLFrames.validPrefixLength(good + torn) == good.count)
    }

    @Test func aFrameThatDoesNotInflateEndsThePrefix() throws {
        let good = try frame(seconds: 0..<5)
        var bad = Data([0x00, 0x00, 0x00, 0x04, 0xDE, 0xAD, 0xBE, 0xEF])
        bad.append(try frame(seconds: 5..<10))
        #expect(CompressedJSONLFrames.validPrefixLength(good + bad) == good.count)
    }

    @Test func absurdLengthEndsThePrefixInsteadOfReadingPastTheFile() throws {
        let good = try frame(seconds: 0..<5)
        let huge = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02])
        #expect(CompressedJSONLFrames.validPrefixLength(good + huge) == good.count)
        let zero = Data([0x00, 0x00, 0x00, 0x00])
        #expect(CompressedJSONLFrames.validPrefixLength(good + zero) == good.count)
    }

    // MARK: append

    @Test func appendAfterTornFrameKeepsEveryLaterFrameReadable() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        // A torn tail much longer than the frames appended after it, so leftover bytes would show.
        let torn = try frame(seconds: 5..<400).prefix(1_000)
        try writeRaw(frame(seconds: 0..<5) + torn, session: session)

        try session.store.appendMotionSamples([Samples.motion(10)], sessionId: session.sessionId)
        try session.store.appendMotionSamples([Samples.motion(11)], sessionId: session.sessionId)

        // The torn frame is gone; nothing else is, and no stray bytes remain on disk.
        #expect(try motionSeconds(session) == (0..<5).map { Samples.time($0) } + [Samples.time(10), Samples.time(11)])
        let onDisk = try Data(contentsOf: session.file(motionFile))
        #expect(CompressedJSONLFrames.validPrefixLength(onDisk) == onDisk.count)
    }

    @Test func appendToIntactFileLeavesExistingBytesUntouched() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let existing = try frame(seconds: 0..<5)
        try writeRaw(existing, session: session)

        try session.store.appendMotionSamples((5..<10).map { Samples.motion($0) }, sessionId: session.sessionId)

        let after = try Data(contentsOf: session.file(motionFile))
        #expect(after.prefix(existing.count) == existing)
        #expect(try motionSeconds(session).count == 10)
    }

    // MARK: read + transfer

    @Test func readingATornFileReturnsTheIntactFrames() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        try writeRaw(frame(seconds: 0..<5) + frame(seconds: 5..<10).prefix(9), session: session)

        #expect(try motionSeconds(session) == (0..<5).map { Samples.time($0) })
        let shipped = try #require(try session.store.readMotionFrameData(sessionId: session.sessionId))
        // What goes over the wire must pass the phone's strict check.
        #expect(throws: Never.self) { try CompressedJSONLFrames.decodeFrames(shipped) }
    }

    @Test func aFileWithNoIntactFrameShipsNoMotion() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        try writeRaw(frame(seconds: 0..<5).prefix(6), session: session)

        #expect(try session.store.readMotionFrameData(sessionId: session.sessionId) == nil)
        #expect(try motionSeconds(session).isEmpty)
    }

    @Test func aTornMotionTailDoesNotStopTheSessionSyncing() throws {
        let session = try TempSession.make(state: .readyToTransfer)
        let phoneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RpplCoreTests-phone-\(UUID().uuidString)", isDirectory: true)
        defer { session.cleanup(); try? FileManager.default.removeItem(at: phoneRoot) }
        let id = session.sessionId
        try session.store.appendLocationSamples([Samples.location(0)], sessionId: id)
        try writeRaw(frame(seconds: 0..<5) + frame(seconds: 5..<10).prefix(13), session: session)

        let package = try session.store.buildTransferPackage(sessionId: id)
        try session.store.importTransferPackage(package, intoPhoneStore: phoneRoot)

        let phone = SessionFileStore(rootURL: phoneRoot)
        #expect(try phone.readMotionSamples(sessionId: id).count == 5)
        #expect(try phone.readLocationSamples(sessionId: id).count == 1)
    }

    @Test func theImportKeepsTheIntactFramesOfADamagedFile() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let good = try frame(seconds: 0..<5)
        let torn = try frame(seconds: 5..<10).prefix(9)

        let dropped = try session.store.writeMotionFrameData(good + torn, sessionId: session.sessionId)

        #expect(dropped == 9)
        #expect(try motionSeconds(session) == (0..<5).map { Samples.time($0) })
    }

    @Test func theImportStoresNothingWhenNoFrameIsUsable() throws {
        let session = try TempSession.make()
        defer { session.cleanup() }
        let torn = try frame(seconds: 0..<5).prefix(9)

        let dropped = try session.store.writeMotionFrameData(torn, sessionId: session.sessionId)

        #expect(dropped == 9)
        #expect(try session.store.readMotionFrameData(sessionId: session.sessionId) == nil)
    }
}
