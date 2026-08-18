/** Framed zlib JSONL: repeating `[UInt32 BE compressedLength][zlib payload]`. */

function readUInt32BE(bytes: Uint8Array, offset: number): number {
  return (
    ((bytes[offset]! << 24) |
      (bytes[offset + 1]! << 16) |
      (bytes[offset + 2]! << 8) |
      bytes[offset + 3]!) >>>
    0
  )
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0
  for (const part of parts) total += part.byteLength
  const out = new Uint8Array(total)
  let offset = 0
  for (const part of parts) {
    out.set(part, offset)
    offset += part.byteLength
  }
  return out
}

async function transformBytes(stream: ReadableStream<Uint8Array>): Promise<Uint8Array> {
  const buf = await new Response(stream).arrayBuffer()
  return new Uint8Array(buf)
}

async function inflateZlib(payload: Uint8Array): Promise<Uint8Array> {
  try {
    return await transformBytes(
      new Blob([payload as BlobPart]).stream().pipeThrough(new DecompressionStream('deflate')),
    )
  } catch {
    return transformBytes(
      new Blob([payload as BlobPart]).stream().pipeThrough(new DecompressionStream('deflate-raw')),
    )
  }
}

function bytesFromBase64(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

export async function decodeMotionFrameBytes(data: Uint8Array): Promise<string> {
  let offset = 0
  const parts: Uint8Array[] = []
  while (offset < data.length) {
    if (offset + 4 > data.length) throw new Error('truncated motion frame')
    const length = readUInt32BE(data, offset)
    offset += 4
    if (length <= 0 || offset + length > data.length) {
      throw new Error('truncated motion frame')
    }
    const slice = data.subarray(offset, offset + length)
    offset += length
    parts.push(await inflateZlib(slice))
  }
  return new TextDecoder().decode(concatBytes(parts))
}

export async function decodeMotionFrames(b64: string): Promise<string> {
  return decodeMotionFrameBytes(bytesFromBase64(b64))
}
