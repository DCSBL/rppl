import Foundation

#if canImport(Compression)
import Compression

/// Raw DEFLATE (RFC 1951, no zlib header) — Apple's `COMPRESSION_ZLIB`.
enum RawDeflate {
    static func encode(
        dst: UnsafeMutablePointer<UInt8>,
        dstCapacity: Int,
        src: UnsafePointer<UInt8>,
        srcSize: Int
    ) -> Int {
        compression_encode_buffer(dst, dstCapacity, src, srcSize, nil, COMPRESSION_ZLIB)
    }

    static func decode(
        dst: UnsafeMutablePointer<UInt8>,
        dstCapacity: Int,
        src: UnsafePointer<UInt8>,
        srcSize: Int
    ) -> Int {
        compression_decode_buffer(dst, dstCapacity, src, srcSize, nil, COMPRESSION_ZLIB)
    }
}
#else
import CZlib

/// Raw DEFLATE (RFC 1951, no zlib header) via system zlib — byte-compatible with Apple's
/// `COMPRESSION_ZLIB`, so frames written on device decode on Linux (CI) and vice versa.
enum RawDeflate {
    private static let rawWindowBits: Int32 = -15
    private static let compressionLevel: Int32 = 5

    /// Bytes written, or 0 when the output does not fit or zlib fails.
    static func encode(
        dst: UnsafeMutablePointer<UInt8>,
        dstCapacity: Int,
        src: UnsafePointer<UInt8>,
        srcSize: Int
    ) -> Int {
        var stream = z_stream()
        guard deflateInit2_(
            &stream, compressionLevel, Z_DEFLATED, rawWindowBits, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else { return 0 }
        defer { deflateEnd(&stream) }
        stream.next_in = UnsafeMutablePointer(mutating: src)
        stream.avail_in = uInt(srcSize)
        stream.next_out = dst
        stream.avail_out = uInt(dstCapacity)
        guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return 0 }
        return Int(stream.total_out)
    }

    /// Bytes written, or 0 on corrupt input or when `dstCapacity` is too small for the whole
    /// stream (callers grow the buffer and retry).
    static func decode(
        dst: UnsafeMutablePointer<UInt8>,
        dstCapacity: Int,
        src: UnsafePointer<UInt8>,
        srcSize: Int
    ) -> Int {
        var stream = z_stream()
        guard inflateInit2_(
            &stream, rawWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else { return 0 }
        defer { inflateEnd(&stream) }
        stream.next_in = UnsafeMutablePointer(mutating: src)
        stream.avail_in = uInt(srcSize)
        stream.next_out = dst
        stream.avail_out = uInt(dstCapacity)
        guard inflate(&stream, Z_FINISH) == Z_STREAM_END else { return 0 }
        return Int(stream.total_out)
    }
}
#endif
