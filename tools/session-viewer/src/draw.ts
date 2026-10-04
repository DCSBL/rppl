import type {
  AccuracyPoint,
  BatteryPoint,
  BatterySample,
  LocationSample,
  SetSegment,
  Segment,
  SpeedPoint,
  TimeRange,
} from './types'
import { clippedBand, toMs } from './analysisPrep'
import { thresholds } from './signalFilter'

const PAD = { left: 48, right: 12, top: 18, bottom: 28 }

const CODE_COLORS: Record<string, string> = {
  riding: '#22c55e',
  inactive: '#3b82f6',
  unsure: '#9ca3af',
}

export function codeColor(code: string): string {
  return CODE_COLORS[code] ?? '#a855f7'
}

function setupCanvas(canvas: HTMLCanvasElement): {
  ctx: CanvasRenderingContext2D
  w: number
  h: number
  dpr: number
} {
  const dpr = window.devicePixelRatio || 1
  const rect = canvas.getBoundingClientRect()
  const w = Math.max(1, Math.floor(rect.width))
  const h = Math.max(1, Math.floor(rect.height))
  canvas.width = Math.floor(w * dpr)
  canvas.height = Math.floor(h * dpr)
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  return { ctx, w, h, dpr }
}

function clear(ctx: CanvasRenderingContext2D, w: number, h: number): void {
  ctx.fillStyle = '#111827'
  ctx.fillRect(0, 0, w, h)
}

function drawCentered(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  text: string,
): void {
  ctx.fillStyle = '#9ca3af'
  ctx.font = '13px ui-sans-serif, system-ui, sans-serif'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText(text, w / 2, h / 2)
}

function plotFrame(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  title: string,
): { x0: number; y0: number; x1: number; y1: number } {
  clear(ctx, w, h)
  ctx.fillStyle = '#e5e7eb'
  ctx.font = '12px ui-sans-serif, system-ui, sans-serif'
  ctx.textAlign = 'left'
  ctx.textBaseline = 'top'
  ctx.fillText(title, 8, 4)
  const x0 = PAD.left
  const y0 = PAD.top
  const x1 = w - PAD.right
  const y1 = h - PAD.bottom
  ctx.strokeStyle = '#374151'
  ctx.strokeRect(x0, y0, x1 - x0, y1 - y0)
  return { x0, y0, x1, y1 }
}

function xAt(tMs: number, range: TimeRange, x0: number, x1: number): number {
  const span = Math.max(1, range.endMs - range.startMs)
  return x0 + ((tMs - range.startMs) / span) * (x1 - x0)
}

function yAt(v: number, minV: number, maxV: number, y0: number, y1: number): number {
  const span = Math.max(1e-9, maxV - minV)
  return y1 - ((v - minV) / span) * (y1 - y0)
}

/** Stroke open polyline only — never closePath. Breaks when `breakBefore` is true. */
function strokeOpenPath(
  ctx: CanvasRenderingContext2D,
  points: { x: number; y: number }[],
  breakBefore?: (index: number) => boolean,
): void {
  if (!points.length) return
  ctx.beginPath()
  let penDown = false
  for (let i = 0; i < points.length; i++) {
    const p = points[i]!
    if (!penDown || (breakBefore?.(i) ?? false)) {
      ctx.moveTo(p.x, p.y)
      penDown = true
    } else {
      ctx.lineTo(p.x, p.y)
    }
  }
  ctx.stroke()
}

const SERIES_GAP_MS = 30_000

export interface TrackExtent {
  minLon: number
  maxLon: number
  minLat: number
  maxLat: number
}

export type TrackMarkerKind = 'start' | 'end' | 'anchor' | 'playhead'

export interface TrackMarker {
  lat: number
  lon: number
  kind: TrackMarkerKind
}

/** Bounds from full session GPS — fixed zoom while scrubbing. */
export function trackExtent(locations: LocationSample[]): TrackExtent | null {
  if (!locations.length) return null
  let minLon = Infinity
  let maxLon = -Infinity
  let minLat = Infinity
  let maxLat = -Infinity
  for (const loc of locations) {
    minLon = Math.min(minLon, loc.longitude)
    maxLon = Math.max(maxLon, loc.longitude)
    minLat = Math.min(minLat, loc.latitude)
    maxLat = Math.max(maxLat, loc.latitude)
  }
  if (maxLon - minLon < 1e-7) {
    minLon -= 1e-5
    maxLon += 1e-5
  }
  if (maxLat - minLat < 1e-7) {
    minLat -= 1e-5
    maxLat += 1e-5
  }
  return { minLon, maxLon, minLat, maxLat }
}

function codeAtTime(segs: Segment[], tMs: number): string {
  for (let i = segs.length - 1; i >= 0; i--) {
    const s = segs[i]!
    if (tMs >= s.startMs && tMs < s.endMs) return s.code
  }
  return 'inactive'
}

/** Relative lon/lat track — colored by detection code; markers + playhead. */
export function drawTrack(
  canvas: HTMLCanvasElement,
  locations: LocationSample[],
  allSegments: Segment[],
  markers: TrackMarker[],
  extent: TrackExtent | null,
): void {
  const { ctx, w, h } = setupCanvas(canvas)
  const frame = plotFrame(ctx, w, h, 'Track (relative, fixed zoom)')
  if (!extent) {
    drawCentered(ctx, w, h, 'No GPS in session')
    return
  }
  if (!locations.length) {
    drawCentered(ctx, w, h, 'No GPS in window')
    return
  }

  const { minLon, maxLon, minLat, maxLat } = extent
  const midLat = ((minLat + maxLat) / 2) * (Math.PI / 180)
  const lonScale = Math.cos(midLat)
  const widthM = (maxLon - minLon) * lonScale
  const heightM = maxLat - minLat
  const plotW = frame.x1 - frame.x0
  const plotH = frame.y1 - frame.y0
  const scale = Math.min(plotW / Math.max(widthM, 1e-12), plotH / Math.max(heightM, 1e-12)) * 0.9
  const cx = (frame.x0 + frame.x1) / 2
  const cy = (frame.y0 + frame.y1) / 2
  const midLon = (minLon + maxLon) / 2
  const midLatVal = (minLat + maxLat) / 2

  const project = (lat: number, lon: number): [number, number] => {
    const x = cx + (lon - midLon) * lonScale * scale
    const y = cy - (lat - midLatVal) * scale
    return [x, y]
  }

  const sorted = [...locations].sort((a, b) => toMs(a.timestamp) - toMs(b.timestamp))
  const diag = Math.hypot(plotW, plotH)
  const jumpLimit = diag * 0.35
  const pts = sorted.map((loc) => {
    const [x, y] = project(loc.latitude, loc.longitude)
    return {
      x,
      y,
      tMs: toMs(loc.timestamp),
      code: codeAtTime(allSegments, toMs(loc.timestamp)),
    }
  })

  ctx.lineWidth = 2
  for (let i = 1; i < pts.length; i++) {
    const prev = pts[i - 1]!
    const cur = pts[i]!
    if (cur.tMs < prev.tMs) continue
    if (cur.tMs - prev.tMs > SERIES_GAP_MS) continue
    const dist = Math.hypot(cur.x - prev.x, cur.y - prev.y)
    if (dist > jumpLimit) continue
    ctx.strokeStyle = codeColor(prev.code)
    ctx.beginPath()
    ctx.moveTo(prev.x, prev.y)
    ctx.lineTo(cur.x, cur.y)
    ctx.stroke()
  }

  for (const m of markers) {
    const [x, y] = project(m.lat, m.lon)
    ctx.beginPath()
    if (m.kind === 'start') {
      ctx.fillStyle = '#22c55e'
      ctx.arc(x, y, 5, 0, Math.PI * 2)
    } else if (m.kind === 'end') {
      ctx.fillStyle = '#ef4444'
      ctx.arc(x, y, 5, 0, Math.PI * 2)
    } else if (m.kind === 'anchor') {
      ctx.strokeStyle = '#fbbf24'
      ctx.fillStyle = 'rgba(251, 191, 36, 0.35)'
      ctx.lineWidth = 2
      ctx.arc(x, y, 7, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
      continue
    } else {
      // playhead
      ctx.fillStyle = '#ffffff'
      ctx.strokeStyle = '#111827'
      ctx.lineWidth = 1.5
      ctx.arc(x, y, 6, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
      continue
    }
    ctx.fill()
  }
}

function drawPlayheadCursor(
  ctx: CanvasRenderingContext2D,
  frame: { x0: number; y0: number; x1: number; y1: number },
  range: TimeRange,
  playheadMs: number | null,
): void {
  if (playheadMs == null) return
  if (playheadMs < range.startMs || playheadMs > range.endMs) return
  const x = xAt(playheadMs, range, frame.x0, frame.x1)
  ctx.strokeStyle = '#f8fafc'
  ctx.lineWidth = 1
  ctx.setLineDash([3, 3])
  ctx.beginPath()
  ctx.moveTo(x, frame.y0)
  ctx.lineTo(x, frame.y1)
  ctx.stroke()
  ctx.setLineDash([])
}

export function drawSpeed(
  canvas: HTMLCanvasElement,
  points: SpeedPoint[],
  range: TimeRange,
  highlight: Segment | null,
  playheadMs: number | null,
): void {
  const { ctx, w, h } = setupCanvas(canvas)
  const frame = plotFrame(ctx, w, h, 'Speed (km/h, usable)')
  const maxV = Math.max(
    thresholds.rideEnterSpeedKmh + 5,
    ...points.map((p) => p.kmh),
    1,
  )
  const minV = 0

  if (highlight) {
    const band = clippedBand(highlight.startMs, highlight.endMs, range)
    if (band) {
      const xA = xAt(band.startMs, range, frame.x0, frame.x1)
      const xB = xAt(band.endMs, range, frame.x0, frame.x1)
      ctx.fillStyle = 'rgba(37, 99, 235, 0.18)'
      ctx.fillRect(xA, frame.y0, Math.max(1, xB - xA), frame.y1 - frame.y0)
    }
  }

  ctx.fillStyle = '#9ca3af'
  ctx.font = '10px ui-sans-serif, system-ui, sans-serif'
  ctx.textAlign = 'right'
  ctx.fillText(String(Math.round(maxV)), frame.x0 - 4, frame.y0 + 8)
  ctx.fillText('0', frame.x0 - 4, frame.y1)
  drawSpeedGate(
    ctx,
    frame,
    minV,
    maxV,
    thresholds.rideEnterSpeedKmh,
    '#34d399',
    `enter ${thresholds.rideEnterSpeedKmh} km/h × ${thresholds.rideEnterHold}s (walk ${thresholds.rideEnterHoldFromWalk}s)`,
  )
  drawSpeedGate(
    ctx,
    frame,
    minV,
    maxV,
    thresholds.stoppedSpeedKmh,
    '#60a5fa',
    `exit ${thresholds.stoppedSpeedKmh} km/h × ${thresholds.rideExitHold}s`,
  )
  drawSpeedGate(
    ctx,
    frame,
    minV,
    maxV,
    thresholds.walkBandSpeedKmh,
    '#a78bfa',
    `walk ${thresholds.walkBandSpeedKmh} km/h`,
  )
  if (!points.length) {
    drawCentered(ctx, w, h, 'No usable speed in window')
    drawPlayheadCursor(ctx, frame, range, playheadMs)
    return
  }

  const sorted = [...points].sort((a, b) => a.tMs - b.tMs)
  const pts = sorted.map((p) => ({
    x: xAt(p.tMs, range, frame.x0, frame.x1),
    y: yAt(p.kmh, minV, maxV, frame.y0, frame.y1),
    tMs: p.tMs,
  }))
  ctx.strokeStyle = '#f8fafc'
  ctx.lineWidth = 1.25
  strokeOpenPath(ctx, pts, (i) => {
    const prev = pts[i - 1]!
    const cur = pts[i]!
    return cur.tMs < prev.tMs || cur.tMs - prev.tMs > SERIES_GAP_MS
  })

  drawPlayheadCursor(ctx, frame, range, playheadMs)
}

function drawSpeedGate(
  ctx: CanvasRenderingContext2D,
  frame: { x0: number; x1: number; y0: number; y1: number },
  minV: number,
  maxV: number,
  kmh: number,
  color: string,
  label: string,
): void {
  const y = yAt(kmh, minV, maxV, frame.y0, frame.y1)
  ctx.strokeStyle = color
  ctx.setLineDash([4, 4])
  ctx.beginPath()
  ctx.moveTo(frame.x0, y)
  ctx.lineTo(frame.x1, y)
  ctx.stroke()
  ctx.setLineDash([])
  ctx.fillStyle = color
  ctx.font = '10px ui-sans-serif, system-ui, sans-serif'
  ctx.textAlign = 'left'
  ctx.fillText(label, frame.x0 + 4, y - 2)
}

export function drawAccuracy(
  canvas: HTMLCanvasElement,
  points: AccuracyPoint[],
  range: TimeRange,
  highlight: Segment | null,
  playheadMs: number | null,
): void {
  const { ctx, w, h } = setupCanvas(canvas)
  const frame = plotFrame(ctx, w, h, 'GPS accuracy (m)')
  const maxV = Math.max(
    thresholds.maxHorizontalAccuracyM + 5,
    ...points.map((p) => p.meters),
    1,
  )
  const minV = 0

  if (highlight) {
    const band = clippedBand(highlight.startMs, highlight.endMs, range)
    if (band) {
      const xA = xAt(band.startMs, range, frame.x0, frame.x1)
      const xB = xAt(band.endMs, range, frame.x0, frame.x1)
      ctx.fillStyle = 'rgba(37, 99, 235, 0.18)'
      ctx.fillRect(xA, frame.y0, Math.max(1, xB - xA), frame.y1 - frame.y0)
    }
  }

  const yGate = yAt(thresholds.maxHorizontalAccuracyM, minV, maxV, frame.y0, frame.y1)
  ctx.strokeStyle = '#f87171'
  ctx.setLineDash([4, 4])
  ctx.beginPath()
  ctx.moveTo(frame.x0, yGate)
  ctx.lineTo(frame.x1, yGate)
  ctx.stroke()
  ctx.setLineDash([])
  ctx.fillStyle = '#f87171'
  ctx.font = '10px ui-sans-serif, system-ui, sans-serif'
  ctx.fillText(`gate ${thresholds.maxHorizontalAccuracyM}m`, frame.x0 + 4, yGate - 2)

  if (!points.length) {
    drawCentered(ctx, w, h, 'No accuracy samples in window')
    drawPlayheadCursor(ctx, frame, range, playheadMs)
    return
  }

  const sorted = [...points].sort((a, b) => a.tMs - b.tMs)
  const pts = sorted.map((p) => ({
    x: xAt(p.tMs, range, frame.x0, frame.x1),
    y: yAt(p.meters, minV, maxV, frame.y0, frame.y1),
    tMs: p.tMs,
  }))
  ctx.strokeStyle = '#fbbf24'
  ctx.lineWidth = 1.25
  strokeOpenPath(ctx, pts, (i) => {
    const prev = pts[i - 1]!
    const cur = pts[i]!
    return cur.tMs < prev.tMs || cur.tMs - prev.tMs > SERIES_GAP_MS
  })
  drawPlayheadCursor(ctx, frame, range, playheadMs)
}

export function batterySeries(samples: BatterySample[], range: TimeRange): BatteryPoint[] {
  return samples
    .map((s) => ({
      tMs: toMs(s.timestamp),
      percent: s.level * 100,
      state: s.state,
    }))
    .filter((p) => !Number.isNaN(p.tMs) && p.tMs >= range.startMs && p.tMs <= range.endMs)
    .sort((a, b) => a.tMs - b.tMs)
}

export function drawBattery(
  canvas: HTMLCanvasElement,
  points: BatteryPoint[],
  range: TimeRange,
  highlight: Segment | null,
  playheadMs: number | null,
): void {
  const { ctx, w, h } = setupCanvas(canvas)
  const frame = plotFrame(ctx, w, h, 'Battery (%)')
  const minV = 0
  const maxV = 100

  if (highlight) {
    const band = clippedBand(highlight.startMs, highlight.endMs, range)
    if (band) {
      const xA = xAt(band.startMs, range, frame.x0, frame.x1)
      const xB = xAt(band.endMs, range, frame.x0, frame.x1)
      ctx.fillStyle = 'rgba(37, 99, 235, 0.18)'
      ctx.fillRect(xA, frame.y0, Math.max(1, xB - xA), frame.y1 - frame.y0)
    }
  }

  if (!points.length) {
    drawCentered(ctx, w, h, 'No battery samples in window')
    drawPlayheadCursor(ctx, frame, range, playheadMs)
    return
  }

  const pts = points.map((p) => ({
    x: xAt(p.tMs, range, frame.x0, frame.x1),
    y: yAt(p.percent, minV, maxV, frame.y0, frame.y1),
    tMs: p.tMs,
    state: p.state,
  }))
  ctx.strokeStyle = '#34d399'
  ctx.lineWidth = 1.25
  strokeOpenPath(ctx, pts, (i) => {
    const prev = pts[i - 1]!
    const cur = pts[i]!
    return cur.tMs < prev.tMs || cur.tMs - prev.tMs > SERIES_GAP_MS
  })

  for (const p of pts) {
    if (p.state !== 'charging' && p.state !== 'full') continue
    ctx.fillStyle = p.state === 'charging' ? '#fbbf24' : '#60a5fa'
    ctx.beginPath()
    ctx.arc(p.x, p.y, 3, 0, Math.PI * 2)
    ctx.fill()
  }

  drawPlayheadCursor(ctx, frame, range, playheadMs)
}

export function drawEvents(
  canvas: HTMLCanvasElement,
  segs: Segment[],
  range: TimeRange,
  selectedId: string | null,
  sets: SetSegment[],
  playheadMs: number | null,
): void {
  const { ctx, w, h } = setupCanvas(canvas)
  const frame = plotFrame(ctx, w, h, 'Detections · laps')
  if (!segs.length) {
    drawCentered(ctx, w, h, 'No detections in window')
    drawPlayheadCursor(ctx, frame, range, playheadMs)
    return
  }
  const laneTop = frame.y0 + 8
  const laneH = frame.y1 - frame.y0 - 16
  for (const seg of segs) {
    const band = clippedBand(seg.startMs, seg.endMs, range)
    if (!band) continue
    const xA = xAt(band.startMs, range, frame.x0, frame.x1)
    const xB = xAt(band.endMs, range, frame.x0, frame.x1)
    ctx.fillStyle = codeColor(seg.code)
    ctx.globalAlpha = seg.id === selectedId ? 1 : 0.75
    ctx.fillRect(xA, laneTop, Math.max(2, xB - xA), laneH)
    ctx.globalAlpha = 1
    if (seg.id === selectedId) {
      ctx.strokeStyle = '#fff'
      ctx.lineWidth = 2
      ctx.strokeRect(xA, laneTop, Math.max(2, xB - xA), laneH)
    }
  }

  for (const set of sets) {
    for (const lapMs of set.lapAtMs) {
      if (lapMs < range.startMs || lapMs > range.endMs) continue
      const x = xAt(lapMs, range, frame.x0, frame.x1)
      ctx.strokeStyle = 'rgba(250, 204, 21, 0.9)'
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(x, laneTop)
      ctx.lineTo(x, laneTop + laneH)
      ctx.stroke()
    }
  }

  drawPlayheadCursor(ctx, frame, range, playheadMs)
}

export function hitTestEvents(
  canvas: HTMLCanvasElement,
  clientX: number,
  segs: Segment[],
  range: TimeRange,
): Segment | null {
  const t = timeAtClientX(canvas, clientX, range)
  if (t == null) return null
  for (let i = segs.length - 1; i >= 0; i--) {
    const s = segs[i]!
    if (t >= s.startMs && t < s.endMs) return s
  }
  return null
}

export function timeAtClientX(
  canvas: HTMLCanvasElement,
  clientX: number,
  range: TimeRange,
): number | null {
  const rect = canvas.getBoundingClientRect()
  const x = clientX - rect.left
  const x0 = PAD.left
  const x1 = rect.width - PAD.right
  if (x < x0 || x > x1) return null
  return range.startMs + ((x - x0) / Math.max(1, x1 - x0)) * (range.endMs - range.startMs)
}

/** Nearest GPS sample under a track click (client coords). */
export function hitTestTrack(
  canvas: HTMLCanvasElement,
  clientX: number,
  clientY: number,
  locations: LocationSample[],
  extent: TrackExtent | null,
): LocationSample | null {
  if (!extent || !locations.length) return null
  const rect = canvas.getBoundingClientRect()
  const mx = clientX - rect.left
  const my = clientY - rect.top
  const w = rect.width
  const h = rect.height
  const frame = {
    x0: PAD.left,
    y0: PAD.top,
    x1: w - PAD.right,
    y1: h - PAD.bottom,
  }
  const { minLon, maxLon, minLat, maxLat } = extent
  const midLat = ((minLat + maxLat) / 2) * (Math.PI / 180)
  const lonScale = Math.cos(midLat)
  const widthM = (maxLon - minLon) * lonScale
  const heightM = maxLat - minLat
  const plotW = frame.x1 - frame.x0
  const plotH = frame.y1 - frame.y0
  const scale = Math.min(plotW / Math.max(widthM, 1e-12), plotH / Math.max(heightM, 1e-12)) * 0.9
  const cx = (frame.x0 + frame.x1) / 2
  const cy = (frame.y0 + frame.y1) / 2
  const midLon = (minLon + maxLon) / 2
  const midLatVal = (minLat + maxLat) / 2

  let best: LocationSample | null = null
  let bestDist = 24
  for (const loc of locations) {
    const x = cx + (loc.longitude - midLon) * lonScale * scale
    const y = cy - (loc.latitude - midLatVal) * scale
    const d = Math.hypot(x - mx, y - my)
    if (d < bestDist) {
      bestDist = d
      best = loc
    }
  }
  return best
}

export function buildTrackMarkers(
  locations: LocationSample[],
  sets: SetSegment[],
  playheadLoc: LocationSample | null,
): TrackMarker[] {
  const markers: TrackMarker[] = []
  if (!locations.length) return markers
  const first = locations[0]!
  const last = locations[locations.length - 1]!
  markers.push({ lat: first.latitude, lon: first.longitude, kind: 'start' })
  markers.push({ lat: last.latitude, lon: last.longitude, kind: 'end' })

  for (const set of sets) {
    if (set.startLatitude != null && set.startLongitude != null) {
      markers.push({
        lat: set.startLatitude,
        lon: set.startLongitude,
        kind: 'anchor',
      })
    }
  }

  if (playheadLoc) {
    markers.push({
      lat: playheadLoc.latitude,
      lon: playheadLoc.longitude,
      kind: 'playhead',
    })
  }
  return markers
}
