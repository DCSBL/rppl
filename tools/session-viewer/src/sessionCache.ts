import type { AnalysisPackage, TimeRange } from './types'

const DB_NAME = 'rppl-session-viewer'
const STORE = 'kv'
const KEY = 'lastSession'
const DB_VERSION = 1

export interface CachedSession {
  label: string
  package: AnalysisPackage
  window?: TimeRange | null
  playheadMs?: number | null
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onerror = () => reject(req.error ?? new Error('indexedDB open failed'))
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE)
    }
    req.onsuccess = () => resolve(req.result)
  })
}

function normalizePackage(raw: unknown): AnalysisPackage | null {
  if (!raw || typeof raw !== 'object') return null
  const pkg = raw as AnalysisPackage
  if (!pkg.manifest) return null
  return {
    manifest: pkg.manifest,
    detections: pkg.detections ?? [],
    locations: pkg.locations ?? [],
    battery: pkg.battery ?? [],
  }
}

export async function saveCachedSession(entry: CachedSession): Promise<void> {
  const db = await openDb()
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error ?? new Error('indexedDB write failed'))
    tx.objectStore(STORE).put(entry, KEY)
  })
  db.close()
}

export async function loadCachedSession(): Promise<CachedSession | null> {
  const db = await openDb()
  const entry = await new Promise<CachedSession | null>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly')
    const req = tx.objectStore(STORE).get(KEY)
    req.onerror = () => reject(req.error ?? new Error('indexedDB read failed'))
    req.onsuccess = () => {
      const value = req.result as CachedSession | undefined
      if (!value) {
        resolve(null)
        return
      }
      const pkg = normalizePackage(value.package)
      if (!pkg) {
        resolve(null)
        return
      }
      resolve({
        label: value.label,
        package: pkg,
        window: value.window,
        playheadMs: value.playheadMs,
      })
    }
  })
  db.close()
  return entry
}
