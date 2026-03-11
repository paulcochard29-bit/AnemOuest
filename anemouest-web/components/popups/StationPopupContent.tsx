'use client'

import { useState, useEffect, useCallback } from 'react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { SOURCE_COLORS, type WindStation } from '@/store/appStore'
import { getWindColor, getWindColorDark, degToCompassFR } from '@/lib/utils'

const API = 'https://anemouest-api.vercel.app/api'

interface Props {
  station: WindStation
  expanded: boolean
  onExpand: () => void
}

interface ChartPoint { time: string; wind: number; gust: number; dir?: number }

export function StationPopupContent({ station, expanded, onExpand }: Props) {
  const wc = getWindColor(station.wind)
  const wcDark = getWindColorDark(station.wind)
  const compass = degToCompassFR(station.direction)

  const [history, setHistory] = useState<ChartPoint[]>([])
  const [loading, setLoading] = useState(true)
  const [hours, setHours] = useState(6)

  const fetchHistory = useCallback((h: number) => {
    const endpoint = station.source === 'pioupiou' ? 'pioupiou'
      : station.source === 'windcornouaille' ? 'windcornouaille'
      : station.source === 'meteofrance' ? 'meteofrance'
      : station.source === 'holfuy' || station.source === 'gowind' ? 'gowind'
      : station.source === 'windsup' ? 'windsup'
      : station.source === 'netatmo' ? 'netatmo'
      : station.source === 'ndbc' ? 'ndbc'
      : station.source === 'ffvl' ? 'gowind'
      : station.source === 'diabox' ? 'diabox'
      : 'pioupiou'
    setLoading(true)
    fetch(`${API}/${endpoint}?history=${station.id}&hours=${h}`)
      .then(r => r.json())
      .then(data => {
        setHistory((data.observations || []).map((o: any) => ({
          time: new Date(o.ts).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
          wind: Math.round(o.wind * 10) / 10,
          gust: Math.round(o.gust * 10) / 10,
          dir: o.direction ?? o.dir,
        })))
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [station.id, station.source])

  useEffect(() => { fetchHistory(hours) }, [hours, fetchHistory])

  // Freshness
  let freshness = ''
  if (station.ts) {
    const diffMin = Math.floor((Date.now() - new Date(station.ts).getTime()) / 60000)
    if (diffMin < 1) freshness = "à l'instant"
    else if (diffMin < 60) freshness = `il y a ${diffMin} min`
    else freshness = `il y a ${Math.floor(diffMin / 60)}h`
  }

  const hasTemp = station.temperature !== undefined && station.temperature !== 0
  const hasHumidity = station.humidity !== undefined && station.humidity !== 0
  const hasPressure = station.pressure !== undefined && station.pressure !== 0

  return (
    <div>
      {/* Hero */}
      <div className="px-4 py-3 relative overflow-hidden" style={{ background: `linear-gradient(135deg, ${wc}, ${wcDark})` }}>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[13px] font-semibold text-white/80 truncate max-w-[180px]">{station.name}</div>
            <div className="flex items-baseline gap-2 mt-0.5">
              <span className="text-[32px] font-black text-white leading-none">{Math.round(station.wind)}</span>
              <span className="text-[13px] font-bold text-white/60">nds</span>
              <span className="text-white/40 text-[10px]">&bull;</span>
              <span className="text-[20px] font-bold text-white/80">{Math.round(station.gust)}</span>
            </div>
          </div>
          <div className="flex flex-col items-center gap-1">
            <svg width="32" height="32" viewBox="0 0 32 32" style={{ transform: `rotate(${station.direction + 180}deg)` }}>
              <path d="M16 4L10 26l6-4 6 4z" fill="#fff" stroke="rgba(255,255,255,0.3)" strokeWidth="0.5" strokeLinejoin="round" />
            </svg>
            <span className="text-[11px] font-bold text-white/80">{compass}</span>
          </div>
        </div>
      </div>

      {/* Chart */}
      <div className="px-3 pt-2 pb-1">
        <div className="flex items-center justify-between mb-1.5">
          <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Historique</span>
          <div className="flex bg-[#f2f2f7] rounded-lg p-0.5">
            {[3, 6, 12, 24].map(h => (
              <button key={h} onClick={() => setHours(h)}
                className={`px-2 py-0.5 text-[10px] font-semibold rounded-md transition ${hours === h ? 'bg-white text-[#1c1c1e] shadow-sm' : 'text-[#8e8e93]'}`}>
                {h}h
              </button>
            ))}
          </div>
        </div>
        <div className="h-28">
          {loading ? (
            <div className="w-full h-full flex items-center justify-center">
              <div className="w-4 h-4 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
            </div>
          ) : history.length > 0 ? (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={history} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
                <defs>
                  <linearGradient id="pwg" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#007aff" stopOpacity={0.2} />
                    <stop offset="95%" stopColor="#007aff" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="pgg" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#ff3b30" stopOpacity={0.12} />
                    <stop offset="95%" stopColor="#ff3b30" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.05)" vertical={false} />
                <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} width={28} />
                <Tooltip content={<WindTooltip />} />
                <Area type="monotone" dataKey="gust" stroke="#ff3b30" strokeWidth={1.5} fill="url(#pgg)" dot={false} name="Rafales" />
                <Area type="monotone" dataKey="wind" stroke="#007aff" strokeWidth={2} fill="url(#pwg)" dot={false} name="Vent" />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="w-full h-full flex items-center justify-center text-[#8e8e93] text-[12px]">Pas de données</div>
          )}
        </div>
        <div className="flex items-center justify-center gap-4 mt-1 text-[10px] font-medium text-[#8e8e93]">
          <div className="flex items-center gap-1"><span className="w-2.5 h-[2px] bg-[#007aff] rounded-full" />Vent</div>
          <div className="flex items-center gap-1"><span className="w-2.5 h-[2px] bg-[#ff3b30] rounded-full" />Rafales</div>
        </div>
      </div>

      {/* Extra data — shown when expanded */}
      {expanded && (hasTemp || hasHumidity || hasPressure) && (
        <div className="flex gap-1.5 mx-3 mb-2">
          {hasTemp && (
            <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Temp</div>
              <div className="text-[16px] font-bold text-[#ff9500] tabular-nums">{Math.round(station.temperature!)}°</div>
            </div>
          )}
          {hasHumidity && (
            <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Humid.</div>
              <div className="text-[16px] font-bold text-[#007aff] tabular-nums">{Math.round(station.humidity!)}%</div>
            </div>
          )}
          {hasPressure && (
            <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Pression</div>
              <div className="text-[16px] font-bold text-[#5856d6] tabular-nums">{Math.round(station.pressure!)}</div>
            </div>
          )}
        </div>
      )}

      {/* Data timestamp — shown when expanded */}
      {expanded && station.ts && (
        <div className="mx-3 mb-2 bg-[#f2f2f7] rounded-lg px-3 py-1.5 flex items-center gap-2">
          <svg className="w-3.5 h-3.5 text-[#8e8e93] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
          <span className="text-[11px] text-[#8e8e93]">
            Données du {new Date(station.ts).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
          </span>
        </div>
      )}

      {/* Footer */}
      <div className="px-3 py-2 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white"
            style={{ background: SOURCE_COLORS[station.source] || '#8e8e93' }}>
            {station.source}
          </span>
          {freshness && <span className="text-[11px] text-[#8e8e93]">{freshness}</span>}
        </div>
        {!expanded ? (
          <button onClick={onExpand}
            className="text-[12px] font-semibold text-[#007aff] hover:text-[#0056b3] transition flex items-center gap-0.5">
            Voir plus
            <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
          </button>
        ) : (
          <button onClick={onExpand}
            className="text-[12px] font-semibold text-[#8e8e93] hover:text-[#1c1c1e] transition flex items-center gap-0.5">
            Réduire
            <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M6 9l6 6 6-6" /></svg>
          </button>
        )}
      </div>
    </div>
  )
}

function WindTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null
  const wind = payload.find((p: any) => p.dataKey === 'wind')
  const gust = payload.find((p: any) => p.dataKey === 'gust')
  const dirVal = payload[0]?.payload?.dir

  return (
    <div style={{
      background: 'rgba(248,248,250,0.95)', backdropFilter: 'blur(16px)',
      borderRadius: 10, padding: '4px 10px', border: '0.5px solid rgba(0,0,0,0.06)',
      boxShadow: '0 2px 12px rgba(0,0,0,0.08)',
      display: 'flex', alignItems: 'center', gap: 5, whiteSpace: 'nowrap',
      transform: 'translateY(-8px)',
    }}>
      <span style={{ fontSize: 9, color: '#8e8e93', fontWeight: 600 }}>{label}</span>
      {dirVal !== undefined && dirVal !== null && (
        <svg width="14" height="14" viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
          <circle cx="8" cy="8" r="7" fill="none" stroke="#e5e5ea" strokeWidth="0.8" />
          <g transform={`rotate(${dirVal + 180}, 8, 8)`}>
            <path d="M8 2L6.5 12l1.5-1.5 1.5 1.5z" fill="#007aff" />
          </g>
        </svg>
      )}
      {wind && <span style={{ fontSize: 11, fontWeight: 800, color: '#007aff' }}>{wind.value}</span>}
      {gust && <>
        <span style={{ fontSize: 9, color: '#c7c7cc' }}>/</span>
        <span style={{ fontSize: 11, fontWeight: 800, color: '#ff3b30' }}>{gust.value}</span>
      </>}
      <span style={{ fontSize: 9, color: '#aeaeb2', fontWeight: 500 }}>nds</span>
    </div>
  )
}
