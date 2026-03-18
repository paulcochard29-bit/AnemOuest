'use client'

import { useEffect, useState, useCallback } from 'react'
import { useSearchParams } from 'next/navigation'
import { getWindColorDark, degToCompassFR } from '@/lib/utils'
import { API, apiFetch } from '@/lib/api'
const ALL_SOURCES = ['meteofrance', 'gowind', 'pioupiou', 'netatmo', 'ffvl', 'windcornouaille', 'ndbc', 'diabox', 'windsup']

type EmbedStyle = 'card' | 'pill' | 'minimal' | 'dark'

interface Station {
  id: string; stableId: string; name: string; wind: number; gust: number; direction: number; source: string
}
interface Buoy {
  id: string; name: string; hm0: number; hmax: number; tp: number; direction: number; seaTemp: number
}
interface WebcamData {
  id: string; name: string; location: string; imageUrl: string
}

export function EmbedContent() {
  const params = useSearchParams()
  const stationId = params.get('station')
  const buoyId = params.get('buoy')
  const webcamId = params.get('webcam')
  const styleParam = (params.get('style') || 'card') as EmbedStyle
  const refresh = parseInt(params.get('refresh') || '60')

  const [station, setStation] = useState<Station | null>(null)
  const [buoy, setBuoy] = useState<Buoy | null>(null)
  const [webcam, setWebcam] = useState<WebcamData | null>(null)
  const [loading, setLoading] = useState(true)
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date())

  const fetchData = useCallback(async () => {
    const promises: Promise<void>[] = []

    if (stationId) {
      const p = Promise.all(
        ALL_SOURCES.map(src =>
          apiFetch(`${API}/${src}`).then(r => r.ok ? r.json() : { stations: [] }).catch(() => ({ stations: [] }))
        )
      ).then(results => {
        for (const data of results) {
          const stations = data.stations || []
          const found = stations.find((s: any) => s.id === stationId || s.stableId === stationId)
          if (found) { setStation(found); break }
        }
      })
      promises.push(p)
    }

    if (buoyId) {
      const p = apiFetch(`${API}/candhis`).then(r => r.json()).then(data => {
        const buoys = data.buoys || data || []
        const found = buoys.find((b: any) => b.id === buoyId)
        if (found) setBuoy(found)
      }).catch(() => {})
      promises.push(p)
    }

    if (webcamId) {
      const p = apiFetch(`${API}/webcams`).then(r => r.json()).then(data => {
        const found = data.find((w: any) => w.id === webcamId)
        if (found) setWebcam(found)
      }).catch(() => {})
      promises.push(p)
    }

    await Promise.all(promises)
    setLastUpdate(new Date())
    setLoading(false)
  }, [stationId, buoyId, webcamId])

  // Initial fetch + auto-refresh
  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, Math.max(30, refresh) * 1000)
    return () => clearInterval(interval)
  }, [fetchData, refresh])

  if (loading) {
    return (
      <div className="h-full flex items-center justify-center" style={{ background: styleParam === 'dark' ? '#1c1c1e' : '#f2f2f7' }}>
        <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
      </div>
    )
  }

  const dir = station?.direction ?? 0
  const compass = station ? degToCompassFR(dir) : ''
  const timeStr = lastUpdate.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
  const isDark = styleParam === 'dark'

  // ===== STYLE: PILL (compact inline) =====
  if (styleParam === 'pill') {
    return (
      <div className="h-full flex items-center justify-center p-2 bg-[#f2f2f7]">
        {station && (
          <div className="flex items-center gap-2 rounded-full px-1 py-1 border border-white/80 shadow-lg"
            style={{ background: getWindColorDark(station.wind) }}>
            <svg width="20" height="20" viewBox="0 0 18 18" style={{ transform: `rotate(${dir + 180}deg)`, marginLeft: 4 }}>
              <path d="M9 2L5 15l4-3 4 3z" fill="#fff" />
            </svg>
            <div className="flex items-baseline gap-1 pr-3">
              <span className="text-[18px] font-black text-white tabular-nums">{Math.round(station.wind)}</span>
              <span className="text-[10px] text-white/50">&bull;</span>
              <span className="text-[14px] font-bold text-white/80 tabular-nums">{Math.round(station.gust)}</span>
              <span className="text-[10px] font-semibold text-white/50 ml-0.5">kts</span>
            </div>
          </div>
        )}
        {buoy && (
          <div className="flex items-center gap-3 rounded-full bg-white px-4 py-2 shadow-lg border border-[#e5e5ea]">
            <span className="text-[16px] font-black text-[#007aff] tabular-nums">{buoy.hm0?.toFixed(1)}m</span>
            <span className="text-[13px] font-bold text-[#8e8e93] tabular-nums">{buoy.tp?.toFixed(0)}s</span>
            <span className="text-[13px] font-bold text-[#8e8e93] tabular-nums">{Math.round(buoy.direction ?? 0)}°</span>
          </div>
        )}
      </div>
    )
  }

  // ===== STYLE: MINIMAL (numbers only, transparent) =====
  if (styleParam === 'minimal') {
    return (
      <div className="h-full flex flex-col items-center justify-center p-3" style={{ fontFamily: "-apple-system, 'SF Pro Display', sans-serif" }}>
        {station && (
          <div className="text-center">
            <div className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1">{station.name}</div>
            <div className="flex items-baseline justify-center gap-2">
              <span className="text-[48px] font-black text-[#1c1c1e] tabular-nums leading-none">{Math.round(station.wind)}</span>
              <span className="text-[20px] font-bold text-[#8e8e93] tabular-nums">/ {Math.round(station.gust)}</span>
              <span className="text-[14px] font-semibold text-[#c7c7cc]">kts</span>
            </div>
            <div className="text-[12px] font-semibold text-[#8e8e93] mt-1">{compass} {Math.round(dir)}°</div>
          </div>
        )}
        {buoy && (
          <div className="text-center">
            <div className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1">{buoy.name}</div>
            <div className="flex items-baseline justify-center gap-3">
              <div><span className="text-[42px] font-black text-[#007aff] tabular-nums leading-none">{buoy.hm0?.toFixed(1)}</span><span className="text-[16px] text-[#8e8e93]">m</span></div>
              <div><span className="text-[28px] font-black text-[#8e8e93] tabular-nums leading-none">{buoy.tp?.toFixed(0)}</span><span className="text-[14px] text-[#c7c7cc]">s</span></div>
            </div>
          </div>
        )}
        {webcam && (
          <img
            src={`${API}/webcam-image?id=${encodeURIComponent(webcam.id)}&redirect=true`}
            alt={webcam.name}
            className="w-full rounded-xl object-cover aspect-video"
            onError={(e) => { (e.target as HTMLImageElement).src = webcam.imageUrl }}
          />
        )}
        <div className="text-[9px] text-[#c7c7cc] mt-2 tabular-nums">{timeStr}</div>
      </div>
    )
  }

  // ===== STYLE: DARK =====
  if (isDark) {
    return (
      <div className="h-full bg-[#1c1c1e] p-3 flex flex-col gap-3" style={{ fontFamily: "-apple-system, 'SF Pro Display', sans-serif" }}>
        {station && (
          <div className="rounded-2xl p-4 border border-[#38383a]" style={{ background: `linear-gradient(135deg, ${getWindColorDark(station.wind)}cc, ${getWindColorDark(station.wind)}88)` }}>
            <div className="flex items-center justify-between mb-3">
              <div>
                <div className="text-[10px] font-semibold text-white/40 uppercase tracking-widest">Vent</div>
                <div className="text-[16px] font-bold text-white leading-tight">{station.name}</div>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-[#34c759] animate-pulse" />
                <span className="text-[10px] font-semibold text-white/40 tabular-nums">{timeStr}</span>
              </div>
            </div>
            <div className="flex items-end gap-4">
              <div className="flex items-center gap-2">
                <svg width="22" height="22" viewBox="0 0 18 18" style={{ transform: `rotate(${dir + 180}deg)` }}>
                  <path d="M9 2L5 15l4-3 4 3z" fill="#fff" stroke="rgba(255,255,255,0.2)" strokeWidth="0.5" strokeLinejoin="round" />
                </svg>
                <span className="text-[36px] font-black text-white tabular-nums leading-none">{Math.round(station.wind)}</span>
                <span className="text-[12px] font-semibold text-white/40">nds</span>
              </div>
              <div className="flex items-baseline gap-1 mb-1">
                <span className="text-[10px] font-semibold text-white/30 uppercase">Raf</span>
                <span className="text-[22px] font-black text-white/60 tabular-nums leading-none">{Math.round(station.gust)}</span>
              </div>
              <div className="ml-auto px-2 py-0.5 rounded-full bg-white/10 text-[10px] font-bold text-white/50 mb-1">{compass}</div>
            </div>
          </div>
        )}
        {buoy && (
          <div className="rounded-2xl p-4 border border-[#38383a] bg-[#2c2c2e]">
            <div className="flex items-center justify-between mb-3">
              <div>
                <div className="text-[10px] font-semibold text-[#8e8e93] uppercase tracking-widest">Houle</div>
                <div className="text-[16px] font-bold text-white leading-tight">{buoy.name}</div>
              </div>
              <span className="text-[10px] font-semibold text-[#636366] tabular-nums">{timeStr}</span>
            </div>
            <div className="flex gap-3">
              {[
                { label: 'Hm0', value: buoy.hm0?.toFixed(1), unit: 'm' },
                { label: 'Tp', value: buoy.tp?.toFixed(1), unit: 's' },
                { label: 'Dir', value: `${Math.round(buoy.direction ?? 0)}`, unit: '°' },
              ].map(d => (
                <div key={d.label} className="flex-1 rounded-xl bg-white/5 p-3 text-center">
                  <div className="text-[9px] font-semibold text-[#636366] uppercase tracking-widest mb-1">{d.label}</div>
                  <div className="text-[26px] font-black text-[#0a84ff] tabular-nums leading-none">{d.value}</div>
                  <div className="text-[10px] font-medium text-[#636366] mt-0.5">{d.unit}</div>
                </div>
              ))}
            </div>
          </div>
        )}
        {webcam && (
          <div className="rounded-2xl overflow-hidden border border-[#38383a]">
            <div className="relative">
              <img
                src={`${API}/webcam-image?id=${encodeURIComponent(webcam.id)}&redirect=true`}
                alt={webcam.name}
                className="w-full aspect-video object-cover bg-[#2c2c2e]"
                onError={(e) => { (e.target as HTMLImageElement).src = webcam.imageUrl }}
              />
              <div className="absolute bottom-0 left-0 right-0 p-2.5 bg-gradient-to-t from-black/70 to-transparent">
                <div className="text-[13px] font-bold text-white">{webcam.name}</div>
                <div className="text-[10px] text-white/50">{webcam.location} &middot; {timeStr}</div>
              </div>
            </div>
          </div>
        )}
        <div className="text-center mt-auto">
          <a href="https://anemouest.app/map" target="_blank" rel="noopener" className="text-[10px] font-medium text-[#636366]">Le Vent</a>
        </div>
      </div>
    )
  }

  // ===== STYLE: CARD (default) =====
  return (
    <div className="h-full bg-[#f2f2f7] p-3 flex flex-col gap-3" style={{ fontFamily: "-apple-system, 'SF Pro Display', sans-serif" }}>
      {station && (
        <div className="glass-card rounded-2xl overflow-hidden">
          <div className="p-4 rounded-2xl" style={{ background: `linear-gradient(135deg, ${getWindColorDark(station.wind)}, ${getWindColorDark(station.wind)}dd)` }}>
            <div className="flex items-center justify-between mb-3">
              <div>
                <div className="text-[10px] font-semibold text-white/50 uppercase tracking-widest">Vent</div>
                <div className="text-[16px] font-bold text-white leading-tight">{station.name}</div>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-[#34c759] animate-pulse" />
                <span className="text-[10px] font-semibold text-white/40 tabular-nums">{timeStr}</span>
              </div>
            </div>
            <div className="flex items-end gap-4">
              <div className="flex items-center gap-2">
                <svg width="22" height="22" viewBox="0 0 18 18" style={{ transform: `rotate(${dir + 180}deg)` }}>
                  <path d="M9 2L5 15l4-3 4 3z" fill="#fff" stroke="rgba(255,255,255,0.3)" strokeWidth="0.5" strokeLinejoin="round" />
                </svg>
                <span className="text-[36px] font-black text-white tabular-nums leading-none">{Math.round(station.wind)}</span>
                <span className="text-[12px] font-semibold text-white/40">nds</span>
              </div>
              <div className="flex items-baseline gap-1 mb-1">
                <span className="text-[10px] font-semibold text-white/30 uppercase">Raf</span>
                <span className="text-[22px] font-black text-white/60 tabular-nums leading-none">{Math.round(station.gust)}</span>
              </div>
              <div className="ml-auto px-2 py-0.5 rounded-full bg-white/15 text-[10px] font-bold text-white/60 mb-1">{compass} {Math.round(dir)}°</div>
            </div>
          </div>
        </div>
      )}

      {buoy && (
        <div className="glass-card rounded-2xl overflow-hidden">
          <div className="p-4">
            <div className="flex items-center justify-between mb-3">
              <div>
                <div className="text-[10px] font-semibold text-[#8e8e93] uppercase tracking-widest">Houle</div>
                <div className="text-[16px] font-bold text-[#1c1c1e] leading-tight">{buoy.name}</div>
              </div>
              <span className="text-[10px] font-semibold text-[#c7c7cc] tabular-nums">{timeStr}</span>
            </div>
            <div className="flex gap-3">
              {[
                { label: 'Hm0', value: buoy.hm0?.toFixed(1), unit: 'm' },
                { label: 'Periode', value: buoy.tp?.toFixed(1), unit: 's' },
                { label: 'Dir.', value: `${Math.round(buoy.direction ?? 0)}`, unit: '°' },
              ].map(d => (
                <div key={d.label} className="flex-1 rounded-xl bg-[#007aff]/8 p-3 text-center">
                  <div className="text-[9px] font-semibold text-[#8e8e93] uppercase tracking-widest mb-1">{d.label}</div>
                  <div className="text-[26px] font-black text-[#007aff] tabular-nums leading-none">{d.value}</div>
                  <div className="text-[10px] font-medium text-[#8e8e93] mt-0.5">{d.unit}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {webcam && (
        <div className="glass-card rounded-2xl overflow-hidden">
          <div className="relative">
            <img
              src={`${API}/webcam-image?id=${encodeURIComponent(webcam.id)}&redirect=true`}
              alt={webcam.name}
              className="w-full aspect-video object-cover bg-[#2c2c2e]"
              onError={(e) => { (e.target as HTMLImageElement).src = webcam.imageUrl }}
            />
            <div className="absolute bottom-0 left-0 right-0 p-2.5 bg-gradient-to-t from-black/60 to-transparent">
              <div className="text-[13px] font-bold text-white">{webcam.name}</div>
              <div className="text-[10px] text-white/50">{webcam.location} &middot; {timeStr}</div>
            </div>
          </div>
        </div>
      )}

      {!station && !buoy && !webcam && (
        <div className="glass-card rounded-2xl p-8 text-center">
          <div className="text-[15px] text-[#8e8e93]">Aucune donnee trouvee</div>
          <div className="text-[12px] text-[#c7c7cc] mt-1">Verifiez les parametres station, buoy ou webcam</div>
        </div>
      )}

      <div className="text-center mt-auto">
        <a href="https://anemouest.app/map" target="_blank" rel="noopener" className="text-[10px] font-medium text-[#c7c7cc] hover:text-[#007aff] transition">Le Vent</a>
      </div>
    </div>
  )
}
