import type { RadarData, RadarFrame } from './types'

const RADAR_INDEX_URL = 'https://api.rainviewer.com/public/weather-maps.json'

let cachedData: { data: RadarData; ts: number } | null = null
const CACHE_TTL = 5 * 60 * 1000 // 5 min

export async function fetchRadarFrames(): Promise<RadarData> {
  if (cachedData && Date.now() - cachedData.ts < CACHE_TTL) {
    return cachedData.data
  }

  const res = await fetch(RADAR_INDEX_URL)
  if (!res.ok) throw new Error(`RainViewer error: ${res.status}`)
  const json = await res.json()

  const host: string = json.host || 'https://tilecache.rainviewer.com'

  const past: RadarFrame[] = (json.radar?.past || []).map((f: { path: string; time: number }) => ({
    path: f.path,
    time: f.time,
  }))

  const nowcast: RadarFrame[] = (json.radar?.nowcast || []).map((f: { path: string; time: number }) => ({
    path: f.path,
    time: f.time,
  }))

  const data: RadarData = { host, past, nowcast }
  cachedData = { data, ts: Date.now() }
  return data
}

/** Build tile URL for a radar frame */
export function getRadarTileUrl(host: string, frame: RadarFrame): string {
  return `${host}${frame.path}/256/{z}/{x}/{y}/4/1_1.png`
}
