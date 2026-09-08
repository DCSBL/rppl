import './style.css'
import type { AnalysisPackage, DerivedSession, Segment, TimeRange } from './types'
import {
  clampPlayhead,
  clampWindow,
  defaultSelection,
  locationsInWindow,
  segments,
  segmentsInWindow,
  sessionSpan,
  toMs,
} from './analysisPrep'
import { accuracySeries, mpsToKmh, usableSpeedAt, usableSpeedSeries } from './signalFilter'
import { loadExportJson, loadSessionFolder } from './loadSession'
import { loadCachedSession, saveCachedSession } from './sessionCache'
import {
  buildTrackMarkers,
  batterySeries,
  drawAccuracy,
  drawBattery,
  drawEvents,
  drawSpeed,
  drawTrack,
  hitTestEvents,
  hitTestTrack,
  timeAtClientX,
  trackExtent,
} from './draw'
import { codeAt, deriveSession, nearestLocation } from './sessionStats'
import {
  type ExportSource,
  buildWindowExport,
  downloadTransferPackage,
  summarizeExport,
} from './exportSession'

const app = document.querySelector<HTMLDivElement>('#app')!
app.innerHTML = `
  <header>
    <h1>Rppl session viewer</h1>
    <div class="controls">
      <label class="file">Open folder
        <input id="folder" type="file" webkitdirectory multiple />
      </label>
      <label class="file">Open export JSON
        <input id="json" type="file" accept="application/json,.json" />
      </label>
      <button type="button" id="exportJson" class="export-btn" disabled title="Download start/end window as session JSON">Export JSON</button>
    </div>
    <button type="button" id="playPause" class="play-btn" disabled title="Space">Play</button>
  </header>
  <div id="status">Open session folder (manifest + jsonl) or export JSON.</div>
  <div id="summary" class="summary" hidden>
    <div class="metric"><span class="metric-label">Distance</span><span class="metric-value" data-k="distance">—</span></div>
    <div class="metric"><span class="metric-label">Sets</span><span class="metric-value" data-k="sets">—</span></div>
    <div class="metric"><span class="metric-label">Laps</span><span class="metric-value" data-k="laps">—</span></div>
    <div class="metric"><span class="metric-label">Peak</span><span class="metric-value" data-k="peak">—</span></div>
    <div class="metric"><span class="metric-label">Avg</span><span class="metric-value" data-k="avg">—</span></div>
    <div class="metric"><span class="metric-label">Riding</span><span class="metric-value" data-k="riding">—</span></div>
  </div>
  <p class="hint">Window default first 5 min (min 60 s). Timeline: green riding · blue inactive · grey unsure · yellow lap. Space = play/pause realtime. Export JSON = current start/end window, all streams.</p>
  <div class="range-row">
    <span>Start</span>
    <input id="start" type="range" disabled />
    <span id="startLabel">—</span>
  </div>
  <div class="range-row">
    <span>End</span>
    <input id="end" type="range" disabled />
    <span id="endLabel">—</span>
  </div>
  <div class="range-row">
    <span>Playhead</span>
    <input id="playhead" type="range" disabled />
    <span id="playheadLabel">—</span>
  </div>
  <div class="panel events"><canvas id="events"></canvas></div>
  <div class="panel"><canvas id="speed"></canvas></div>
  <div class="panel track"><canvas id="track"></canvas></div>
  <div class="panel"><canvas id="accuracy"></canvas></div>
  <div class="panel"><canvas id="battery"></canvas></div>
  <div id="detail">Scrub playhead or click chart / track for point detail.</div>
`

function wearSettingsLabel(manifest: AnalysisPackage['manifest']): string {
  const wrist = manifest.wristLocation
  const crown = manifest.crownOrientation
  if (!wrist && !crown) return ''
  return ` · wrist ${wrist ?? '?'} · crown ${crown ?? '?'}`
}

const statusEl = document.querySelector<HTMLDivElement>('#status')!
const summaryEl = document.querySelector<HTMLDivElement>('#summary')!
const detailEl = document.querySelector<HTMLDivElement>('#detail')!
const startSlider = document.querySelector<HTMLInputElement>('#start')!
const endSlider = document.querySelector<HTMLInputElement>('#end')!
const playheadSlider = document.querySelector<HTMLInputElement>('#playhead')!
const startLabel = document.querySelector<HTMLSpanElement>('#startLabel')!
const endLabel = document.querySelector<HTMLSpanElement>('#endLabel')!
const playheadLabel = document.querySelector<HTMLSpanElement>('#playheadLabel')!
const playPauseBtn = document.querySelector<HTMLButtonElement>('#playPause')!
const exportJsonBtn = document.querySelector<HTMLButtonElement>('#exportJson')!
const trackCanvas = document.querySelector<HTMLCanvasElement>('#track')!
const speedCanvas = document.querySelector<HTMLCanvasElement>('#speed')!
const accuracyCanvas = document.querySelector<HTMLCanvasElement>('#accuracy')!
const batteryCanvas = document.querySelector<HTMLCanvasElement>('#battery')!
const eventsCanvas = document.querySelector<HTMLCanvasElement>('#events')!

let pkg: AnalysisPackage | null = null
let span: TimeRange | null = null
let windowRange: TimeRange | null = null
let playheadMs = 0
let allSegments: Segment[] = []
let derived: DerivedSession | null = null
let selectedId: string | null = null
let sourceLabel = ''
let exportSource: ExportSource = { kind: 'memory' }
let persistTimer: number | null = null
let playing = false
let rafId: number | null = null
let lastFrameTs: number | null = null

function fmt(ms: number): string {
  return new Date(ms).toISOString().slice(11, 19)
}

function formatDuration(ms: number): string {
  const sec = Math.max(0, Math.round(ms / 1000))
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = sec % 60
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`
  return `${s}s`
}

function formatDistanceKm(meters: number): string {
  return `${(meters / 1000).toFixed(2)} km`
}

function formatSpeed(kmh: number | null): string {
  return kmh != null ? `${kmh.toFixed(1)} km/h` : '—'
}

function setMetric(key: string, value: string): void {
  const el = summaryEl.querySelector<HTMLSpanElement>(`[data-k="${key}"]`)
  if (el) el.textContent = value
}

function updateSummary(d: DerivedSession): void {
  summaryEl.hidden = false
  setMetric('distance', formatDistanceKm(d.totalDistanceMeters))
  setMetric('sets', String(d.sets.length))
  setMetric('laps', String(d.totalLapCount))
  setMetric('peak', formatSpeed(d.peakSpeedKmh))
  setMetric('avg', formatSpeed(d.averageSpeedKmh))
  setMetric('riding', formatDuration(d.ridingDurationMs))
}

function offsetLabel(ms: number): string {
  if (!span) return '—'
  const sec = Math.max(0, Math.round((ms - span.startMs) / 1000))
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `+${m}:${String(s).padStart(2, '0')} (${fmt(ms)})`
}

function schedulePersist(): void {
  if (!pkg) return
  if (persistTimer !== null) window.clearTimeout(persistTimer)
  persistTimer = window.setTimeout(() => {
    persistTimer = null
    void saveCachedSession({
      label: sourceLabel,
      package: pkg!,
      window: windowRange,
      playheadMs,
    }).catch(() => {
      /* ignore quota / private-mode failures */
    })
  }, 200)
}

function setPlaying(next: boolean): void {
  playing = next
  playPauseBtn.textContent = playing ? 'Pause' : 'Play'
  if (playing) {
    lastFrameTs = null
    if (rafId == null) rafId = requestAnimationFrame(playbackTick)
  } else if (rafId != null) {
    cancelAnimationFrame(rafId)
    rafId = null
    lastFrameTs = null
  }
}

function playbackTick(now: number): void {
  rafId = null
  if (!playing || !windowRange) return
  if (lastFrameTs == null) lastFrameTs = now
  const delta = now - lastFrameTs
  lastFrameTs = now
  const next = playheadMs + delta
  if (next >= windowRange.endMs) {
    playheadMs = windowRange.endMs
    wirePlayheadSlider()
    render()
    schedulePersist()
    setPlaying(false)
    return
  }
  playheadMs = next
  wirePlayheadSlider()
  render()
  rafId = requestAnimationFrame(playbackTick)
}

function togglePlay(): void {
  if (!pkg || !windowRange) return
  if (!playing && playheadMs >= windowRange.endMs) {
    playheadMs = windowRange.startMs
  }
  setPlaying(!playing)
}

function applyPackage(
  next: AnalysisPackage,
  label: string,
  savedWindow?: TimeRange | null,
  savedPlayhead?: number | null,
): void {
  setPlaying(false)
  pkg = next
  sourceLabel = label
  span = sessionSpan(next)
  windowRange = savedWindow
    ? clampWindow(savedWindow.startMs, savedWindow.endMs, span)
    : defaultSelection(span)
  allSegments = segments(next.detections, span.endMs)
  derived = deriveSession(next, span.endMs)
  selectedId = null
  playheadMs = clampPlayhead(
    savedPlayhead ?? windowRange.startMs,
    windowRange,
  )
  statusEl.textContent =
    `${label} · ${next.manifest.sessionId} · ${next.locations.length} locs · ${next.detections.length} detections`
    + wearSettingsLabel(next.manifest)
  updateSummary(derived)
  wireSliders()
  render()
  schedulePersist()
}

function wirePlayheadSlider(): void {
  if (!windowRange) return
  playheadSlider.value = String(Math.round(playheadMs))
  playheadLabel.textContent = offsetLabel(playheadMs)
}

function wireSliders(): void {
  if (!span || !windowRange) return
  startSlider.disabled = false
  endSlider.disabled = false
  playheadSlider.disabled = false
  playPauseBtn.disabled = false
  exportJsonBtn.disabled = false
  startSlider.min = String(span.startMs)
  startSlider.max = String(span.endMs)
  endSlider.min = String(span.startMs)
  endSlider.max = String(span.endMs)
  startSlider.step = '1000'
  endSlider.step = '1000'
  startSlider.value = String(windowRange.startMs)
  endSlider.value = String(windowRange.endMs)
  startLabel.textContent = offsetLabel(windowRange.startMs)
  endLabel.textContent = offsetLabel(windowRange.endMs)

  playheadSlider.min = String(windowRange.startMs)
  playheadSlider.max = String(windowRange.endMs)
  playheadSlider.step = '1000'
  playheadMs = clampPlayhead(playheadMs, windowRange)
  wirePlayheadSlider()
}

function onWindowSliderChange(): void {
  if (!span) return
  setPlaying(false)
  const next = clampWindow(Number(startSlider.value), Number(endSlider.value), span)
  windowRange = next
  startSlider.value = String(next.startMs)
  endSlider.value = String(next.endMs)
  startLabel.textContent = offsetLabel(next.startMs)
  endLabel.textContent = offsetLabel(next.endMs)
  playheadMs = clampPlayhead(playheadMs, next)
  playheadSlider.min = String(next.startMs)
  playheadSlider.max = String(next.endMs)
  wirePlayheadSlider()
  render()
  schedulePersist()
}

function onPlayheadSliderChange(): void {
  if (!windowRange) return
  setPlaying(false)
  playheadMs = clampPlayhead(Number(playheadSlider.value), windowRange)
  wirePlayheadSlider()
  render()
  schedulePersist()
}

function seekTo(tMs: number): void {
  if (!windowRange) return
  setPlaying(false)
  playheadMs = clampPlayhead(tMs, windowRange)
  wirePlayheadSlider()
  render()
  schedulePersist()
}

function render(): void {
  if (!pkg || !windowRange || !derived) return
  const locs = locationsInWindow(pkg.locations, windowRange)
  const segs = segmentsInWindow(allSegments, windowRange)
  const selected = allSegments.find((s) => s.id === selectedId) ?? null
  const speed = usableSpeedSeries(pkg.locations, windowRange)
  const accuracy = accuracySeries(pkg.locations, windowRange)
  const battery = batterySeries(pkg.battery ?? [], windowRange)
  const extent = trackExtent(pkg.locations)
  const playLoc = nearestLocation(pkg.locations, playheadMs)
  const markers = buildTrackMarkers(locs, derived.sets, playLoc)

  drawEvents(eventsCanvas, segs, windowRange, selectedId, derived.sets, playheadMs)
  drawSpeed(speedCanvas, speed, windowRange, selected, playheadMs)
  drawTrack(trackCanvas, locs, allSegments, markers, extent)
  drawAccuracy(accuracyCanvas, accuracy, windowRange, selected, playheadMs)
  drawBattery(batteryCanvas, battery, windowRange, selected, playheadMs)

  updateDetail(selected, playLoc)
}

function nearestBattery(
  samples: AnalysisPackage['battery'],
  tMs: number,
): { level: number; state: string } | null {
  const list = samples ?? []
  if (!list.length) return null
  let best = list[0]!
  let bestDist = Math.abs(toMs(best.timestamp) - tMs)
  for (const s of list) {
    const d = Math.abs(toMs(s.timestamp) - tMs)
    if (d < bestDist) {
      best = s
      bestDist = d
    }
  }
  if (bestDist > 90_000) return null
  return { level: best.level, state: best.state }
}

function updateDetail(selected: Segment | null, playLoc: ReturnType<typeof nearestLocation>): void {
  if (!pkg || !windowRange) return
  const code = codeAt(allSegments, playheadMs)
  const usable = usableSpeedAt(pkg.locations, playheadMs)
  const rawSpeed =
    playLoc?.speed != null && playLoc.speed >= 0 ? mpsToKmh(playLoc.speed) : null
  const speedText =
    usable != null
      ? `${usable.toFixed(1)} km/h`
      : rawSpeed != null
        ? `${rawSpeed.toFixed(1)} km/h (raw)`
        : '—'
  const lat = playLoc ? playLoc.latitude.toFixed(6) : '—'
  const lon = playLoc ? playLoc.longitude.toFixed(6) : '—'
  const acc = playLoc ? `${playLoc.horizontalAccuracy.toFixed(1)} m` : '—'
  const batt = nearestBattery(pkg.battery, playheadMs)
  const battText =
    batt != null ? `${(batt.level * 100).toFixed(2)}% (${batt.state})` : '—'
  const lines = [
    `Playhead ${offsetLabel(playheadMs)} · code=${code ?? '—'} · speed=${speedText}`,
    `lat=${lat} lon=${lon} · accuracy=${acc} · battery=${battText}`,
  ]
  if (selected) {
    lines.push(
      [
        `Selected ${selected.code}`,
        selected.reason,
        selected.detectorId ? `detector=${selected.detectorId}` : null,
        selected.motionActivity ? `activity=${selected.motionActivity}` : null,
        selected.waterSubmersionState ? `water=${selected.waterSubmersionState}` : null,
        selected.speedMps != null ? `eventSpeed=${(selected.speedMps * 3.6).toFixed(1)} km/h` : null,
      ]
        .filter(Boolean)
        .join(' · '),
    )
  }
  detailEl.textContent = lines.join('\n')
}

startSlider.addEventListener('input', onWindowSliderChange)
endSlider.addEventListener('input', onWindowSliderChange)
playheadSlider.addEventListener('input', onPlayheadSliderChange)
playPauseBtn.addEventListener('click', () => togglePlay())

window.addEventListener('keydown', (ev) => {
  if (ev.code !== 'Space' && ev.key !== ' ') return
  const target = ev.target as HTMLElement | null
  if (target instanceof HTMLInputElement && target.type === 'file') return
  if (target instanceof HTMLTextAreaElement) return
  if (target instanceof HTMLButtonElement) return
  ev.preventDefault()
  togglePlay()
})

function onTimeChartClick(canvas: HTMLCanvasElement, clientX: number): void {
  if (!windowRange) return
  const t = timeAtClientX(canvas, clientX, windowRange)
  if (t == null) return
  seekTo(t)
}

speedCanvas.addEventListener('click', (ev) => onTimeChartClick(speedCanvas, ev.clientX))
accuracyCanvas.addEventListener('click', (ev) => onTimeChartClick(accuracyCanvas, ev.clientX))
batteryCanvas.addEventListener('click', (ev) => onTimeChartClick(batteryCanvas, ev.clientX))

eventsCanvas.addEventListener('click', (ev) => {
  if (!windowRange) return
  const segs = segmentsInWindow(allSegments, windowRange)
  const hit = hitTestEvents(eventsCanvas, ev.clientX, segs, windowRange)
  selectedId = hit?.id ?? null
  const t = timeAtClientX(eventsCanvas, ev.clientX, windowRange)
  if (t != null) seekTo(t)
  else render()
})

trackCanvas.addEventListener('click', (ev) => {
  if (!pkg || !windowRange) return
  const locs = locationsInWindow(pkg.locations, windowRange)
  const hit = hitTestTrack(
    trackCanvas,
    ev.clientX,
    ev.clientY,
    locs,
    trackExtent(pkg.locations),
  )
  if (hit) seekTo(toMs(hit.timestamp))
})

document.querySelector<HTMLInputElement>('#folder')!.addEventListener('change', async (ev) => {
  const input = ev.target as HTMLInputElement
  const files = input.files
  if (!files?.length) return
  statusEl.textContent = 'Loading folder…'
  try {
    const loaded = await loadSessionFolder(files)
    exportSource = { kind: 'folder', files: Array.from(files) }
    applyPackage(loaded, 'folder')
  } catch (err) {
    statusEl.textContent = err instanceof Error ? err.message : String(err)
  }
  input.value = ''
})

document.querySelector<HTMLInputElement>('#json')!.addEventListener('change', async (ev) => {
  const input = ev.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  statusEl.textContent = 'Loading export…'
  try {
    const loaded = await loadExportJson(file)
    exportSource = { kind: 'json', file }
    applyPackage(loaded, file.name)
  } catch (err) {
    statusEl.textContent = err instanceof Error ? err.message : String(err)
  }
  input.value = ''
})

exportJsonBtn.addEventListener('click', () => {
  void (async () => {
    if (!pkg || !windowRange) return
    exportJsonBtn.disabled = true
    statusEl.textContent = 'Exporting window…'
    try {
      const sliced = await buildWindowExport(exportSource, pkg, windowRange)
      downloadTransferPackage(sliced)
      const lean =
        exportSource.kind === 'memory' ? ' · lean (reopen folder/JSON for motion/health)' : ''
      statusEl.textContent = `Exported ${summarizeExport(sliced)}${lean}`
    } catch (err) {
      statusEl.textContent = err instanceof Error ? err.message : String(err)
    } finally {
      exportJsonBtn.disabled = !pkg
    }
  })()
})

window.addEventListener('resize', () => {
  if (pkg) render()
})

void loadCachedSession()
  .then((cached) => {
    if (!cached?.package?.manifest) return
    exportSource = { kind: 'memory' }
    applyPackage(
      cached.package,
      cached.label || 'restored',
      cached.window,
      cached.playheadMs,
    )
    statusEl.textContent = `${statusEl.textContent} · restored`
  })
  .catch(() => {
    /* first visit / blocked storage */
  })
