import type { AnalysisPackage, AssumptionEvent, LocationSample, SessionManifest } from './types'
import { stripHeavyKeys } from './stripHeavyKeys'

export async function loadExportJson(file: File): Promise<AnalysisPackage> {
  const raw = await file.text()
  const lean = stripHeavyKeys(raw)
  const parsed = JSON.parse(lean) as {
    manifest?: SessionManifest
    assumptions?: AssumptionEvent[]
    locations?: LocationSample[]
  }
  if (!parsed.manifest) throw new Error('export missing manifest')
  return {
    manifest: parsed.manifest,
    assumptions: [...(parsed.assumptions ?? [])].sort(
      (a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp),
    ),
    locations: [...(parsed.locations ?? [])].sort(
      (a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp),
    ),
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
  const assumptions = await parseJsonl(
    list.find((f) => basename(f.name) === 'assumptions.jsonl'),
  ) as AssumptionEvent[]
  const locationFiles = list
    .filter((f) => /^location-\d+\.jsonl$/i.test(basename(f.name)))
    .sort((a, b) => basename(a.name).localeCompare(basename(b.name)))
  const locations: LocationSample[] = []
  for (const file of locationFiles) {
    locations.push(...((await parseJsonl(file)) as LocationSample[]))
  }
  locations.sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  assumptions.sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  return { manifest, assumptions, locations }
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

async function parseJsonl(file: File | undefined): Promise<unknown[]> {
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

function basename(path: string): string {
  const parts = path.split(/[/\\]/)
  return parts[parts.length - 1] ?? path
}

function dirname(path: string): string {
  const parts = path.split(/[/\\]/)
  parts.pop()
  return parts.join('/') || '.'
}
