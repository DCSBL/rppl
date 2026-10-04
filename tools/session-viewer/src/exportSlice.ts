import type {
  AnalysisPackage,
  BatterySample,
  DetectionEvent,
  LocationSample,
  SessionManifest,
  SessionTransferPackage,
  TimeRange,
} from './types'
import { decodeMotionFrames } from './motionFrames'

export function isoUtc(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')
}

/** Read `timestamp` or compact motion `t`. */
export function timestampMs(value: unknown): number | null {
  if (!value || typeof value !== 'object') return null
  const rec = value as Record<string, unknown>
  const raw = rec.timestamp ?? rec.t
  if (typeof raw === 'string') {
    const ms = Date.parse(raw)
    return Number.isNaN(ms) ? null : ms
  }
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return raw < 1e12 ? raw * 1000 : raw
  }
  return null
}

export function recordsInWindow<T>(records: T[], range: TimeRange): T[] {
  return records.filter((record) => {
    const t = timestampMs(record)
    return t != null && t >= range.startMs && t <= range.endMs
  })
}

/**
 * Events inside window, plus last event before start (timestamp clamped to start)
 * so sliced session opens on the code that was already active.
 */
export function sliceDetections(events: DetectionEvent[], range: TimeRange): DetectionEvent[] {
  const sorted = [...events].sort((a, b) => {
    const da = timestampMs(a) ?? 0
    const db = timestampMs(b) ?? 0
    return da - db
  })
  let lastBefore: DetectionEvent | null = null
  const inside: DetectionEvent[] = []
  for (const event of sorted) {
    const t = timestampMs(event)
    if (t == null) continue
    if (t < range.startMs) lastBefore = event
    else if (t <= range.endMs) inside.push(event)
  }
  const startsAtBoundary = inside.some((e) => timestampMs(e) === range.startMs)
  if (lastBefore && !startsAtBoundary) {
    return [{ ...lastBefore, timestamp: isoUtc(range.startMs) }, ...inside]
  }
  return inside
}

function sliceManifest(manifest: SessionManifest, range: TimeRange): SessionManifest {
  return {
    ...manifest,
    startedAt: isoUtc(range.startMs),
    endedAt: isoUtc(range.endMs),
  }
}

export function sliceAnalysisPackage(
  pkg: AnalysisPackage,
  range: TimeRange,
): SessionTransferPackage {
  return {
    manifest: sliceManifest(pkg.manifest, range),
    detections: sliceDetections(pkg.detections, range),
    locations: recordsInWindow(pkg.locations, range) as LocationSample[],
    motion: [],
    health: [],
    battery: recordsInWindow(pkg.battery ?? [], range),
  }
}

export interface RawTransferPackage {
  manifest: SessionManifest
  detections?: DetectionEvent[]
  locations?: unknown[]
  motion?: unknown[]
  motionFramesZlib?: string
  /** Uncompressed motion JSONL (folder load). Sliced into `motion` on export. */
  motionJsonl?: string
  health?: unknown[]
  water?: unknown[]
  battery?: BatterySample[]
}

function detectionsOf(raw: RawTransferPackage): DetectionEvent[] {
  return raw.detections ?? []
}

function jsonlRecordsInWindow(jsonl: string, range: TimeRange): unknown[] {
  const kept: unknown[] = []
  for (const line of jsonl.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed) continue
    const record = JSON.parse(trimmed) as unknown
    const t = timestampMs(record)
    if (t != null && t >= range.startMs && t <= range.endMs) kept.push(record)
  }
  return kept
}

async function sliceMotion(raw: RawTransferPackage, range: TimeRange): Promise<unknown[]> {
  let jsonl: string | null = raw.motionJsonl ?? null
  if (jsonl == null && raw.motionFramesZlib) {
    jsonl = await decodeMotionFrames(raw.motionFramesZlib)
  }
  if (jsonl != null && jsonl.trim()) return jsonlRecordsInWindow(jsonl, range)
  if (raw.motion?.length) return recordsInWindow(raw.motion, range)
  return []
}

export async function sliceTransferPackage(
  raw: RawTransferPackage,
  range: TimeRange,
): Promise<SessionTransferPackage> {
  return {
    manifest: sliceManifest(raw.manifest, range),
    detections: sliceDetections(detectionsOf(raw), range),
    locations: recordsInWindow(raw.locations ?? [], range) as LocationSample[],
    motion: await sliceMotion(raw, range),
    health: recordsInWindow(raw.health ?? [], range),
    water: recordsInWindow(raw.water ?? [], range),
    battery: recordsInWindow(raw.battery ?? [], range) as BatterySample[],
  }
}
