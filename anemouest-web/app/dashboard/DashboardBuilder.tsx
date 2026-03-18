'use client'

import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { useSearchParams } from 'next/navigation'
import { getWindColorDark, degToCompassFR } from '@/lib/utils'
import { API, apiFetch } from '@/lib/api'

// ─── Animated number hook ───
function useAnimatedValue(target: number, duration = 600): number {
  const [display, setDisplay] = useState(target)
  const prev = useRef(target)
  const raf = useRef<number>(0)

  useEffect(() => {
    const from = prev.current
    const to = target
    prev.current = to
    if (from === to) return
    const start = performance.now()
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1)
      const ease = 1 - Math.pow(1 - t, 3) // easeOutCubic
      setDisplay(from + (to - from) * ease)
      if (t < 1) raf.current = requestAnimationFrame(tick)
    }
    raf.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf.current)
  }, [target, duration])

  return display
}

// ─── Animated station values wrapper ───
function AnimatedStation({ wind, gust, direction, temperature, scale, isLarge, isTall, ts, source }: {
  wind: number; gust: number; direction: number; temperature?: number
  scale: number; isLarge: boolean; isTall: boolean; ts?: string; source: string
}) {
  const aWind = useAnimatedValue(wind)
  const aGust = useAnimatedValue(gust)
  const aDir = useAnimatedValue(direction)
  const aTemp = useAnimatedValue(temperature ?? 0)
  const compass = degToCompassFR(Math.round(aDir))

  return (
    <>
      {/* Big arrow — dead center, large */}
      <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', zIndex: 0 }}>
        <svg width={Math.round(scale * 40)} height={Math.round(scale * 40)} viewBox="0 0 24 24" style={{ transform: `rotate(${Math.round(aDir) + 180}deg)`, transition: 'transform 0.5s ease', filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.3))' }}>
          <path d="M12 2L6 18l6-4 6 4z" fill="#fff" />
        </svg>
        <span style={{ fontSize: Math.round(scale * 8), fontWeight: 900, color: '#fff', marginTop: 2, letterSpacing: 0.5 }}>{compass}</span>
      </div>
      {/* Middle — temp */}
      {temperature !== undefined && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <span style={{ fontSize: Math.round(scale * 12), fontWeight: 800, color: 'rgba(255,255,255,0.55)', fontVariantNumeric: 'tabular-nums' }}>{Math.round(aTemp)}°C</span>
        </div>
      )}
      {/* Bottom — vent / rafale + EN DIRECT */}
      <div>
        <div style={{ display: 'flex', alignItems: 'flex-end' }}>
          <div>
            <div style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.35)', textTransform: 'uppercase', letterSpacing: 1, marginBottom: 2 }}>Vent</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 2 }}>
              <span style={{ fontSize: Math.round(scale * 26), fontWeight: 900, color: '#fff', fontVariantNumeric: 'tabular-nums', lineHeight: 1, textShadow: '0 2px 8px rgba(0,0,0,0.15)' }}>{Math.round(aWind)}</span>
              <span style={{ fontSize: Math.round(scale * 7), fontWeight: 700, color: 'rgba(255,255,255,0.4)' }}>nds</span>
            </div>
          </div>
          <div style={{ marginLeft: 'auto', textAlign: 'right' }}>
            <div style={{ fontSize: 11, fontWeight: 800, color: 'rgba(255,255,255,0.5)', textTransform: 'uppercase', letterSpacing: 1, marginBottom: 2 }}>Rafale</div>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'flex-end', gap: 2 }}>
              <span style={{ fontSize: Math.round(scale * 26), fontWeight: 900, color: 'rgba(255,255,255,0.7)', fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{Math.round(aGust)}</span>
              <span style={{ fontSize: Math.round(scale * 7), fontWeight: 700, color: 'rgba(255,255,255,0.25)' }}>nds</span>
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: isTall ? 8 : 5 }}>
          <span style={{ width: 5, height: 5, borderRadius: '50%', background: '#34c759', flexShrink: 0 }} className="animate-pulse" />
          <span style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.35)' }}>EN DIRECT</span>
        </div>
      </div>
    </>
  )
}

// ─── Animated buoy values wrapper ───
function AnimatedBuoy({ hm0, hmax, tp, direction, seaTemp, scale, isLarge, isTall, isDark, accentColor, textPrimary, textSecondary, textMuted, label }: {
  hm0: number; hmax: number; tp: number; direction: number; seaTemp: number
  scale: number; isLarge: boolean; isTall: boolean; isDark: boolean
  accentColor: string; textPrimary: string; textSecondary: string; textMuted: string; label: string
}) {
  const aHm0 = useAnimatedValue(hm0)
  const aHmax = useAnimatedValue(hmax)
  const aTp = useAnimatedValue(tp)
  const aDir = useAnimatedValue(direction)
  const aTemp = useAnimatedValue(seaTemp)

  return (
    <>
      <div style={{ position: 'relative', zIndex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: isLarge ? 15 : 13, fontWeight: 800, color: textPrimary, lineHeight: 1.2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</div>
            <div style={{ fontSize: 10, fontWeight: 600, color: textMuted, marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.8 }}>Houle</div>
          </div>
        </div>
      </div>
      <div style={{ position: 'relative', zIndex: 1 }}>
        {/* Main value + direction */}
        <div style={{ display: 'flex', alignItems: 'center', gap: isLarge ? 14 : 8 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
            <span style={{ fontSize: Math.round(scale * 24), fontWeight: 900, color: accentColor, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{aHm0.toFixed(1)}</span>
            <span style={{ fontSize: Math.round(scale * 7), fontWeight: 700, color: textSecondary }}>m</span>
          </div>
          {direction > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <svg width={Math.round(scale * 14)} height={Math.round(scale * 14)} viewBox="0 0 24 24" style={{ transform: `rotate(${Math.round(aDir) + 180}deg)`, transition: 'transform 0.3s ease', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.2))' }}>
                <path d="M12 2L6 18l6-4 6 4z" fill={accentColor} />
              </svg>
              <span style={{ fontSize: Math.round(scale * 8), fontWeight: 900, color: textPrimary, opacity: 0.7 }}>{degToCompassFR(Math.round(aDir))}</span>
            </div>
          )}
        </div>
        {/* Secondary values */}
        <div style={{ display: 'flex', gap: isLarge ? 12 : 8, marginTop: isTall ? 10 : 6, flexWrap: 'wrap' }}>
          <div style={{ padding: `${isTall ? 6 : 4}px ${isTall ? 10 : 8}px`, borderRadius: 10, background: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)' }}>
            <div style={{ fontSize: Math.round(scale * 5), fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 0.8 }}>Tp</div>
            <div style={{ fontSize: Math.round(scale * 12), fontWeight: 900, color: textPrimary, opacity: 0.75, fontVariantNumeric: 'tabular-nums', lineHeight: 1, marginTop: 1 }}>{Math.round(aTp)}<span style={{ fontSize: Math.round(scale * 5.5), color: textSecondary, fontWeight: 600 }}>s</span></div>
          </div>
          <div style={{ padding: `${isTall ? 6 : 4}px ${isTall ? 10 : 8}px`, borderRadius: 10, background: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)' }}>
            <div style={{ fontSize: Math.round(scale * 5), fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 0.8 }}>Hmax</div>
            <div style={{ fontSize: Math.round(scale * 12), fontWeight: 900, color: textPrimary, opacity: 0.75, fontVariantNumeric: 'tabular-nums', lineHeight: 1, marginTop: 1 }}>{aHmax.toFixed(1)}<span style={{ fontSize: Math.round(scale * 5.5), color: textSecondary, fontWeight: 600 }}>m</span></div>
          </div>
          {direction > 0 && <div style={{ padding: `${isTall ? 6 : 4}px ${isTall ? 10 : 8}px`, borderRadius: 10, background: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)' }}>
            <div style={{ fontSize: Math.round(scale * 5), fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 0.8 }}>Dir</div>
            <div style={{ fontSize: Math.round(scale * 12), fontWeight: 900, color: textPrimary, opacity: 0.75, fontVariantNumeric: 'tabular-nums', lineHeight: 1, marginTop: 1 }}>{Math.round(aDir)}°</div>
          </div>}
          {seaTemp > 0 && <div style={{ padding: `${isTall ? 6 : 4}px ${isTall ? 10 : 8}px`, borderRadius: 10, background: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)' }}>
            <div style={{ fontSize: Math.round(scale * 5), fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 0.8 }}>Mer</div>
            <div style={{ fontSize: Math.round(scale * 12), fontWeight: 900, color: '#ff9500', opacity: 0.85, fontVariantNumeric: 'tabular-nums', lineHeight: 1, marginTop: 1 }}>{Math.round(aTemp)}<span style={{ fontSize: Math.round(scale * 5.5), color: textSecondary, fontWeight: 600 }}>°</span></div>
          </div>}
        </div>
      </div>
    </>
  )
}

const ALL_SOURCES = ['meteofrance', 'gowind', 'pioupiou', 'netatmo', 'ffvl', 'windcornouaille', 'ndbc', 'diabox']

// ─── Types ───

export type DashboardStyle = 'glass' | 'dark' | 'ocean'

export interface DashboardWidget {
  id: string
  type: 'station' | 'webcam' | 'buoy' | 'clock' | 'title'
  dataId: string
  label: string
  // Pixel-based positioning (absolute within container)
  x: number; y: number; w: number; h: number
}

export interface DashboardConfig {
  name: string
  style: DashboardStyle
  columns: number
  refreshInterval: number
  widgets: DashboardWidget[]
  pixelMode?: boolean // true = pixel-based positioning
}

interface AvailableItem { id: string; name: string; type: 'station' | 'webcam' | 'buoy'; source?: string; location?: string }
interface StationData { id: string; stableId: string; name: string; wind: number; gust: number; direction: number; source: string; temperature?: number; ts?: string }
interface BuoyData { id: string; name: string; hm0: number; hmax: number; tp: number; direction: number; seaTemp: number }
interface WebcamData { id: string; name: string; location: string; imageUrl: string; streamUrl?: string | null }

const SNAP_SIZE = 20 // snap grid in pixels
const DEFAULT_WIDGET_SIZES: Record<string, { w: number; h: number }> = {
  station: { w: 280, h: 160 },
  webcam: { w: 340, h: 240 },
  buoy: { w: 280, h: 160 },
  clock: { w: 240, h: 140 },
  title: { w: 600, h: 50 },
}
const DEFAULT_CONFIG: DashboardConfig = { name: 'Mon Dashboard', style: 'dark', columns: 12, refreshInterval: 60, widgets: [], pixelMode: true }

function encodeConfig(cfg: DashboardConfig): string { return btoa(unescape(encodeURIComponent(JSON.stringify(cfg)))) }
function decodeConfig(str: string): DashboardConfig | null { try { return JSON.parse(decodeURIComponent(escape(atob(str)))) } catch { return null } }

/** Migrate old grid-based configs to pixel-based */
function migrateConfig(cfg: DashboardConfig): DashboardConfig {
  if (cfg.pixelMode) return cfg
  // Old grid: x/w in columns (12-col), y/h in rows (60px each), gap 14px
  const colW = 100 // approximate column width in pixels
  const rowH = 60
  const gap = 14
  return {
    ...cfg,
    pixelMode: true,
    widgets: cfg.widgets.map(w => ({
      ...w,
      x: w.x * (colW + gap),
      y: w.y * (rowH + gap),
      w: w.w * colW + (w.w - 1) * gap,
      h: w.h * rowH + (w.h - 1) * gap,
    })),
  }
}
function genId(): string { return Math.random().toString(36).slice(2, 9) }
function nextY(widgets: DashboardWidget[]): number { return widgets.length === 0 ? 0 : Math.max(...widgets.map(w => w.y + w.h)) + 20 }

// ─── Webcam HLS Widget ───

function DashboardWebcam({ webcam, label, imgUrl, isDark, lastUpdate }: {
  webcam: WebcamData | undefined; label: string; imgUrl: string | null; isDark: boolean; lastUpdate: Date
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<any>(null)
  const [streaming, setStreaming] = useState(false)
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null)
  const hasStream = !!webcam?.streamUrl

  useEffect(() => {
    if (!streaming || !webcam?.streamUrl || !videoRef.current) return
    let hls: any = null
    let timeout: ReturnType<typeof setTimeout>
    const fallback = () => { setStreaming(false) }
    // Timeout: if no playback within 8s, revert to image
    timeout = setTimeout(fallback, 8000)
    const clearT = () => clearTimeout(timeout)

    const setup = async () => {
      const Hls = (await import('hls.js')).default
      if (!Hls.isSupported() || !videoRef.current) { fallback(); return }
      hls = new Hls({ enableWorker: true, lowLatencyMode: true })
      hls.loadSource(webcam.streamUrl!)
      hls.attachMedia(videoRef.current)
      hls.on(Hls.Events.MANIFEST_PARSED, () => { clearT(); videoRef.current?.play().catch(fallback) })
      hls.on(Hls.Events.ERROR, (_: any, data: any) => { if (data.fatal) fallback() })
      hlsRef.current = hls
    }
    if (videoRef.current.canPlayType('application/vnd.apple.mpegurl')) {
      videoRef.current.src = webcam.streamUrl
      videoRef.current.onplaying = clearT
      videoRef.current.onerror = fallback
      videoRef.current.play().catch(fallback)
    } else { setup() }
    return () => { clearT(); hls?.destroy(); hlsRef.current = null }
  }, [streaming, webcam?.streamUrl])

  return (
    <div style={{ height: '100%', borderRadius: 20, overflow: 'hidden', position: 'relative', background: isDark ? '#111' : '#e5e5ea' }}>
      {/* Previous loaded image (stays visible during reload) */}
      {!streaming && loadedUrl && (
        <img src={loadedUrl} alt="" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', zIndex: 0 }} />
      )}
      {/* Loading spinner — only on first load */}
      {!loadedUrl && !streaming && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 2 }}>
          <div className="w-7 h-7 border-[2.5px] border-white/15 border-t-[#af52de] rounded-full animate-spin" />
        </div>
      )}

      {streaming ? (
        <video ref={videoRef} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', position: 'relative', zIndex: 1 }} autoPlay muted playsInline />
      ) : imgUrl ? (
        <img src={imgUrl} alt={label} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', position: 'relative', zIndex: 1 }}
          onLoad={(e) => setLoadedUrl((e.target as HTMLImageElement).src)} onError={() => {}} />
      ) : null}

      {/* Gradient overlay */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '28px 14px 10px', background: 'linear-gradient(to top, rgba(0,0,0,0.8) 0%, rgba(0,0,0,0.3) 60%, transparent 100%)', zIndex: 3 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <div>
            <div style={{ fontSize: 15, fontWeight: 800, color: '#fff', textShadow: '0 1px 4px rgba(0,0,0,0.4)' }}>{label}</div>
            {webcam?.location && <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', marginTop: 1 }}>{webcam.location}</div>}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            {streaming ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '2px 8px', borderRadius: 10, background: 'rgba(255,59,48,0.85)' }}>
                <span style={{ width: 5, height: 5, borderRadius: '50%', background: '#fff' }} className="animate-pulse" />
                <span style={{ fontSize: 9, fontWeight: 800, color: '#fff', letterSpacing: 1 }}>LIVE</span>
              </div>
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <span style={{ width: 4, height: 4, borderRadius: '50%', background: '#34c759' }} className="animate-pulse" />
                <span style={{ fontSize: 10, fontWeight: 600, color: 'rgba(255,255,255,0.45)' }}>
                  {lastUpdate.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Stream toggle button */}
      {hasStream && (
        <button onClick={(e) => { e.stopPropagation(); setStreaming(!streaming) }}
          style={{
            position: 'absolute', top: 8, right: 8, zIndex: 10,
            width: 34, height: 34, borderRadius: '50%',
            background: streaming ? 'rgba(255,59,48,0.9)' : 'rgba(0,0,0,0.5)',
            backdropFilter: 'blur(8px)',
            border: '1.5px solid rgba(255,255,255,0.2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', transition: 'all 0.2s',
          }}>
          {streaming ? (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="#fff"><rect x="6" y="4" width="4" height="16" rx="1" /><rect x="14" y="4" width="4" height="16" rx="1" /></svg>
          ) : (
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z" /></svg>
          )}
        </button>
      )}
    </div>
  )
}

// ─── Helper: relative time ───
function relativeTimeShort(ts: string): string {
  const diff = Math.floor((Date.now() - new Date(ts).getTime()) / 60000)
  if (diff < 1) return "à l'instant"
  if (diff < 60) return `${diff} min`
  if (diff < 1440) return `${Math.floor(diff / 60)}h`
  return `${Math.floor(diff / 1440)}j`
}

// ─── Main ───

export function DashboardBuilder() {
  const params = useSearchParams()
  const isTV = params.get('view') === '1'
  const configParam = params.get('config')

  const [config, setConfig] = useState<DashboardConfig>(() => {
    if (configParam) { const d = decodeConfig(configParam); if (d) return migrateConfig(d) }
    if (typeof window !== 'undefined') { const s = localStorage.getItem('anemouest-dashboard'); if (s) try { return migrateConfig(JSON.parse(s)) } catch {} }
    return DEFAULT_CONFIG
  })

  const [editing, setEditing] = useState(!isTV)
  const [stations, setStations] = useState<AvailableItem[]>([])
  const [webcams, setWebcams] = useState<AvailableItem[]>([])
  const [buoys, setBuoys] = useState<AvailableItem[]>([])
  const [stationMap, setStationMap] = useState<Record<string, StationData>>({})
  const [buoyMap, setBuoyMap] = useState<Record<string, BuoyData>>({})
  const [webcamMap, setWebcamMap] = useState<Record<string, WebcamData>>({})
  const [clock, setClock] = useState(new Date())
  const [lastUpdate, setLastUpdate] = useState(new Date())
  const [imgTick, setImgTick] = useState(0)
  const [search, setSearch] = useState('')
  const [addPanel, setAddPanel] = useState<'station' | 'webcam' | 'buoy' | null>(null)
  const [copied, setCopied] = useState(false)
  const [showSettings, setShowSettings] = useState(false)

  // Drag & resize state
  const [dragId, setDragId] = useState<string | null>(null)
  const [resizeId, setResizeId] = useState<string | null>(null)
  const gridRef = useRef<HTMLDivElement>(null)
  const interactionStart = useRef({ mx: 0, my: 0, ox: 0, oy: 0, ow: 0, oh: 0 })

  // Save
  useEffect(() => { localStorage.setItem('anemouest-dashboard', JSON.stringify(config)) }, [config])

  // Clock
  useEffect(() => { const i = setInterval(() => setClock(new Date()), 1000); return () => clearInterval(i) }, [])

  // Fetch catalog (for add panel)
  useEffect(() => {
    if (!editing) return
    const f = async () => {
      const all: AvailableItem[] = []
      await Promise.all(ALL_SOURCES.map(async src => {
        try { const r = await apiFetch(`${API}/${src}`); if (!r.ok) return; const d = await r.json(); (d.stations || []).forEach((s: any) => all.push({ id: s.stableId || s.id, name: s.name, type: 'station', source: s.source || src })) } catch {}
      }))
      setStations(all.sort((a, b) => a.name.localeCompare(b.name)))
      try { const r = await apiFetch(`${API}/webcams`); if (r.ok) { const d = await r.json(); setWebcams(d.map((w: any) => ({ id: w.id, name: w.name || w.location, type: 'webcam' as const, source: w.source, location: w.location }))) } } catch {}
      try { const r = await apiFetch(`${API}/candhis`); if (r.ok) { const d = await r.json(); setBuoys((d.buoys || d || []).map((b: any) => ({ id: b.id, name: b.name, type: 'buoy' as const }))) } } catch {}
    }
    f()
  }, [editing])

  // Fetch live data
  const fetchData = useCallback(async () => {
    const ns = config.widgets.filter(w => w.type === 'station').map(w => w.dataId)
    const nb = config.widgets.filter(w => w.type === 'buoy').map(w => w.dataId)
    const nw = config.widgets.filter(w => w.type === 'webcam').map(w => w.dataId)
    const ps: Promise<void>[] = []
    if (ns.length) { ps.push(Promise.all(ALL_SOURCES.map(s => apiFetch(`${API}/${s}`).then(r => r.ok ? r.json() : { stations: [] }).catch(() => ({ stations: [] })))).then(results => { const m: Record<string, StationData> = {}; for (const d of results) for (const s of (d.stations || [])) { const sid = s.stableId || s.id; if (ns.includes(sid) || ns.includes(s.id)) { m[sid] = s; m[s.id] = s } }; setStationMap(m) })) }
    if (nb.length) { ps.push(apiFetch(`${API}/candhis`).then(r => r.json()).then(d => { const m: Record<string, BuoyData> = {}; for (const b of (d.buoys || d || [])) if (nb.includes(b.id)) m[b.id] = b; setBuoyMap(m) }).catch(() => {})) }
    if (nw.length) { ps.push(apiFetch(`${API}/webcams`).then(r => r.json()).then(d => { const m: Record<string, WebcamData> = {}; for (const w of d) if (nw.includes(w.id)) m[w.id] = { id: w.id, name: w.name, location: w.location, imageUrl: w.imageUrl, streamUrl: w.streamUrl }; setWebcamMap(m) }).catch(() => {})) }
    await Promise.all(ps)
    setLastUpdate(new Date())
    setImgTick(t => t + 1)
  }, [config.widgets])

  useEffect(() => {
    fetchData()
    const i = setInterval(fetchData, Math.max(30, config.refreshInterval) * 1000)
    return () => clearInterval(i)
  }, [fetchData, config.refreshInterval])

  // ── Snap helper ──
  const snap = (v: number) => Math.round(v / SNAP_SIZE) * SNAP_SIZE

  // ── Drag (pixel-based free position) ──
  const startDrag = (e: React.MouseEvent | React.TouchEvent, id: string) => {
    if (!editing) return
    e.preventDefault()
    const w = config.widgets.find(x => x.id === id)
    if (!w) return
    const pt = 'touches' in e ? e.touches[0] : e
    interactionStart.current = { mx: pt.clientX, my: pt.clientY, ox: w.x, oy: w.y, ow: w.w, oh: w.h }
    setDragId(id)
  }

  useEffect(() => {
    if (!dragId) return
    const move = (e: MouseEvent | TouchEvent) => {
      const pt = 'touches' in e ? e.touches[0] : e
      const dx = pt.clientX - interactionStart.current.mx
      const dy = pt.clientY - interactionStart.current.my
      const nx = snap(Math.max(0, interactionStart.current.ox + dx))
      const ny = snap(Math.max(0, interactionStart.current.oy + dy))
      const w = config.widgets.find(x => x.id === dragId)
      if (!w) return
      if (w.x !== nx || w.y !== ny) setConfig(p => ({ ...p, widgets: p.widgets.map(x => x.id === dragId ? { ...x, x: nx, y: ny } : x) }))
    }
    const end = () => setDragId(null)
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end)
    window.addEventListener('touchmove', move); window.addEventListener('touchend', end)
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end) }
  }, [dragId, config.widgets])

  // ── Resize (pixel-based free) ──
  const startResize = (e: React.MouseEvent | React.TouchEvent, id: string) => {
    if (!editing) return
    e.preventDefault(); e.stopPropagation()
    const w = config.widgets.find(x => x.id === id)
    if (!w) return
    const pt = 'touches' in e ? e.touches[0] : e
    interactionStart.current = { mx: pt.clientX, my: pt.clientY, ox: w.x, oy: w.y, ow: w.w, oh: w.h }
    setResizeId(id)
  }

  useEffect(() => {
    if (!resizeId) return
    const move = (e: MouseEvent | TouchEvent) => {
      const pt = 'touches' in e ? e.touches[0] : e
      const dx = pt.clientX - interactionStart.current.mx
      const dy = pt.clientY - interactionStart.current.my
      const nw = snap(Math.max(80, interactionStart.current.ow + dx))
      const nh = snap(Math.max(50, interactionStart.current.oh + dy))
      const w = config.widgets.find(x => x.id === resizeId)
      if (!w) return
      if (w.w !== nw || w.h !== nh) setConfig(p => ({ ...p, widgets: p.widgets.map(x => x.id === resizeId ? { ...x, w: nw, h: nh } : x) }))
    }
    const end = () => setResizeId(null)
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end)
    window.addEventListener('touchmove', move); window.addEventListener('touchend', end)
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end) }
  }, [resizeId, config.widgets])

  // ── Add widget ──
  const addWidget = (item: AvailableItem) => {
    const s = DEFAULT_WIDGET_SIZES[item.type] || { w: 280, h: 160 }
    setConfig(p => ({ ...p, widgets: [...p.widgets, { id: genId(), type: item.type, dataId: item.id, label: item.name, x: 0, y: nextY(p.widgets), w: s.w, h: s.h }] }))
    setAddPanel(null)
  }

  const addSpecial = (type: 'clock' | 'title') => {
    const s = DEFAULT_WIDGET_SIZES[type] || { w: 240, h: 140 }
    setConfig(p => ({ ...p, widgets: [...p.widgets, { id: genId(), type, dataId: '', label: type === 'clock' ? 'Horloge' : 'Mon titre', x: 0, y: nextY(p.widgets), w: s.w, h: s.h }] }))
  }

  const removeWidget = (id: string) => setConfig(p => ({ ...p, widgets: p.widgets.filter(w => w.id !== id) }))

  const filterItems = (items: AvailableItem[]) => {
    if (!search.trim()) return items.slice(0, 50)
    const q = search.toLowerCase()
    return items.filter(i => i.name.toLowerCase().includes(q) || i.source?.toLowerCase().includes(q) || i.location?.toLowerCase().includes(q)).slice(0, 50)
  }

  const shareUrl = typeof window !== 'undefined' ? `${window.location.origin}/dashboard?view=1&config=${encodeConfig(config)}` : ''

  // ── Style vars ──
  const isDark = config.style === 'dark' || config.style === 'ocean'
  const bg = config.style === 'dark' ? '#1a1a2e' : config.style === 'ocean' ? '#0c1929' : '#f2f2f7'
  const cardBg = config.style === 'dark' ? 'rgba(30,30,50,0.85)' : config.style === 'ocean' ? 'rgba(15,35,60,0.85)' : 'rgba(255,255,255,0.7)'
  const cardBorder = config.style === 'dark' ? '1px solid rgba(255,255,255,0.06)' : config.style === 'ocean' ? '1px solid rgba(100,180,255,0.15)' : '1px solid rgba(255,255,255,0.5)'
  const textPrimary = isDark ? '#fff' : '#1c1c1e'
  const textSecondary = isDark ? 'rgba(255,255,255,0.5)' : '#8e8e93'
  const textMuted = isDark ? 'rgba(255,255,255,0.3)' : '#c7c7cc'

  // ── Render widget content ──
  const renderWidget = (widget: DashboardWidget) => {
    const isLarge = widget.w >= 200
    const isTall = widget.h >= 180
    const isXL = widget.w >= 350 || (widget.w >= 250 && widget.h >= 250)
    // Scale factor: bigger widget = bigger text (pixel-based)
    const scale = Math.min(widget.w / 100, 4) * 0.5 + Math.min(widget.h / 80, 6) * 0.25

    if (widget.type === 'title') return (
      <div style={{ height: '100%', display: 'flex', alignItems: 'flex-end', padding: '0 4px 6px' }}>
        <div style={{ fontSize: isLarge ? 28 : 22, fontWeight: 900, color: textPrimary, letterSpacing: '-0.5px' }}>{widget.label}</div>
      </div>
    )

    if (widget.type === 'clock') return (
      <div style={{ height: '100%', background: cardBg, border: cardBorder, borderRadius: 20, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(20px)', position: 'relative', overflow: 'hidden' }}>
        {/* Subtle decorative ring */}
        <div style={{ position: 'absolute', width: isLarge ? 160 : 120, height: isLarge ? 160 : 120, borderRadius: '50%', border: `2px solid ${isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)'}` }} />
        <div style={{ fontSize: isLarge ? 60 : 40, fontWeight: 900, color: textPrimary, fontVariantNumeric: 'tabular-nums', lineHeight: 1, position: 'relative' }}>
          {clock.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
          <span style={{ fontSize: isLarge ? 20 : 14, fontWeight: 600, color: textMuted, marginLeft: 2 }}>
            {clock.toLocaleTimeString('fr-FR', { second: '2-digit' }).slice(-2)}
          </span>
        </div>
        <div style={{ fontSize: isLarge ? 15 : 12, fontWeight: 600, color: textSecondary, marginTop: 6, textTransform: 'capitalize', position: 'relative' }}>
          {clock.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
        </div>
      </div>
    )

    if (widget.type === 'station') {
      const s = stationMap[widget.dataId]
      if (!s) return <div style={{ height: '100%', background: cardBg, border: cardBorder, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(20px)' }}><div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" /></div>
      const wcDark = getWindColorDark(s.wind)
      return (
        <div style={{ height: '100%', background: `linear-gradient(145deg, ${wcDark}, ${wcDark}bb)`, borderRadius: 20, overflow: 'hidden', position: 'relative' }}>
          <div style={{ height: '100%', padding: isLarge ? 22 : 14, background: 'rgba(255,255,255,0.04)', display: 'flex', flexDirection: 'column', justifyContent: 'space-between', position: 'relative', zIndex: 1 }}>
            {/* Source — bottom right */}
            <div style={{ position: 'absolute', bottom: isLarge ? 10 : 6, right: isLarge ? 14 : 10, fontSize: 8, fontWeight: 600, color: 'rgba(255,255,255,0.2)', textTransform: 'uppercase', letterSpacing: 0.8 }}>{s.source}</div>
            {/* Header */}
            <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: Math.round(scale * 10), fontWeight: 800, color: '#fff', lineHeight: 1.2 }}>{widget.label}</div>
            {/* Animated values */}
            <AnimatedStation wind={s.wind} gust={s.gust} direction={s.direction ?? 0} temperature={s.temperature} scale={scale} isLarge={isLarge} isTall={isTall} ts={s.ts} source={s.source} />
          </div>
        </div>
      )
    }

    if (widget.type === 'buoy') {
      const b = buoyMap[widget.dataId]
      if (!b) return <div style={{ height: '100%', background: cardBg, border: cardBorder, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(20px)' }}><div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" /></div>
      const accentColor = config.style === 'ocean' ? '#0ea5e9' : '#007aff'
      const buoyBg = isDark
        ? `linear-gradient(145deg, rgba(0,${Math.min(120, Math.round(b.hm0 * 40))},${Math.min(180, Math.round(b.hm0 * 60))},0.3), ${cardBg})`
        : cardBg
      return (
        <div style={{ height: '100%', background: buoyBg, border: cardBorder, borderRadius: 20, padding: isLarge ? 22 : 14, backdropFilter: 'blur(20px)', display: 'flex', flexDirection: 'column', justifyContent: 'space-between', position: 'relative', overflow: 'hidden' }}>
          {/* Animated wave — two layers undulating */}
          <svg style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: '33%', opacity: 0.08 }} viewBox="0 0 400 60" preserveAspectRatio="none">
            <path fill={accentColor} opacity="0.6">
              <animate attributeName="d"
                values="M0 35 C40 20 80 45 120 30 S200 15 240 30 S320 45 360 30 S400 20 400 30 V60 H0 Z;M0 30 C40 45 80 20 120 35 S200 45 240 30 S320 15 360 35 S400 45 400 30 V60 H0 Z;M0 35 C40 20 80 45 120 30 S200 15 240 30 S320 45 360 30 S400 20 400 30 V60 H0 Z"
                dur="7s" repeatCount="indefinite" />
            </path>
            <path fill={accentColor}>
              <animate attributeName="d"
                values="M0 38 C50 28 100 48 150 35 S250 22 300 38 S380 48 400 35 V60 H0 Z;M0 32 C50 45 100 25 150 38 S250 48 300 32 S380 22 400 38 V60 H0 Z;M0 38 C50 28 100 48 150 35 S250 22 300 38 S380 48 400 35 V60 H0 Z"
                dur="5s" repeatCount="indefinite" />
            </path>
          </svg>
          <AnimatedBuoy hm0={b.hm0} hmax={b.hmax} tp={b.tp} direction={b.direction} seaTemp={b.seaTemp}
            scale={scale} isLarge={isLarge} isTall={isTall} isDark={isDark}
            accentColor={accentColor} textPrimary={textPrimary} textSecondary={textSecondary} textMuted={textMuted} label={widget.label} />
        </div>
      )
    }

    if (widget.type === 'webcam') {
      const w = webcamMap[widget.dataId]
      const imgUrl = w ? `${API}/webcam-image?id=${encodeURIComponent(w.id)}&redirect=true&t=${imgTick}` : null
      return <DashboardWebcam webcam={w} label={widget.label} imgUrl={imgUrl} isDark={isDark} lastUpdate={lastUpdate} />
    }
    return null
  }

  return (
    <div style={{ minHeight: '100vh', background: bg, fontFamily: "-apple-system, 'SF Pro Display', BlinkMacSystemFont, sans-serif", WebkitFontSmoothing: 'antialiased' }}>

      {/* ── Floating toolbar (edit mode) ── */}
      {editing && (
        <div className="fixed top-3 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 px-3 py-2 rounded-2xl shadow-2xl" style={{ background: 'rgba(0,0,0,0.8)', backdropFilter: 'blur(24px)', border: '1px solid rgba(255,255,255,0.08)' }}>
          {(['station', 'webcam', 'buoy'] as const).map(t => (
            <button key={t} onClick={() => setAddPanel(addPanel === t ? null : t)}
              className={`px-3 py-1.5 rounded-xl text-[12px] font-bold transition active:scale-95 ${addPanel === t ? 'bg-[#007aff] text-white' : 'bg-white/10 text-white/80 hover:bg-white/20'}`}>
              + {t === 'station' ? 'Station' : t === 'webcam' ? 'Webcam' : 'Bouee'}
            </button>
          ))}
          <button onClick={() => addSpecial('clock')} className="px-3 py-1.5 rounded-xl text-[12px] font-bold bg-white/10 text-white/80 hover:bg-white/20 transition active:scale-95">Horloge</button>
          <button onClick={() => addSpecial('title')} className="px-3 py-1.5 rounded-xl text-[12px] font-bold bg-white/10 text-white/80 hover:bg-white/20 transition active:scale-95">Titre</button>
          <div className="w-px h-6 bg-white/15 mx-0.5" />
          <button onClick={() => setShowSettings(!showSettings)}
            className={`px-3 py-1.5 rounded-xl text-[12px] font-bold transition active:scale-95 ${showSettings ? 'bg-[#007aff] text-white' : 'bg-white/10 text-white/80 hover:bg-white/20'}`}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24"><path strokeLinecap="round" d="M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75" /></svg>
          </button>
          <button onClick={() => { navigator.clipboard.writeText(shareUrl); setCopied(true); setTimeout(() => setCopied(false), 2000) }}
            className={`px-3 py-1.5 rounded-xl text-[12px] font-bold transition active:scale-95 ${copied ? 'bg-[#34c759] text-white' : 'bg-white/10 text-white/80 hover:bg-white/20'}`}>
            {copied ? 'Copie !' : 'Lien TV'}
          </button>
          <button onClick={() => { setEditing(false); setAddPanel(null); setShowSettings(false) }}
            className="px-3 py-1.5 rounded-xl text-[12px] font-bold bg-[#34c759] text-white transition active:scale-95">OK</button>
        </div>
      )}

      {/* ── Add panel dropdown ── */}
      {editing && addPanel && (
        <div className="fixed top-16 left-1/2 -translate-x-1/2 z-50 w-80 rounded-2xl shadow-2xl p-3 overflow-hidden" style={{ background: 'rgba(0,0,0,0.88)', backdropFilter: 'blur(24px)', border: '1px solid rgba(255,255,255,0.06)' }}>
          <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher..." autoFocus
            className="w-full px-3 py-2 rounded-xl bg-white/10 border border-white/10 text-[13px] text-white outline-none focus:border-[#007aff] transition mb-2 placeholder-white/30" />
          <div className="max-h-52 overflow-auto space-y-0.5">
            {filterItems(addPanel === 'station' ? stations : addPanel === 'webcam' ? webcams : buoys).map(item => (
              <button key={item.id} onClick={() => addWidget(item)}
                className="w-full text-left px-3 py-2 rounded-xl hover:bg-white/10 transition flex items-center justify-between">
                <div>
                  <div className="text-[13px] font-semibold text-white">{item.name}</div>
                  <div className="text-[10px] text-white/40">{[item.location, item.source].filter(Boolean).join(' · ')}</div>
                </div>
                <svg className="w-4 h-4 text-[#007aff]" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M12 4v16m8-8H4" /></svg>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ── Settings panel ── */}
      {editing && showSettings && (
        <div className="fixed top-16 right-4 z-50 w-72 rounded-2xl shadow-2xl p-4" style={{ background: 'rgba(0,0,0,0.88)', backdropFilter: 'blur(24px)', border: '1px solid rgba(255,255,255,0.06)' }}>
          <div className="space-y-3">
            <div>
              <label className="text-[10px] font-bold text-white/40 uppercase tracking-wider block mb-1">Nom</label>
              <input type="text" value={config.name} onChange={e => setConfig(p => ({ ...p, name: e.target.value }))}
                className="w-full px-3 py-2 rounded-xl bg-white/10 border border-white/10 text-[13px] text-white outline-none focus:border-[#007aff]" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-white/40 uppercase tracking-wider block mb-1">Theme</label>
              <div className="flex gap-1">
                {(['glass', 'dark', 'ocean'] as const).map(s => (
                  <button key={s} onClick={() => setConfig(p => ({ ...p, style: s }))}
                    className={`flex-1 py-1.5 rounded-lg text-[12px] font-bold transition ${config.style === s ? 'bg-[#007aff] text-white' : 'bg-white/10 text-white/60'}`}>
                    {s === 'glass' ? 'Clair' : s === 'dark' ? 'Sombre' : 'Ocean'}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="text-[10px] font-bold text-white/40 uppercase tracking-wider block mb-1">Refresh</label>
              <div className="flex gap-1">
                {[30, 60, 120, 300].map(r => (
                  <button key={r} onClick={() => setConfig(p => ({ ...p, refreshInterval: r }))}
                    className={`flex-1 py-1.5 rounded-lg text-[12px] font-bold transition ${config.refreshInterval === r ? 'bg-[#007aff] text-white' : 'bg-white/10 text-white/60'}`}>
                    {r < 60 ? `${r}s` : `${r / 60}m`}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Edit toggle (when not editing) ── */}
      {!editing && !isTV && (
        <button onClick={() => setEditing(true)}
          className="fixed top-4 right-4 z-50 px-4 py-2 rounded-full shadow-lg text-[13px] font-bold transition active:scale-95"
          style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(16px)', color: '#fff', border: '1px solid rgba(255,255,255,0.1)' }}>
          Modifier
        </button>
      )}

      {/* ── Dashboard content ── */}
      <div style={{ padding: editing ? '72px 24px 24px' : 24 }}>
        {/* Header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20, padding: '0 4px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ fontSize: 24, fontWeight: 900, color: textPrimary, letterSpacing: '-0.5px' }}>{config.name}</div>
            <div style={{ padding: '3px 10px', borderRadius: 20, background: isDark ? 'rgba(52,199,89,0.15)' : 'rgba(52,199,89,0.1)', display: 'flex', alignItems: 'center', gap: 5 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#34c759' }} className="animate-pulse" />
              <span style={{ fontSize: 11, fontWeight: 700, color: '#34c759' }}>EN DIRECT</span>
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: textMuted, fontVariantNumeric: 'tabular-nums' }}>
              Maj {lastUpdate.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
            </div>
            <div style={{ fontSize: 9, fontWeight: 600, color: textMuted, marginTop: 1, opacity: 0.6 }}>propulse par Le Vent</div>
          </div>
        </div>

        {/* Canvas — absolute pixel positioning */}
        <div ref={gridRef} style={{
          position: 'relative',
          minHeight: config.widgets.length > 0 ? Math.max(...config.widgets.map(w => w.y + w.h)) + (editing ? 200 : 40) : 300,
        }}>
          {/* Snap grid overlay — visible during drag/resize */}
          {(dragId || resizeId) && (
            <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', zIndex: 0, pointerEvents: 'none' }}>
              <defs>
                <pattern id="snap-grid" width={SNAP_SIZE} height={SNAP_SIZE} patternUnits="userSpaceOnUse">
                  <circle cx="1" cy="1" r="0.8" fill={isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'} />
                </pattern>
              </defs>
              <rect width="100%" height="100%" fill="url(#snap-grid)" />
            </svg>
          )}
          {config.widgets.map(widget => {
            const isActive = dragId === widget.id || resizeId === widget.id
            return (
              <div key={widget.id} className="group" style={{
                position: 'absolute',
                left: widget.x,
                top: widget.y,
                width: widget.w,
                height: widget.h,
                zIndex: isActive ? 50 : 1,
                transition: isActive ? 'none' : 'all 0.15s ease',
              }}>
                {renderWidget(widget)}

                {/* Edit overlay */}
                {editing && (
                  <>
                    {/* Drag handle */}
                    <div
                      style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 32, cursor: 'grab', zIndex: 10, borderRadius: '20px 20px 0 0' }}
                      className="opacity-0 group-hover:opacity-100 transition"
                      onMouseDown={e => startDrag(e, widget.id)}
                      onTouchStart={e => startDrag(e, widget.id)}
                    >
                      <div className="flex items-center justify-center h-full gap-2" style={{ background: 'rgba(0,0,0,0.5)', borderRadius: '20px 20px 0 0' }}>
                        <svg className="w-4 h-4 text-white/80" fill="currentColor" viewBox="0 0 24 24"><circle cx="8" cy="7" r="1.5" /><circle cx="16" cy="7" r="1.5" /><circle cx="8" cy="12" r="1.5" /><circle cx="16" cy="12" r="1.5" /><circle cx="8" cy="17" r="1.5" /><circle cx="16" cy="17" r="1.5" /></svg>
                      </div>
                    </div>

                    {/* Delete */}
                    <button onClick={() => removeWidget(widget.id)}
                      className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition shadow-lg"
                      style={{ zIndex: 20, background: 'rgba(255,59,48,0.9)' }}>
                      <svg className="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /></svg>
                    </button>

                    {/* Resize handle */}
                    <div
                      className="absolute bottom-1.5 right-1.5 w-7 h-7 rounded-full flex items-center justify-center cursor-se-resize opacity-0 group-hover:opacity-100 transition shadow-lg"
                      style={{ background: 'rgba(0,122,255,0.9)', zIndex: 20 }}
                      onMouseDown={e => startResize(e, widget.id)}
                      onTouchStart={e => startResize(e, widget.id)}
                    >
                      <svg className="w-3.5 h-3.5 text-white" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"><path d="M10 2L2 10M10 6L6 10" /></svg>
                    </div>

                    {/* Active border + size label */}
                    {isActive && (
                      <>
                        <div className="absolute inset-0 rounded-[20px] border-2 border-[#007aff] pointer-events-none" style={{ zIndex: 15 }} />
                        <div className="absolute -bottom-6 left-1/2 -translate-x-1/2 px-2 py-0.5 rounded-md text-[10px] font-bold text-white tabular-nums pointer-events-none" style={{ zIndex: 60, background: 'rgba(0,122,255,0.9)', whiteSpace: 'nowrap' }}>
                          {widget.w} × {widget.h}
                        </div>
                      </>
                    )}
                  </>
                )}
              </div>
            )
          })}
        </div>

        {/* Empty state */}
        {config.widgets.length === 0 && (
          <div className="flex items-center justify-center" style={{ minHeight: 300 }}>
            <div className="text-center">
              <div style={{ fontSize: 48, marginBottom: 16 }}>📺</div>
              <div style={{ fontSize: 20, fontWeight: 800, color: textPrimary, marginBottom: 6 }}>Dashboard vide</div>
              <div style={{ fontSize: 14, color: textSecondary, maxWidth: 280, margin: '0 auto' }}>Ajoutez des stations, webcams et bouees depuis la barre d&apos;outils</div>
            </div>
          </div>
        )}

        {/* Footer */}
        <div style={{ textAlign: 'center', marginTop: 24, fontSize: 11, fontWeight: 600, color: textMuted }}>
          AnemOuest &middot; Refresh {config.refreshInterval < 60 ? `${config.refreshInterval}s` : `${config.refreshInterval / 60}min`}
        </div>
      </div>
    </div>
  )
}
