export interface SessionManifest {
  schemaVersion: number
  sessionId: string
  testerId: string
  appVersion: string
  buildNumber: string
  watchModel: string
  systemVersion: string
  startedAt: string
  endedAt?: string | null
  transferState: string
  /** Watch settings wrist side at session start (`left` / `right`). */
  wristLocation?: string | null
  /** Watch settings Digital Crown side at session start (`left` / `right`). */
  crownOrientation?: string | null
}

export interface LocationSample {
  timestamp: string
  latitude: number
  longitude: number
  altitude?: number | null
  horizontalAccuracy: number
  verticalAccuracy?: number | null
  speed?: number | null
  course?: number | null
}

export interface DetectionEvent {
  id: string
  code: string
  timestamp: string
  reason: string
  detectorId: string
  speedMps?: number | null
  horizontalAccuracy?: number | null
  waterSubmersionState?: string | null
  motionActivity?: string | null
  supersedesId?: string | null
}

export interface AnalysisPackage {
  manifest: SessionManifest
  detections: DetectionEvent[]
  locations: LocationSample[]
}

/** Phone Share / WC transfer JSON. Extra keys on samples are kept as-is. */
export interface SessionTransferPackage {
  manifest: SessionManifest
  detections: DetectionEvent[]
  locations: LocationSample[]
  motion?: unknown[]
  motionFramesZlib?: string
  health: unknown[]
}

export interface Segment {
  id: string
  code: string
  startMs: number
  endMs: number
  reason: string
  speedMps?: number | null
  waterSubmersionState?: string | null
  motionActivity?: string | null
  detectorId?: string
}

export interface TimeRange {
  startMs: number
  endMs: number
}

export interface SpeedPoint {
  tMs: number
  kmh: number
}

export interface AccuracyPoint {
  tMs: number
  meters: number
}

export interface SetSegment {
  index: number
  startMs: number
  endMs: number
  durationMs: number
  distanceMeters: number
  lapCount: number
  /** Crossing completion times (ms) for timeline markers. */
  lapAtMs: number[]
  startLatitude: number | null
  startLongitude: number | null
}

export interface DerivedSession {
  phases: { code: string; startMs: number; endMs: number }[]
  sets: SetSegment[]
  totalLapCount: number
  totalDistanceMeters: number
  ridingDurationMs: number
  inactiveDurationMs: number
  peakSpeedKmh: number | null
  averageSpeedKmh: number | null
}
