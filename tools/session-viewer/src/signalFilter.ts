import type { AccuracyPoint, LocationSample, SpeedPoint, TimeRange } from './types'
import { toMs } from './analysisPrep'

/** Defaults mirror RpplCore DetectionThresholds. */
export const thresholds = {
  rideEnterSpeedKmh: 20,
  rideEnterHold: 3.0,
  walkBandSpeedKmh: 8,
  rideEnterHoldFromWalk: 4.0,
  stoppedSpeedKmh: 4,
  rideExitHold: 3.0,
  gapUnsureHold: 3.0,
  unsureSameRideWindow: 60.0,
  maxHorizontalAccuracyM: 25,
  maxPlausibleSpeedKmh: 45,
  maxSpeedJumpKmh: 30,
} as const

export function mpsToKmh(mps: number): number {
  return mps * 3.6
}

export function usableSpeedSeries(
  locations: LocationSample[],
  range: TimeRange,
): SpeedPoint[] {
  const points: SpeedPoint[] = []
  let previousUsable: number | null = null
  for (const loc of locations) {
    const tMs = toMs(loc.timestamp)
    if (tMs < range.startMs || tMs > range.endMs) continue
    const usable = filterSpeed(loc.speed ?? null, loc.horizontalAccuracy, previousUsable)
    if (usable === null) continue
    previousUsable = usable
    points.push({ tMs, kmh: mpsToKmh(usable) })
  }
  return points
}

export function accuracySeries(
  locations: LocationSample[],
  range: TimeRange,
): AccuracyPoint[] {
  const points: AccuracyPoint[] = []
  for (const loc of locations) {
    const tMs = toMs(loc.timestamp)
    if (tMs < range.startMs || tMs > range.endMs) continue
    points.push({ tMs, meters: loc.horizontalAccuracy })
  }
  return points
}

/** Single usable speed at tMs, or null. */
export function usableSpeedAt(
  locations: LocationSample[],
  tMs: number,
): number | null {
  let previousUsable: number | null = null
  let best: { tMs: number; kmh: number } | null = null
  for (const loc of locations) {
    const locMs = toMs(loc.timestamp)
    const usable = filterSpeed(loc.speed ?? null, loc.horizontalAccuracy, previousUsable)
    if (usable === null) continue
    previousUsable = usable
    if (locMs <= tMs) {
      best = { tMs: locMs, kmh: mpsToKmh(usable) }
    } else {
      break
    }
  }
  return best?.kmh ?? null
}

function filterSpeed(
  speedMps: number | null,
  horizontalAccuracy: number,
  previousUsableMps: number | null,
): number | null {
  if (speedMps === null || Number.isNaN(speedMps)) return null
  if (horizontalAccuracy < 0) return null
  if (horizontalAccuracy > thresholds.maxHorizontalAccuracyM) return null
  const kmh = mpsToKmh(speedMps)
  if (kmh > thresholds.maxPlausibleSpeedKmh) return null
  if (previousUsableMps !== null) {
    const delta = Math.abs(kmh - mpsToKmh(previousUsableMps))
    if (delta >= thresholds.maxSpeedJumpKmh) return null
  }
  return speedMps
}

/** Exported for offline peak-speed over set windows. */
export function filterSpeedMps(
  speedMps: number | null,
  horizontalAccuracy: number,
  previousUsableMps: number | null,
): number | null {
  return filterSpeed(speedMps, horizontalAccuracy, previousUsableMps)
}
