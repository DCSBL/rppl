import type {
  AnalysisPackage,
  AssumptionEvent,
  LocationSample,
  Segment,
  TimeRange,
} from './types'

export const DEFAULT_WINDOW_MS = 5 * 60 * 1000
export const MIN_WINDOW_MS = 60 * 1000

export function toMs(iso: string): number {
  return Date.parse(iso)
}

export function sessionSpan(pkg: AnalysisPackage): TimeRange {
  const locationTimes = pkg.locations.map((l) => toMs(l.timestamp))
  const assumptionTimes = pkg.assumptions.map((a) => toMs(a.timestamp))
  const started = toMs(pkg.manifest.startedAt)
  const lower = Math.min(
    started,
    ...locationTimes,
    ...assumptionTimes.filter((n) => !Number.isNaN(n)),
  )
  const ended = pkg.manifest.endedAt ? toMs(pkg.manifest.endedAt) : NaN
  const upperCandidates = [
    ended,
    ...locationTimes,
    ...assumptionTimes,
  ].filter((n) => !Number.isNaN(n))
  const upper = Math.max(
    upperCandidates.length ? Math.max(...upperCandidates) : lower + DEFAULT_WINDOW_MS,
    lower + MIN_WINDOW_MS,
  )
  return { startMs: lower, endMs: upper }
}

/** First 5 minutes of span, clamped to span end. */
export function defaultSelection(span: TimeRange): TimeRange {
  const end = Math.min(span.startMs + DEFAULT_WINDOW_MS, span.endMs)
  return {
    startMs: span.startMs,
    endMs: Math.max(end, span.startMs + MIN_WINDOW_MS),
  }
}

/** Enforce min 60s window while staying inside span. No max — long windows are user's risk. */
export function clampWindow(startMs: number, endMs: number, span: TimeRange): TimeRange {
  let start = Math.max(span.startMs, Math.min(startMs, span.endMs - MIN_WINDOW_MS))
  let end = Math.max(start + MIN_WINDOW_MS, Math.min(endMs, span.endMs))
  if (end - start < MIN_WINDOW_MS) {
    end = Math.min(span.endMs, start + MIN_WINDOW_MS)
    start = Math.max(span.startMs, end - MIN_WINDOW_MS)
  }
  return { startMs: start, endMs: end }
}

export function segments(assumptions: AssumptionEvent[], sessionEndMs: number): Segment[] {
  const sorted = [...assumptions].sort((a, b) => toMs(a.timestamp) - toMs(b.timestamp))
  if (!sorted.length) return []
  return sorted.flatMap((event, index) => {
    const start = toMs(event.timestamp)
    const rawEnd = index + 1 < sorted.length ? toMs(sorted[index + 1]!.timestamp) : sessionEndMs
    const end = Math.max(rawEnd, start)
    if (end <= start) return []
    return [
      {
        id: event.id || `assumption-${index}`,
        code: event.code,
        startMs: start,
        endMs: end,
        reason: event.reason,
        speedMps: event.speedMps,
        waterSubmersionState: event.waterSubmersionState,
        motionActivity: event.motionActivity,
      },
    ]
  })
}

export function clippedBand(
  startMs: number,
  endMs: number,
  range: TimeRange,
): TimeRange | null {
  const lo = Math.max(startMs, range.startMs)
  const hi = Math.min(endMs, range.endMs)
  if (hi <= lo) return null
  return { startMs: lo, endMs: hi }
}

export function locationsInWindow(
  locations: LocationSample[],
  range: TimeRange,
): LocationSample[] {
  return locations.filter((l) => {
    const t = toMs(l.timestamp)
    return t >= range.startMs && t <= range.endMs
  })
}

export function segmentsInWindow(segs: Segment[], range: TimeRange): Segment[] {
  return segs.filter((s) => s.endMs > range.startMs && s.startMs < range.endMs)
}
