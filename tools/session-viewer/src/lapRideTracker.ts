import type { LocationSample } from './types'
import { acceptsStep, meters } from './geoDistance'
import { thresholds as gpsThresholds } from './signalFilter'

/** Mirrors RpplCore LapThresholds (cable-loop defaults). */
export interface LapThresholds {
  startSafeRadiusM: number
  exitRadiusM: number
  minPathBeforeCrossingM: number
  maxHorizontalAccuracyM: number
}

export const defaultLapThresholds: LapThresholds = {
  startSafeRadiusM: 50,
  exitRadiusM: 70,
  minPathBeforeCrossingM: 200,
  maxHorizontalAccuracyM: gpsThresholds.maxHorizontalAccuracyM,
}

type ZoneState = 'idle' | 'awaitingAnchor' | 'atStart' | 'outside'

/**
 * Crossing-based lap counter — TS port of RpplCore LapRideTracker (WIP).
 * Exposes start anchor for viz.
 */
export class LapRideTracker {
  lapCount = 0
  isRideActive = false
  startLatitude: number | null = null
  startLongitude: number | null = null

  private thresholds: LapThresholds
  private zoneState: ZoneState = 'idle'
  private hasSeenPause = false
  private scoringThisRide = false
  private pathSinceLeaveM = 0
  private previousLocation: LocationSample | null = null

  constructor(thresholds: LapThresholds = defaultLapThresholds) {
    this.thresholds = { ...thresholds }
  }

  reset(): void {
    this.lapCount = 0
    this.isRideActive = false
    this.zoneState = 'idle'
    this.hasSeenPause = false
    this.scoringThisRide = false
    this.startLatitude = null
    this.startLongitude = null
    this.pathSinceLeaveM = 0
    this.previousLocation = null
  }

  notePaused(): void {
    if (this.isRideActive) this.endRide()
    this.hasSeenPause = true
  }

  beginRide(): void {
    if (this.isRideActive) this.endRide()
    this.lapCount = 0
    this.isRideActive = true
    this.scoringThisRide = this.hasSeenPause
    this.zoneState = this.scoringThisRide ? 'awaitingAnchor' : 'idle'
    this.startLatitude = null
    this.startLongitude = null
    this.pathSinceLeaveM = 0
    this.previousLocation = null
  }

  endRide(): void {
    this.isRideActive = false
    this.scoringThisRide = false
    this.zoneState = 'idle'
    this.previousLocation = null
    this.hasSeenPause = true
  }

  addLocation(sample: LocationSample): void {
    if (!this.isRideActive || !this.scoringThisRide) return
    if (
      sample.horizontalAccuracy < 0 ||
      sample.horizontalAccuracy > this.thresholds.maxHorizontalAccuracyM
    ) {
      return
    }

    if (this.zoneState === 'awaitingAnchor') {
      this.startLatitude = sample.latitude
      this.startLongitude = sample.longitude
      this.zoneState = 'atStart'
      this.previousLocation = sample
      return
    }

    if (this.startLatitude == null || this.startLongitude == null) return

    const distanceFromStart = meters(
      this.startLatitude,
      this.startLongitude,
      sample.latitude,
      sample.longitude,
    )

    if (
      this.previousLocation &&
      acceptsStep(
        this.previousLocation,
        sample,
        this.thresholds.maxHorizontalAccuracyM,
      )
    ) {
      const step = meters(
        this.previousLocation.latitude,
        this.previousLocation.longitude,
        sample.latitude,
        sample.longitude,
      )
      if (this.zoneState === 'outside') this.pathSinceLeaveM += step
      this.previousLocation = sample
    } else if (!this.previousLocation) {
      this.previousLocation = sample
    } else {
      return
    }

    if (this.zoneState === 'atStart') {
      if (distanceFromStart > this.thresholds.exitRadiusM) {
        this.zoneState = 'outside'
        this.pathSinceLeaveM = 0
      }
    } else if (this.zoneState === 'outside') {
      if (
        distanceFromStart <= this.thresholds.startSafeRadiusM &&
        this.pathSinceLeaveM >= this.thresholds.minPathBeforeCrossingM
      ) {
        this.lapCount += 1
        this.zoneState = 'atStart'
        this.pathSinceLeaveM = 0
      }
    }
  }
}
