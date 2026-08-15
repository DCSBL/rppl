import type {
  AnalysisPackage,
  DerivedSession,
  DetectionEvent,
  LocationSample,
  RideSegment,
} from './types'
import { toMs } from './analysisPrep'
import { acceptsStep, meters } from './geoDistance'
import { LapRideTracker, defaultLapThresholds } from './lapRideTracker'
import { thresholds } from './signalFilter'

const RIDING = 'riding'
const PAUSED = 'paused'
const UNSURE = 'unsure'

export interface AttributedPhase {
  attributedCode: string
  startMs: number
  endMs: number
}

export function effectiveEvents(events: DetectionEvent[]): DetectionEvent[] {
  const superseded = new Set(
    events.map((e) => e.supersedesId).filter((id): id is string => Boolean(id)),
  )
  return events
    .filter((e) => !superseded.has(e.id))
    .sort((a, b) => toMs(a.timestamp) - toMs(b.timestamp))
}

/** Unsure → paused for ride windows (mirrors SessionStatsBuilder.attributed). */
function attributed(code: string): string {
  if (code === UNSURE) return PAUSED
  return code
}

export function buildAttributedPhases(
  effective: DetectionEvent[],
  sessionStartMs: number,
  sessionEndMs: number,
): AttributedPhase[] {
  const phases: AttributedPhase[] = []
  let currentCode = PAUSED
  let intervalStart = sessionStartMs

  for (const event of effective) {
    const end = Math.min(toMs(event.timestamp), sessionEndMs)
    if (end > intervalStart) {
      phases.push({
        attributedCode: attributed(currentCode),
        startMs: intervalStart,
        endMs: end,
      })
    }
    currentCode = event.code
    intervalStart = Math.max(toMs(event.timestamp), sessionStartMs)
  }

  if (sessionEndMs > intervalStart) {
    phases.push({
      attributedCode: attributed(currentCode),
      startMs: intervalStart,
      endMs: sessionEndMs,
    })
  }

  return mergeAdjacentPhases(phases)
}

function mergeAdjacentPhases(phases: AttributedPhase[]): AttributedPhase[] {
  const merged: AttributedPhase[] = []
  for (const phase of phases) {
    if (phase.endMs <= phase.startMs) continue
    const last = merged[merged.length - 1]
    if (
      last &&
      last.attributedCode === phase.attributedCode &&
      last.endMs === phase.startMs
    ) {
      last.endMs = phase.endMs
    } else {
      merged.push({ ...phase })
    }
  }
  return merged
}

export function rideWindows(phases: AttributedPhase[]): { startMs: number; endMs: number }[] {
  return phases
    .filter((p) => p.attributedCode === RIDING)
    .map((p) => ({ startMs: p.startMs, endMs: p.endMs }))
}

function hasPausedPhase(phases: AttributedPhase[], beforeMs: number): boolean {
  return phases.some(
    (p) => p.attributedCode === PAUSED && p.startMs < beforeMs && p.endMs > p.startMs,
  )
}

function distanceMeters(
  locations: LocationSample[],
  fromMs: number,
  endMs: number,
  maxHorizontalAccuracyM: number,
): number {
  const inWindow = locations.filter((s) => {
    const t = toMs(s.timestamp)
    return t >= fromMs && t <= endMs
  })
  if (inWindow.length < 2) return 0
  let total = 0
  let previous: LocationSample | undefined
  for (const sample of inWindow) {
    const from = previous
    previous = sample
    if (!from) continue
    if (!acceptsStep(from, sample, maxHorizontalAccuracyM)) continue
    total += meters(from.latitude, from.longitude, sample.latitude, sample.longitude)
  }
  return total
}

/** Derive rides + lap counts + start anchors (offline, mirrors branch SessionStatsBuilder). */
export function deriveSession(pkg: AnalysisPackage, spanEndMs: number): DerivedSession {
  const sessionStartMs = toMs(pkg.manifest.startedAt)
  const sessionEndMs = Math.max(
    spanEndMs,
    pkg.manifest.endedAt ? toMs(pkg.manifest.endedAt) : sessionStartMs,
  )
  const effective = effectiveEvents(pkg.detections)
  const phases = buildAttributedPhases(effective, sessionStartMs, sessionEndMs)
  const windows = rideWindows(phases)
  const sortedLocations = [...pkg.locations].sort(
    (a, b) => toMs(a.timestamp) - toMs(b.timestamp),
  )

  const lapTracker = new LapRideTracker(defaultLapThresholds)
  if (hasPausedPhase(phases, windows[0]?.startMs ?? sessionEndMs)) {
    lapTracker.notePaused()
  }

  const rides: RideSegment[] = []
  for (let i = 0; i < windows.length; i++) {
    const window = windows[i]!
    const distance = distanceMeters(
      sortedLocations,
      window.startMs,
      window.endMs,
      thresholds.maxHorizontalAccuracyM,
    )
    lapTracker.beginRide()
    for (const sample of sortedLocations) {
      const t = toMs(sample.timestamp)
      if (t < window.startMs || t > window.endMs) continue
      lapTracker.addLocation(sample)
    }
    const laps = lapTracker.lapCount
    const startLatitude = lapTracker.startLatitude
    const startLongitude = lapTracker.startLongitude
    lapTracker.endRide()
    rides.push({
      index: i + 1,
      startMs: window.startMs,
      endMs: window.endMs,
      durationMs: Math.max(0, window.endMs - window.startMs),
      distanceMeters: distance,
      lapCount: laps,
      startLatitude,
      startLongitude,
    })
  }

  return {
    phases: phases.map((p) => ({
      code: p.attributedCode,
      startMs: p.startMs,
      endMs: p.endMs,
    })),
    rides,
    totalLapCount: rides.reduce((sum, r) => sum + r.lapCount, 0),
  }
}

/** Display code at playhead from raw detection segments (not attributed). */
export function codeAt(segments: { code: string; startMs: number; endMs: number }[], tMs: number): string | null {
  for (let i = segments.length - 1; i >= 0; i--) {
    const s = segments[i]!
    if (tMs >= s.startMs && tMs < s.endMs) return s.code
  }
  if (segments.length && tMs >= segments[segments.length - 1]!.startMs) {
    return segments[segments.length - 1]!.code
  }
  return null
}

export function nearestLocation(
  locations: LocationSample[],
  tMs: number,
): LocationSample | null {
  if (!locations.length) return null
  let best = locations[0]!
  let bestDist = Math.abs(toMs(best.timestamp) - tMs)
  for (const loc of locations) {
    const d = Math.abs(toMs(loc.timestamp) - tMs)
    if (d < bestDist) {
      bestDist = d
      best = loc
    }
  }
  return best
}
