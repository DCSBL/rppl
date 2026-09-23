import type {
  AnalysisPackage,
  BatterySample,
  DetectionEvent,
  LocationSample,
  SessionManifest,
} from './types'
import { stripHeavyKeys } from './stripHeavyKeys'

export async function loadExportJson(file: File): Promise<AnalysisPackage> {
  const raw = await file.text()
  const lean = stripHeavyKeys(raw)
  const parsed = JSON.parse(lean) as {
    manifest?: SessionManifest
    detections?: DetectionEvent[]
    assumptions?: DetectionEvent[]
    locations?: LocationSample[]
    battery?: BatterySample[]
  }
  if (!parsed.manifest) throw new Error('export missing manifest')
  const detections = normalizeDetections(parsed.detections ?? parsed.assumptions ?? [])
  const battery = normalizeBattery(parsed.battery ?? [])
  return {
    manifest: parsed.manifest,
    detections,
    locations: [...(parsed.locations ?? [])].sort(
      (a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp),
    ),
    battery,
  }
}

/** Load session dir via folder picker FileList (webkitdirectory). */
export async function loadSessionFolder(files: FileList): Promise<AnalysisPackage> {
  const list = Array.from(files)
  const byName = new Map(list.map((f) => [basename(f.name), f]))
  const manifestFile = byName.get('manifest.json')
  if (!manifestFile) {
    // Nested: path may be sessionId/manifest.json
    const nested = list.find((f) => basename(f.name) === 'manifest.json')
    if (!nested) throw new Error('folder missing manifest.json')
    return loadFromFileMap(groupByDir(list), nested)
  }
  return loadFromFlatList(list)
}

async function loadFromFlatList(list: File[]): Promise<AnalysisPackage> {
  const manifestFile = list.find((f) => basename(f.name) === 'manifest.json')
  if (!manifestFile) throw new Error('folder missing manifest.json')
  const manifest = JSON.parse(await manifestFile.text()) as SessionManifest
  const detectionsFile =
    list.find((f) => basename(f.name) === 'detections.jsonl') ??
    list.find((f) => basename(f.name) === 'assumptions.jsonl')
  const detections = normalizeDetections((await parseJsonl(detectionsFile)) as DetectionEvent[])
  const locationFiles = list
    .filter((f) => /^location-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  const locations: LocationSample[] = []
  for (const file of locationFiles) {
    locations.push(...((await parseJsonl(file)) as LocationSample[]))
  }
  locations.sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  const batteryFiles = list
    .filter((f) => /^battery-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  const battery: BatterySample[] = []
  for (const file of batteryFiles) {
    battery.push(...((await parseJsonl(file)) as BatterySample[]))
  }
  return { manifest, detections, locations, battery: normalizeBattery(battery) }
}

async function loadFromFileMap(
  byDir: Map<string, File[]>,
  manifestFile: File,
): Promise<AnalysisPackage> {
  const dir = dirname(manifestFile.webkitRelativePath || manifestFile.name)
  const siblings = byDir.get(dir) ?? [manifestFile]
  return loadFromFlatList(siblings)
}

function groupByDir(files: File[]): Map<string, File[]> {
  const map = new Map<string, File[]>()
  for (const f of files) {
    const dir = dirname(f.webkitRelativePath || f.name)
    const arr = map.get(dir) ?? []
    arr.push(f)
    map.set(dir, arr)
  }
  return map
}

export function normalizeDetections(raw: DetectionEvent[]): DetectionEvent[] {
  return raw
    .map((event) => ({
      ...event,
      detectorId: event.detectorId ?? 'legacy_assumption',
    }))
    .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
}

export function normalizeBattery(raw: BatterySample[]): BatterySample[] {
  return [...raw]
    .filter((s) => typeof s.level === 'number' && Number.isFinite(s.level) && s.level >= 0)
    .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
}

export async function parseJsonl(file: File | undefined): Promise<unknown[]> {
  if (!file) return []
  const text = await file.text()
  const out: unknown[] = []
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed) continue
    out.push(JSON.parse(trimmed))
  }
  return out
}

export function basename(path: string): string {
  const parts = path.split(/[/\\]/)
  return parts[parts.length - 1] ?? path
}

export function dirname(path: string): string {
  const parts = path.split(/[/\\]/)
  parts.pop()
  return parts.join('/') || '.'
}
