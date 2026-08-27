import Compression
import Foundation

public enum CompressedJSONLFrameError: Error, Equatable, Sendable {
    case truncatedFrame
    case emptyPayload
    case compressionFailed
    case decompressionFailed
}

/// Append-friendly JSONL storage: each flush is one length-prefixed zlib member.
///
/// Frame layout (repeat):
/// `[UInt32 BE compressedLength][zlib payload]`
///
/// Concatenated frames decompress to UTF-8 JSONL (newline-delimited objects).
public enum CompressedJSONLFrames {
    public static func makeFrame(jsonlUTF8: Data) throws -> Data {
        guard !jsonlUTF8.isEmpty else { throw CompressedJSONLFrameError.emptyPayload }
        let compressed = try compress(jsonlUTF8)
        return lengthPrefixed(compressed)
    }

    public static func appendFrame(
        jsonlUTF8: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let frame = try makeFrame(jsonlUTF8: jsonlUTF8)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: frame)
    }

    /// Decompress all frames into concatenated JSONL UTF-8.
    public static func decodeFrames(_ data: Data) throws -> Data {
        var offset = 0
        var result = Data()
        while offset < data.count {
            guard offset + 4 <= data.count else {
                throw CompressedJSONLFrameError.truncatedFrame
            }
            let length = Int(readUInt32BE(data, at: offset))
            offset += 4
            guard length > 0, offset + length <= data.count else {
                throw CompressedJSONLFrameError.truncatedFrame
            }
            let slice = data.subdata(in: offset..<(offset + length))
            offset += length
            result.append(try decompress(slice))
        }
        return result
    }

    private static func compress(_ source: Data) throws -> Data {
        let dstCapacity = source.count + source.count / 16 + 64
        var dest = Data(count: dstCapacity)
        let written = dest.withUnsafeMutableBytes { destPtr -> Int in
            source.withUnsafeBytes { srcPtr -> Int in
                guard let src = srcPtr.bindMemory(to: UInt8.self).baseAddress,
                      let dst = destPtr.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    dst,
                    dstCapacity,
                    src,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw CompressedJSONLFrameError.compressionFailed }
        return dest.prefix(written)
    }

    private static func decompress(_ source: Data) throws -> Data {
        var capacity = max(source.count * 8, 64 * 1024)
        for _ in 0..<8 {
            var dest = Data(count: capacity)
            let written = dest.withUnsafeMutableBytes { destPtr -> Int in
                source.withUnsafeBytes { srcPtr -> Int in
                    guard let src = srcPtr.bindMemory(to: UInt8.self).baseAddress,
                          let dst = destPtr.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        dst,
                        capacity,
                        src,
                        source.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                return dest.prefix(written)
            }
            capacity *= 2
        }
        throw CompressedJSONLFrameError.decompressionFailed
    }

    private static func lengthPrefixed(_ payload: Data) -> Data {
        var out = Data()
        out.reserveCapacity(4 + payload.count)
        var be = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
