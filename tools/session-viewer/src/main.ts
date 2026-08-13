import './style.css'
import type { AnalysisPackage, Segment, TimeRange } from './types'
import {
  clampWindow,
  defaultSelection,
  locationsInWindow,
  segments,
  segmentsInWindow,
  sessionSpan,
} from './analysisPrep'
import { accuracySeries, usableSpeedSeries } from './signalFilter'
import { loadExportJson, loadSessionFolder } from './loadSession'
import { loadCachedSession, saveCachedSession } from './sessionCache'
import {
  assumptionMarkers,
  drawAccuracy,
  drawEvents,
  drawSpeed,
  drawTrack,
  hitTestEvents,
  trackExtent,
} from './draw'

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
    </div>
  </header>
  <div id="status">Open session folder (manifest + jsonl) or export JSON.</div>
  <p class="hint">Window default first 5 min (min 60 s). Track is relative shape (not map tiles).</p>
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
  <div class="panel track"><canvas id="track"></canvas></div>
  <div class="panel"><canvas id="speed"></canvas></div>
  <div class="panel"><canvas id="accuracy"></canvas></div>
  <div class="panel events"><canvas id="events"></canvas></div>
  <div id="detail">Click an assumption band for detail.</div>
`

const statusEl = document.querySelector<HTMLDivElement>('#status')!
const detailEl = document.querySelector<HTMLDivElement>('#detail')!
const startSlider = document.querySelector<HTMLInputElement>('#start')!
const endSlider = document.querySelector<HTMLInputElement>('#end')!
const startLabel = document.querySelector<HTMLSpanElement>('#startLabel')!
const endLabel = document.querySelector<HTMLSpanElement>('#endLabel')!
const trackCanvas = document.querySelector<HTMLCanvasElement>('#track')!
const speedCanvas = document.querySelector<HTMLCanvasElement>('#speed')!
const accuracyCanvas = document.querySelector<HTMLCanvasElement>('#accuracy')!
const eventsCanvas = document.querySelector<HTMLCanvasElement>('#events')!

let pkg: AnalysisPackage | null = null
let span: TimeRange | null = null
let windowRange: TimeRange | null = null
let allSegments: Segment[] = []
let selectedId: string | null = null
let sourceLabel = ''
let persistTimer: number | null = null

function fmt(ms: number): string {
  return new Date(ms).toISOString().slice(11, 19)
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
    }).catch(() => {
      /* ignore quota / private-mode failures */
    })
  }, 200)
}

function applyPackage(
  next: AnalysisPackage,
  label: string,
  savedWindow?: TimeRange | null,
): void {
  pkg = next
  sourceLabel = label
  span = sessionSpan(next)
  windowRange = savedWindow
    ? clampWindow(savedWindow.startMs, savedWindow.endMs, span)
    : defaultSelection(span)
  allSegments = segments(next.assumptions, span.endMs)
  selectedId = null
  statusEl.textContent = `${label} · ${next.manifest.sessionId} · ${next.locations.length} locs · ${next.assumptions.length} assumptions`
  wireSliders()
  render()
  schedulePersist()
}

function wireSliders(): void {
  if (!span || !windowRange) return
  startSlider.disabled = false
  endSlider.disabled = false
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
}

function onSliderChange(): void {
  if (!span) return
  const next = clampWindow(Number(startSlider.value), Number(endSlider.value), span)
  windowRange = next
  startSlider.value = String(next.startMs)
  endSlider.value = String(next.endMs)
  startLabel.textContent = offsetLabel(next.startMs)
  endLabel.textContent = offsetLabel(next.endMs)
  render()
  schedulePersist()
}

function render(): void {
  if (!pkg || !windowRange) return
  const locs = locationsInWindow(pkg.locations, windowRange)
  const segs = segmentsInWindow(allSegments, windowRange)
  const selected = allSegments.find((s) => s.id === selectedId) ?? null
  const speed = usableSpeedSeries(pkg.locations, windowRange)
  const accuracy = accuracySeries(pkg.locations, windowRange)
  const markers = assumptionMarkers(locs, segs)

  drawTrack(trackCanvas, locs, markers, trackExtent(pkg.locations))
  drawSpeed(speedCanvas, speed, windowRange, selected)
  drawAccuracy(accuracyCanvas, accuracy, windowRange, selected)
  drawEvents(eventsCanvas, segs, windowRange, selectedId)

  if (selected) {
    const bits = [
      selected.code,
      selected.reason,
      selected.motionActivity ? `activity=${selected.motionActivity}` : null,
      selected.waterSubmersionState ? `water=${selected.waterSubmersionState}` : null,
      selected.speedMps != null ? `speed=${(selected.speedMps * 3.6).toFixed(1)} km/h` : null,
    ].filter(Boolean)
    detailEl.textContent = bits.join(' · ')
  } else {
    detailEl.textContent = 'Click an assumption band for detail.'
  }
}

startSlider.addEventListener('input', onSliderChange)
endSlider.addEventListener('input', onSliderChange)

eventsCanvas.addEventListener('click', (ev) => {
  if (!windowRange) return
  const segs = segmentsInWindow(allSegments, windowRange)
  const hit = hitTestEvents(eventsCanvas, ev.clientX, segs, windowRange)
  selectedId = hit?.id ?? null
  render()
})

document.querySelector<HTMLInputElement>('#folder')!.addEventListener('change', async (ev) => {
  const input = ev.target as HTMLInputElement
  const files = input.files
  if (!files?.length) return
  statusEl.textContent = 'Loading folder…'
  try {
    applyPackage(await loadSessionFolder(files), 'folder')
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
    applyPackage(await loadExportJson(file), file.name)
  } catch (err) {
    statusEl.textContent = err instanceof Error ? err.message : String(err)
  }
  input.value = ''
})

window.addEventListener('resize', () => {
  if (pkg) render()
})

void loadCachedSession()
  .then((cached) => {
    if (!cached?.package?.manifest) return
    applyPackage(cached.package, cached.label || 'restored', cached.window)
    statusEl.textContent = `${statusEl.textContent} · restored`
  })
  .catch(() => {
    /* first visit / blocked storage */
  })
