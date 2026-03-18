'use client'

import { useState, useEffect, useCallback } from 'react'
import { getWindColorDark, degToCompassFR } from '@/lib/utils'
import type { DashboardConfig, DashboardWidget } from './DashboardBuilder'
import { API, apiFetch } from '@/lib/api'
const ALL_SOURCES = ['meteofrance', 'gowind', 'pioupiou', 'netatmo', 'ffvl', 'windcornouaille', 'ndbc', 'diabox']

interface StationData { id: string; stableId: string; name: string; wind: number; gust: number; direction: number; source: string; temperature?: number }
interface BuoyData { id: string; name: string; hm0: number; hmax: number; tp: number; direction: number; seaTemp: number }
interface WebcamData { id: string; name: string; location: string; imageUrl: string; streamUrl?: string }

interface Props { config: DashboardConfig }

export function DashboardView({ config }: Props) {
  const [stationMap, setStationMap] = useState<Record<string, StationData>>({})
  const [buoyMap, setBuoyMap] = useState<Record<string, BuoyData>>({})
  const [webcamMap, setWebcamMap] = useState<Record<string, WebcamData>>({})
  const [clock, setClock] = useState(new Date())
  const [lastUpdate, setLastUpdate] = useState(new Date())
  const [imgTick, setImgTick] = useState(0)

  const fetchAll = useCallback(async () => {
    const neededStations = config.widgets.filter(w => w.type === 'station').map(w => w.dataId)
    const neededBuoys = config.widgets.filter(w => w.type === 'buoy').map(w => w.dataId)
    const neededWebcams = config.widgets.filter(w => w.type === 'webcam').map(w => w.dataId)
    const promises: Promise<void>[] = []

    if (neededStations.length > 0) {
      const p = Promise.all(
        ALL_SOURCES.map(src =>
          apiFetch(`${API}/${src}`).then(r => r.ok ? r.json() : { stations: [] }).catch(() => ({ stations: [] }))
        )
      ).then(results => {
        const map: Record<string, StationData> = {}
        for (const data of results) {
          for (const s of (data.stations || [])) {
            const sid = s.stableId || s.id
            if (neededStations.includes(sid) || neededStations.includes(s.id)) {
              map[sid] = s
              map[s.id] = s
            }
          }
        }
        setStationMap(map)
      })
      promises.push(p)
    }

    if (neededBuoys.length > 0) {
      const p = apiFetch(`${API}/candhis`).then(r => r.json()).then(data => {
        const list = data.buoys || data || []
        const map: Record<string, BuoyData> = {}
        for (const b of list) { if (neededBuoys.includes(b.id)) map[b.id] = b }
        setBuoyMap(map)
      }).catch(() => {})
      promises.push(p)
    }

    if (neededWebcams.length > 0) {
      const p = apiFetch(`${API}/webcams`).then(r => r.json()).then(data => {
        const map: Record<string, WebcamData> = {}
        for (const w of data) { if (neededWebcams.includes(w.id)) map[w.id] = w }
        setWebcamMap(map)
      }).catch(() => {})
      promises.push(p)
    }

    await Promise.all(promises)
    setLastUpdate(new Date())
    setImgTick(t => t + 1)
  }, [config.widgets])

  useEffect(() => {
    fetchAll()
    const interval = setInterval(fetchAll, Math.max(30, config.refreshInterval) * 1000)
    return () => clearInterval(interval)
  }, [fetchAll, config.refreshInterval])

  useEffect(() => {
    const interval = setInterval(() => setClock(new Date()), 1000)
    return () => clearInterval(interval)
  }, [])

  const style = config.style
  const isDark = style === 'dark' || style === 'ocean'
  const bg = style === 'dark' ? '#1a1a2e' : style === 'ocean' ? '#0c1929' : '#f2f2f7'
  const cardBg = style === 'dark' ? 'rgba(30,30,50,0.85)' : style === 'ocean' ? 'rgba(15,35,60,0.85)' : 'rgba(255,255,255,0.7)'
  const cardBorder = style === 'dark' ? '1px solid rgba(255,255,255,0.06)' : style === 'ocean' ? '1px solid rgba(100,180,255,0.15)' : '1px solid rgba(255,255,255,0.5)'
  const textPrimary = isDark ? '#fff' : '#1c1c1e'
  const textSecondary = isDark ? 'rgba(255,255,255,0.5)' : '#8e8e93'
  const textMuted = isDark ? 'rgba(255,255,255,0.3)' : '#c7c7cc'

  const renderWidget = (widget: DashboardWidget) => {
    const isLarge = widget.w >= 2

    if (widget.type === 'title') {
      return (
        <div style={{ height: '100%', display: 'flex', alignItems: 'flex-end', padding: '0 4px 4px' }}>
          <div style={{ fontSize: 22, fontWeight: 900, color: textPrimary, letterSpacing: '-0.3px' }}>{widget.label}</div>
        </div>
      )
    }

    if (widget.type === 'clock') {
      return (
        <div style={{
          height: '100%', background: cardBg, border: cardBorder, borderRadius: 20,
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
          backdropFilter: 'blur(20px)',
        }}>
          <div style={{ fontSize: isLarge ? 64 : 42, fontWeight: 900, color: textPrimary, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>
            {clock.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
          </div>
          <div style={{ fontSize: isLarge ? 16 : 13, fontWeight: 600, color: textSecondary, marginTop: 8 }}>
            {clock.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
          </div>
        </div>
      )
    }

    if (widget.type === 'station') {
      const s = stationMap[widget.dataId]
      if (!s) {
        return (
          <div style={{ height: '100%', background: cardBg, border: cardBorder, borderRadius: 20, padding: 20, backdropFilter: 'blur(20px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: textSecondary }}>{widget.label}</div>
              <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin mx-auto mt-3" />
            </div>
          </div>
        )
      }
      const dir = s.direction ?? 0
      const compass = degToCompassFR(dir)
      const wcDark = getWindColorDark(s.wind)

      return (
        <div style={{
          height: '100%',
          background: `linear-gradient(135deg, ${wcDark}, ${wcDark}cc)`,
          border: style === 'ocean' ? '1px solid rgba(100,180,255,0.12)' : 'none',
          borderRadius: 20, overflow: 'hidden',
        }}>
          <div style={{ height: '100%', padding: isLarge ? 24 : 16, background: 'rgba(255,255,255,0.06)', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.4)', textTransform: 'uppercase', letterSpacing: 1.5 }}>Vent</div>
                <div style={{ fontSize: isLarge ? 17 : 14, fontWeight: 800, color: '#fff', lineHeight: 1.2 }}>{widget.label}</div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <svg width="18" height="18" viewBox="0 0 18 18" style={{ transform: `rotate(${dir + 180}deg)` }}>
                  <path d="M9 2L5 15l4-3 4 3z" fill="#fff" fillOpacity="0.8" />
                </svg>
                <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.5)' }}>{compass}</span>
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: isLarge ? 12 : 8 }}>
              <span style={{ fontSize: isLarge ? 64 : 44, fontWeight: 900, color: '#fff', fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{Math.round(s.wind)}</span>
              <span style={{ fontSize: isLarge ? 16 : 12, fontWeight: 600, color: 'rgba(255,255,255,0.4)' }}>nds</span>
              <div style={{ marginLeft: 'auto', textAlign: 'right' }}>
                <div style={{ fontSize: 10, fontWeight: 600, color: 'rgba(255,255,255,0.3)', textTransform: 'uppercase' }}>Raf</div>
                <div style={{ fontSize: isLarge ? 32 : 24, fontWeight: 900, color: 'rgba(255,255,255,0.6)', fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{Math.round(s.gust)}</div>
              </div>
            </div>
          </div>
        </div>
      )
    }

    if (widget.type === 'buoy') {
      const b = buoyMap[widget.dataId]
      if (!b) {
        return (
          <div style={{ height: '100%', background: cardBg, border: cardBorder, borderRadius: 20, padding: 20, backdropFilter: 'blur(20px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: textSecondary }}>{widget.label}</div>
              <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin mx-auto mt-3" />
            </div>
          </div>
        )
      }
      const waveColor = style === 'ocean' ? '#0ea5e9' : '#007aff'

      return (
        <div style={{
          height: '100%', background: cardBg, border: cardBorder, borderRadius: 20,
          padding: isLarge ? 24 : 16, backdropFilter: 'blur(20px)',
          display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
        }}>
          <div>
            <div style={{ fontSize: 10, fontWeight: 700, color: textSecondary, textTransform: 'uppercase', letterSpacing: 1.5 }}>Houle</div>
            <div style={{ fontSize: isLarge ? 17 : 14, fontWeight: 800, color: textPrimary, lineHeight: 1.2 }}>{widget.label}</div>
          </div>
          <div style={{ display: 'flex', gap: isLarge ? 16 : 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
            <div>
              <span style={{ fontSize: isLarge ? 56 : 40, fontWeight: 900, color: waveColor, fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{b.hm0?.toFixed(1)}</span>
              <span style={{ fontSize: 14, fontWeight: 600, color: textSecondary, marginLeft: 3 }}>m</span>
            </div>
            <div style={{ display: 'flex', gap: isLarge ? 14 : 8 }}>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 9, fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 1 }}>Tp</div>
                <div style={{ fontSize: isLarge ? 28 : 20, fontWeight: 900, color: textPrimary, fontVariantNumeric: 'tabular-nums', lineHeight: 1, opacity: 0.7 }}>{b.tp?.toFixed(0)}<span style={{ fontSize: 11, color: textSecondary }}>s</span></div>
              </div>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 9, fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 1 }}>Hmax</div>
                <div style={{ fontSize: isLarge ? 28 : 20, fontWeight: 900, color: textPrimary, fontVariantNumeric: 'tabular-nums', lineHeight: 1, opacity: 0.7 }}>{b.hmax?.toFixed(1)}<span style={{ fontSize: 11, color: textSecondary }}>m</span></div>
              </div>
              {b.seaTemp > 0 && (
                <div style={{ textAlign: 'center' }}>
                  <div style={{ fontSize: 9, fontWeight: 700, color: textMuted, textTransform: 'uppercase', letterSpacing: 1 }}>Mer</div>
                  <div style={{ fontSize: isLarge ? 28 : 20, fontWeight: 900, color: '#ff9500', fontVariantNumeric: 'tabular-nums', lineHeight: 1, opacity: 0.8 }}>{b.seaTemp?.toFixed(0)}<span style={{ fontSize: 11, color: textSecondary }}>°</span></div>
                </div>
              )}
            </div>
          </div>
        </div>
      )
    }

    if (widget.type === 'webcam') {
      const w = webcamMap[widget.dataId]
      const imgUrl = w
        ? `${API}/webcam-image?id=${encodeURIComponent(w.id)}&redirect=true&t=${imgTick}`
        : null

      return (
        <div style={{
          height: '100%', background: cardBg, border: cardBorder, borderRadius: 20,
          overflow: 'hidden', backdropFilter: 'blur(20px)',
        }}>
          <div style={{ position: 'relative', height: '100%' }}>
            {imgUrl ? (
              <img
                src={imgUrl}
                alt={widget.label}
                style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', background: isDark ? '#1c1c1e' : '#e5e5ea' }}
                onError={(e) => { if (w) (e.target as HTMLImageElement).src = w.imageUrl }}
              />
            ) : (
              <div style={{ width: '100%', height: '100%', background: isDark ? '#1c1c1e' : '#e5e5ea', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
              </div>
            )}
            <div style={{
              position: 'absolute', bottom: 0, left: 0, right: 0,
              padding: '20px 14px 10px',
              background: 'linear-gradient(to top, rgba(0,0,0,0.75), transparent)',
            }}>
              <div style={{ fontSize: 15, fontWeight: 800, color: '#fff' }}>{widget.label}</div>
              {w?.location && <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.5)' }}>{w.location}</div>}
            </div>
          </div>
        </div>
      )
    }

    return null
  }

  return (
    <div style={{
      minHeight: '100vh',
      background: bg,
      padding: 24,
      fontFamily: "-apple-system, 'SF Pro Display', BlinkMacSystemFont, sans-serif",
      WebkitFontSmoothing: 'antialiased',
    }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20, padding: '0 4px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ fontSize: 24, fontWeight: 900, color: textPrimary, letterSpacing: '-0.5px' }}>{config.name}</div>
          <div style={{
            padding: '3px 10px', borderRadius: 20,
            background: isDark ? 'rgba(52,199,89,0.15)' : 'rgba(52,199,89,0.1)',
            display: 'flex', alignItems: 'center', gap: 5,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#34c759' }} className="animate-pulse" />
            <span style={{ fontSize: 11, fontWeight: 700, color: '#34c759' }}>LIVE</span>
          </div>
        </div>
        <div style={{ fontSize: 12, fontWeight: 600, color: textMuted, fontVariantNumeric: 'tabular-nums' }}>
          Maj {lastUpdate.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
        </div>
      </div>

      {/* Grid using CSS Grid with widget positions */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${config.columns}, 1fr)`,
        gridAutoRows: 60,
        gap: 12,
      }}>
        {config.widgets.map(widget => (
          <div key={widget.id} style={{
            gridColumn: `${widget.x + 1} / span ${Math.min(widget.w, config.columns)}`,
            gridRow: `${widget.y + 1} / span ${widget.h}`,
          }}>
            {renderWidget(widget)}
          </div>
        ))}
      </div>

      {/* Footer */}
      <div style={{ textAlign: 'center', marginTop: 24, fontSize: 11, fontWeight: 600, color: textMuted }}>
        Le Vent &middot; Refresh auto {config.refreshInterval}s
      </div>
    </div>
  )
}
