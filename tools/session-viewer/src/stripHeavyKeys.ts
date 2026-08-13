const HEAVY_KEYS = ['motionFramesZlib', 'motion', 'health', 'labels'] as const

/** Drop selected top-level keys by byte rewrite — never builds motion/health graphs. */
export function stripHeavyKeys(raw: string): string {
  let bytes: Uint8Array = new TextEncoder().encode(raw)
  for (const key of HEAVY_KEYS) {
    bytes = removeTopLevelKey(bytes, key)
  }
  return new TextDecoder().decode(bytes)
}

function removeTopLevelKey(bytes: Uint8Array, key: string): Uint8Array {
  const needle = new TextEncoder().encode(`"${key}"`)
  const keyIndex = findTopLevelKey(bytes, needle)
  if (keyIndex === null) return bytes

  let removeStart = keyIndex
  let k = keyIndex - 1
  while (k >= 0 && isWhitespace(bytes[k]!)) k -= 1
  if (k >= 0 && bytes[k] === 0x2c /* , */) removeStart = k

  let i = keyIndex + needle.length
  i = skipWhitespace(bytes, i)
  if (i >= bytes.length || bytes[i] !== 0x3a /* : */) {
    throw new Error(`invalid JSON around key ${key}`)
  }
  i += 1
  i = skipWhitespace(bytes, i)
  const valueEnd = skipValue(bytes, i)

  let removeEnd = valueEnd
  if (removeStart === keyIndex) {
    const j = skipWhitespace(bytes, valueEnd)
    if (j < bytes.length && bytes[j] === 0x2c) removeEnd = j + 1
  }

  const out = new Uint8Array(bytes.length - (removeEnd - removeStart))
  out.set(bytes.subarray(0, removeStart), 0)
  out.set(bytes.subarray(removeEnd), removeStart)
  return out
}

function findTopLevelKey(bytes: Uint8Array, needle: Uint8Array): number | null {
  let depth = 0
  let inString = false
  let escaped = false
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i]!
    if (inString) {
      if (escaped) escaped = false
      else if (b === 0x5c) escaped = true
      else if (b === 0x22) inString = false
      continue
    }
    if (b === 0x22) {
      if (depth === 1 && matches(bytes, i, needle)) return i
      inString = true
    } else if (b === 0x7b || b === 0x5b) depth += 1
    else if (b === 0x7d || b === 0x5d) depth -= 1
  }
  return null
}

function matches(bytes: Uint8Array, index: number, needle: Uint8Array): boolean {
  if (index + needle.length > bytes.length) return false
  for (let o = 0; o < needle.length; o++) {
    if (bytes[index + o] !== needle[o]) return false
  }
  return true
}

function skipValue(bytes: Uint8Array, start: number): number {
  if (start >= bytes.length) throw new Error('invalid JSON value')
  const b = bytes[start]!
  if (b === 0x22) {
    let i = start + 1
    let escaped = false
    while (i < bytes.length) {
      const c = bytes[i]!
      if (escaped) escaped = false
      else if (c === 0x5c) escaped = true
      else if (c === 0x22) return i + 1
      i += 1
    }
    throw new Error('unterminated string')
  }
  if (b === 0x7b || b === 0x5b) {
    let i = start
    let depth = 0
    let inString = false
    let escaped = false
    while (i < bytes.length) {
      const c = bytes[i]!
      if (inString) {
        if (escaped) escaped = false
        else if (c === 0x5c) escaped = true
        else if (c === 0x22) inString = false
        i += 1
        continue
      }
      if (c === 0x22) inString = true
      else if (c === 0x7b || c === 0x5b) depth += 1
      else if (c === 0x7d || c === 0x5d) {
        depth -= 1
        if (depth === 0) return i + 1
      }
      i += 1
    }
    throw new Error('unbalanced brackets')
  }
  let i = start
  while (i < bytes.length) {
    const c = bytes[i]!
    if (isWhitespace(c) || c === 0x2c || c === 0x7d || c === 0x5d) break
    i += 1
  }
  return i
}

function skipWhitespace(bytes: Uint8Array, start: number): number {
  let i = start
  while (i < bytes.length && isWhitespace(bytes[i]!)) i += 1
  return i
}

function isWhitespace(b: number): boolean {
  return b === 0x20 || b === 0x0a || b === 0x0d || b === 0x09
}
