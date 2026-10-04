import Foundation
import Testing
@testable import RpplCore

@Suite("CompressedJSONLFrames")
struct CompressedJSONLFramesTests {
    @Test func roundTripSingleFrame() throws {
        // Small payloads can expand under zlib overhead; use enough bytes to shrink.
        let line = #"{"a":1,"b":"repeated-text-repeated-text-repeated-text"}"# + "\n"
        let payload = Data(String(repeating: line, count: 40).utf8)
        let frame = try CompressedJSONLFrames.makeFrame(jsonlUTF8: payload)
        let decoded = try CompressedJSONLFrames.decodeFrames(frame)
        #expect(decoded == payload)
        #expect(frame.count < payload.count)
    }

    /// Frames are raw DEFLATE (RFC 1951, no zlib header): what Apple's `COMPRESSION_ZLIB` writes and
    /// what the Linux zlib fallback must read. A fixed vector keeps both platforms byte-compatible.
    @Test func decodesKnownRawDeflateFrame() throws {
        let rawDeflateHello: [UInt8] = [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00]
        let frame = Data([0x00, 0x00, 0x00, UInt8(rawDeflateHello.count)] + rawDeflateHello)
        #expect(String(data: try CompressedJSONLFrames.decodeFrames(frame), encoding: .utf8) == "hello")
    }

    @Test func concatenatesMultipleFrames() throws {
        let first = try CompressedJSONLFrames.makeFrame(jsonlUTF8: Data("line1\n".utf8))
        let second = try CompressedJSONLFrames.makeFrame(jsonlUTF8: Data("line2\n".utf8))
        var combined = first
        combined.append(second)
        let decoded = try CompressedJSONLFrames.decodeFrames(combined)
        #expect(String(data: decoded, encoding: .utf8) == "line1\nline2\n")
    }

    @Test func rejectsTruncatedFrame() {
        #expect(throws: CompressedJSONLFrameError.truncatedFrame) {
            try CompressedJSONLFrames.decodeFrames(Data([0x00, 0x00, 0x00, 0x10, 0x01]))
        }
    }

    @Test func rejectsOversizedLengthHeader() {
        var frame = Data([0x00, 0x10, 0x00, 0x01]) // claims 1 MiB + 1 compressed
        frame.append(Data(repeating: 0x00, count: 16))
        #expect(throws: CompressedJSONLFrameError.frameTooLarge) {
            try CompressedJSONLFrames.decodeFrames(frame)
        }
    }

    @Test func rejectsTooManyFrames() throws {
        let single = try CompressedJSONLFrames.makeFrame(jsonlUTF8: Data("x\n".utf8))
        var many = Data()
        for _ in 0..<(CompressedJSONLFrames.maxFrameCount + 1) {
            many.append(single)
        }
        #expect(throws: CompressedJSONLFrameError.tooManyFrames) {
            try CompressedJSONLFrames.decodeFrames(many)
        }
    }
}

@Suite("MotionCompression")
struct MotionCompressionTests {
    @Test func appendMotionWritesZlibAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionFileStore(rootURL: root)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try store.createSession(manifest: manifest)

        let samples = (0..<50).map { i in
            MotionSample(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                userAccelX: Double(i) * 0.01,
                userAccelY: 0.2,
                userAccelZ: 0.3,
                rotationX: 1,
                rotationY: 2,
                rotationZ: 3,
                pitch: 0.4,
                roll: 0.5,
                yaw: 0.6
            )
        }
        try store.appendMotionSamples(Array(samples.prefix(25)), sessionId: manifest.sessionId)
        try store.appendMotionSamples(Array(samples.suffix(25)), sessionId: manifest.sessionId)

        let loaded = try store.readMotionSamples(sessionId: manifest.sessionId)
        #expect(loaded.count == 50)
        #expect(loaded.first?.timestamp == samples.first?.timestamp)
        #expect(loaded.last?.userAccelX == 0.49)

        let framed = try store.readMotionFrameData(sessionId: manifest.sessionId)
        #expect(framed != nil)
        #expect(framed!.count > 0)

        let zlibURL = try store.sessionDirectory(for: manifest.sessionId)
            .appendingPathComponent("motion-000.jsonl.zlib")
        #expect(FileManager.default.fileExists(atPath: zlibURL.path))
    }

    @Test func transferPackageCarriesFramesNotExpandedMotion() throws {
        let watchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-mot-\(UUID().uuidString)", isDirectory: true)
        let phoneRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("phone-mot-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: watchRoot)
            try? FileManager.default.removeItem(at: phoneRoot)
        }

        let watchStore = SessionFileStore(rootURL: watchRoot)
        let manifest = SessionManifest(
            testerId: "t",
            appVersion: "1.0",
            buildNumber: "1",
            watchModel: "Ultra2",
            systemVersion: "26.0"
        )
        try watchStore.createSession(manifest: manifest)
        try watchStore.appendMotionSamples(
            [
                MotionSample(
                    timestamp: Date(timeIntervalSince1970: 1),
                    userAccelX: 0.11,
                    userAccelY: 0.22,
                    userAccelZ: 0.33,
                    rotationX: 1,
                    rotationY: 2,
                    rotationZ: 3,
                    pitch: 0.4,
                    roll: 0.5,
                    yaw: 0.6
                )
            ],
            sessionId: manifest.sessionId
        )
        try watchStore.markReadyToTransfer(sessionId: manifest.sessionId, endedAt: Date())

        let package = try watchStore.buildTransferPackage(sessionId: manifest.sessionId)
        #expect(package.motion.isEmpty)
        #expect(package.motionFramesZlib != nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(package)
        #expect(!String(data: encoded, encoding: .utf8)!.contains("userAccelX"))

        try watchStore.importTransferPackage(package, intoPhoneStore: phoneRoot)
        let phoneStore = SessionFileStore(rootURL: phoneRoot)
        let phoneMotion = try phoneStore.readMotionSamples(sessionId: manifest.sessionId)
        #expect(phoneMotion.count == 1)
        #expect(phoneMotion[0].userAccelX == 0.11)
    }

    @Test func compressedMotionMuchSmallerThanNaiveJSONL() throws {
        let samples = (0..<500).map { i -> MotionSample in
            let t = Double(i)
            return MotionSample(
                timestamp: Date(timeIntervalSince1970: t / 25.0),
                userAccelX: sin(t / 10),
                userAccelY: cos(t / 10),
                userAccelZ: 0.01 * Double(i % 7),
                rotationX: 0.1,
                rotationY: -0.2,
                rotationZ: 0.3,
                pitch: 0.01,
                roll: -0.02,
                yaw: 0.03
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var naive = Data()
        for sample in samples {
            var line = try encoder.encode(sample)
            line.append(contentsOf: "\n".utf8)
            naive.append(line)
        }
        let framed = try CompressedJSONLFrames.makeFrame(jsonlUTF8: naive)
        // Framed zlib should crush repetitive JSONL well below half.
        #expect(framed.count * 2 < naive.count)
    }
}
