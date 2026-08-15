import type { LocationSample } from './types'
import { toMs } from './analysisPrep'
import { thresholds } from './signalFilter'

const EARTH_RADIUS_M = 6_371_000

export function meters(
  fromLat: number,
  fromLon: number,
  toLat: number,
  toLon: number,
): number {
  const lat1 = (fromLat * Math.PI) / 180
  const lat2 = (toLat * Math.PI) / 180
  const dLat = ((toLat - fromLat) * Math.PI) / 180
  const dLon = ((toLon - fromLon) * Math.PI) / 180
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return EARTH_RADIUS_M * c
}

function maxStepMeters(deltaSeconds: number, speedMps: number | null | undefined): number {
  const hardCap = 50
  if (speedMps == null || speedMps < 0 || deltaSeconds <= 0) return hardCap
  const dynamic = Math.abs(speedMps) * deltaSeconds + 20
  return Math.min(hardCap, Math.max(15, dynamic))
}

export function acceptsStep(
  from: LocationSample,
  to: LocationSample,
  maxHorizontalAccuracyM: number = thresholds.maxHorizontalAccuracyM,
  maxPlausibleSpeedKmh: number = thresholds.maxPlausibleSpeedKmh,
): boolean {
  if (from.horizontalAccuracy < 0 || to.horizontalAccuracy < 0) return false
  if (
    from.horizontalAccuracy > maxHorizontalAccuracyM ||
    to.horizontalAccuracy > maxHorizontalAccuracyM
  ) {
    return false
  }
  const delta = (toMs(to.timestamp) - toMs(from.timestamp)) / 1000
  if (delta <= 0) return false
  const step = meters(from.latitude, from.longitude, to.latitude, to.longitude)
  const speed = to.speed ?? from.speed
  if (step > maxStepMeters(delta, speed)) return false
  const impliedKmh = (step / delta) * 3.6
  return impliedKmh <= maxPlausibleSpeedKmh
}
