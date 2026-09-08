import type {
  AnalysisPackage,
  DetectionEvent,
  SessionManifest,
  SessionTransferPackage,
  TimeRange,
} from './types'
import {
  type RawTransferPackage,
  sliceAnalysisPackage,
  sliceTransferPackage,
} from './exportSlice'
import { decodeMotionFrameBytes } from './motionFrames'
import { basename, dirname, parseJsonl } from './loadSession'

export type ExportSource =
  | { kind: 'json'; file: File }
  | { kind: 'folder'; files: File[] }
  | { kind: 'memory' }

function downloadJson(filename: string, payload: unknown): void {
  // Pretty-print; insertion order keeps `manifest` first when callers build objects that way.
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

function sanitizeLocation(locationName: string | null | undefined): string {
  const trimmed = (locationName ?? '').trim()
  if (!trimmed) return 'unknown'
  const slug = trimmed
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return slug || 'unknown'
}

/** Match phone Share: `rppl_<startedAt>_<location>.json`. */
export function exportFilename(
  pkg: SessionTransferPackage,
  locationName?: string | null,
): string {
  const start = pkg.manifest.startedAt.replace(/[:.]/g, '-')
  const location = sanitizeLocation(locationName)
  return `rppl_${start}_${location}.json`
}

async function filesForSession(files: File[], sessionId: string): Promise<File[]> {
  const manifests = files.filter((f) => basename(f.name) === 'manifest.json')
  for (const manifestFile of manifests) {
    try {
      const manifest = JSON.parse(await manifestFile.text()) as SessionManifest
      if (manifest.sessionId !== sessionId) continue
      const dir = dirname(manifestFile.webkitRelativePath || manifestFile.name)
      return files.filter((f) => dirname(f.webkitRelativePath || f.name) === dir)
    } catch {
      /* skip unreadable manifest */
    }
  }
  return files
}

async function loadRawFromJson(file: File): Promise<RawTransferPackage> {
  const parsed = JSON.parse(await file.text()) as RawTransferPackage & { manifest?: SessionManifest }
  if (!parsed.manifest) throw new Error('export missing manifest')
  return parsed as RawTransferPackage
}

async function jsonlFromMotionFiles(files: File[]): Promise<string> {
  const zlibFiles = files
    .filter((f) => /^motion-\d+\.jsonl\.zlib$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  if (zlibFiles.length) {
    const chunks: string[] = []
    for (const file of zlibFiles) {
      const bytes = new Uint8Array(await file.arrayBuffer())
      chunks.push(await decodeMotionFrameBytes(bytes))
    }
    return chunks.join('')
  }
  const plain = files
    .filter((f) => /^motion-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  const parts: string[] = []
  for (const file of plain) parts.push(await file.text())
  return parts.join('')
}

async function loadRawFromFolder(files: File[], sessionId: string): Promise<RawTransferPackage> {
  const sessionFiles = await filesForSession(files, sessionId)
  const manifestFile = sessionFiles.find((f) => basename(f.name) === 'manifest.json')
  if (!manifestFile) throw new Error('folder missing manifest.json')
  const manifest = JSON.parse(await manifestFile.text()) as SessionManifest
  const detectionsFile =
    sessionFiles.find((f) => basename(f.name) === 'detections.jsonl') ??
    sessionFiles.find((f) => basename(f.name) === 'assumptions.jsonl')
  const detections = (await parseJsonl(detectionsFile)) as DetectionEvent[]
  const locations: unknown[] = []
  const locationFiles = sessionFiles
    .filter((f) => /^location-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  for (const file of locationFiles) locations.push(...(await parseJsonl(file)))
  const health: unknown[] = []
  const healthFiles = sessionFiles
    .filter((f) => /^health-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  for (const file of healthFiles) health.push(...(await parseJsonl(file)))

  const battery: unknown[] = []
  const batteryFiles = sessionFiles
    .filter((f) => /^battery-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  for (const file of batteryFiles) battery.push(...(await parseJsonl(file)))

  const water: unknown[] = []
  const waterFiles = sessionFiles
    .filter((f) => /^water-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  for (const file of waterFiles) water.push(...(await parseJsonl(file)))

  const raw: RawTransferPackage = { manifest, detections, locations, health }
  if (battery.length) raw.battery = battery as RawTransferPackage['battery']
  if (water.length) raw.water = water
  const motionJsonl = await jsonlFromMotionFiles(sessionFiles)
  if (motionJsonl.trim()) raw.motionJsonl = motionJsonl
  else raw.motion = []
  return raw
}

export async function buildWindowExport(
  source: ExportSource,
  pkg: AnalysisPackage,
  range: TimeRange,
): Promise<SessionTransferPackage> {
  if (source.kind === 'json') {
    return sliceTransferPackage(await loadRawFromJson(source.file), range)
  }
  if (source.kind === 'folder') {
    return sliceTransferPackage(await loadRawFromFolder(source.files, pkg.manifest.sessionId), range)
  }
  return sliceAnalysisPackage(pkg, range)
}

export function summarizeExport(sliced: SessionTransferPackage): string {
  const batteryN = sliced.battery?.length ?? 0
  return `${sliced.locations.length} locs · ${sliced.detections.length} detections · ${sliced.health.length} health · ${sliced.motion?.length ?? 0} motion · ${batteryN} battery`
}

export function downloadTransferPackage(sliced: SessionTransferPackage): void {
  downloadJson(exportFilename(sliced), sliced)
}
