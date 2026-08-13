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

export interface AssumptionEvent {
  id: string
  code: string
  timestamp: string
  reason: string
  speedMps?: number | null
  waterSubmersionState?: string | null
  motionActivity?: string | null
}

export interface AnalysisPackage {
  manifest: SessionManifest
  assumptions: AssumptionEvent[]
  locations: LocationSample[]
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
