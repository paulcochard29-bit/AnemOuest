'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { SOURCE_COLORS, useAppStore, type WindStation } from '@/store/appStore'
import { getWindColor, getWindColorDark, degToCompassFR } from '@/lib/utils'
import { useSwipe } from '@/hooks/useSwipe'
import { EmbedPicker } from './EmbedPicker'
import { API, apiFetch } from '@/lib/api'

const METEO_API = 'https://api.open-meteo.com/v1/meteofrance'

interface Props { station: WindStation; onClose: () => void; onSwipe?: (dir: 'left' | 'right') => void }
interface ChartPoint { time: string; wind: number; gust: number; dir?: number }
interface ForecastPoint { time: string; forecastWind: number; forecastGust: number }
interface ForecastComparison { meanError: number; maxError: number; bias: number; withinTolerance: number; points: { time: string; actual: number; forecast: number }[] }

export function StationSheet({ station, onClose, onSwipe }: Props) {
  const [history, setHistory] = useState<ChartPoint[]>([])
  const [hours, setHours] = useState(6)
  const [loading, setLoading] = useState(true)
  const [lastFetchTs, setLastFetchTs] = useState<number>(Date.now())
  const [ago, setAgo] = useState('0s')
  const [forecast, setForecast] = useState<ForecastComparison | null>(null)
  const [showForecast, setShowForecast] = useState(false)
  const refreshInterval = useAppStore(s => s.refreshInterval)
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const fetchHistory = useCallback((stationId: string, source: string, h: number) => {
    const endpoint = source === 'pioupiou' ? 'pioupiou'
      : source === 'windcornouaille' ? 'windcornouaille'
      : source === 'meteofrance' ? 'meteofrance'
      : source === 'holfuy' || source === 'gowind' ? 'gowind'
      : source === 'windsup' ? 'windsup'
      : source === 'netatmo' ? 'netatmo'
      : source === 'ndbc' ? 'ndbc'
      : source === 'ffvl' ? 'gowind'
      : source === 'diabox' ? 'diabox'
      : 'pioupiou'
    let url = `${API}/${endpoint}?history=${stationId}&hours=${h}`
    if (endpoint === 'windsup') {
      const token = localStorage.getItem('windsupToken')
      if (token) url += `&token=${encodeURIComponent(token)}`
    }
    return apiFetch(url)
      .then(r => r.json())
      .then(data => {
        setHistory((data.observations || []).map((o: any) => ({
          time: new Date(o.ts).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
          wind: Math.round(o.wind * 10) / 10,
          gust: Math.round(o.gust * 10) / 10,
          dir: o.direction ?? o.dir,
        })))
        setLastFetchTs(Date.now())
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [])

  // Fetch AROME forecast for comparison
  const fetchForecast = useCallback(async (lat: number, lon: number) => {
    try {
      const res = await fetch(`${METEO_API}?latitude=${lat}&longitude=${lon}&hourly=wind_speed_10m,wind_gusts_10m&past_days=1&forecast_days=0&wind_speed_unit=kn&timezone=Europe/Paris`)
      const data = await res.json()
      if (!data.hourly) return
      const points: ForecastPoint[] = data.hourly.time.map((t: string, i: number) => ({
        time: new Date(t).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
        forecastWind: Math.round((data.hourly.wind_speed_10m[i] || 0) * 10) / 10,
        forecastGust: Math.round((data.hourly.wind_gusts_10m[i] || 0) * 10) / 10,
      }))
      return points
    } catch { return null }
  }, [])

  // Build comparison when both datasets are available
  useEffect(() => {
    if (!station.lat || !station.lon || history.length < 3) { setForecast(null); return }
    fetchForecast(station.lat, station.lon).then(fp => {
      if (!fp || fp.length === 0) { setForecast(null); return }
      const forecastMap = new Map(fp.map(p => [p.time, p]))
      const matched: { time: string; actual: number; forecast: number }[] = []
      history.forEach(h => {
        const f = forecastMap.get(h.time)
        if (f) matched.push({ time: h.time, actual: h.wind, forecast: f.forecastWind })
      })
      if (matched.length < 3) { setForecast(null); return }
      const errors = matched.map(m => Math.abs(m.actual - m.forecast))
      const biases = matched.map(m => m.forecast - m.actual)
      setForecast({
        meanError: Math.round(errors.reduce((a, b) => a + b, 0) / errors.length * 10) / 10,
        maxError: Math.round(Math.max(...errors) * 10) / 10,
        bias: Math.round(biases.reduce((a, b) => a + b, 0) / biases.length * 10) / 10,
        withinTolerance: Math.round(errors.filter(e => e <= 5).length / errors.length * 100),
        points: matched,
      })
    })
  }, [history, station.lat, station.lon, fetchForecast])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    fetchHistory(station.id, station.source, hours).then(() => { if (cancelled) return })
    return () => { cancelled = true }
  }, [station.id, station.source, hours, fetchHistory])

  useEffect(() => {
    if (refreshTimerRef.current) clearInterval(refreshTimerRef.current)
    refreshTimerRef.current = setInterval(() => {
      fetchHistory(station.id, station.source, hours)
    }, refreshInterval * 1000)
    return () => { if (refreshTimerRef.current) clearInterval(refreshTimerRef.current) }
  }, [station.id, station.source, hours, refreshInterval, fetchHistory])

  useEffect(() => {
    const tick = () => {
      const diff = Math.floor((Date.now() - lastFetchTs) / 1000)
      if (diff < 60) setAgo(`${diff}s`)
      else if (diff < 3600) setAgo(`${Math.floor(diff / 60)} min`)
      else setAgo(`${Math.floor(diff / 3600)}h`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [lastFetchTs])

  const wcDark = getWindColorDark(station.wind)
  const dir = station.direction
  const compass = degToCompassFR(dir)
  const swipe = useSwipe(onSwipe)

  const hasTemp = station.temperature !== undefined && station.temperature !== 0
  const hasHumidity = station.humidity !== undefined && station.humidity !== 0
  const hasPressure = station.pressure !== undefined && station.pressure !== 0

  return (
    <>
      <div className="sheet-backdrop" onClick={onClose} />
      <div className="sheet" {...swipe}>
        <div className="flex justify-center pt-1.5 pb-1 md:hidden">
          <div className="w-9 h-[5px] rounded-full bg-white/30" />
        </div>

        <div className="overflow-auto max-h-[calc(50vh-20px)] md:max-h-screen pb-safe">
          {/* Header */}
          <div className="flex items-start justify-between px-4 pt-3 pb-2">
            <div>
              <h2 className="text-[18px] font-bold text-[#1c1c1e] tracking-tight">{station.name}</h2>
            </div>
            <button onClick={onClose} className="px-3 py-1 rounded-full text-[13px] font-medium text-[#007aff] glass-btn">Fermer</button>
          </div>

          {/* Hero: Compass + Wind/Gust */}
          <div className="mx-4 mb-3 rounded-2xl overflow-hidden relative" style={{ background: `linear-gradient(135deg, ${wcDark}, ${wcDark}dd)` }}>
            <div className="p-4 flex items-center gap-5 relative z-10" style={{ background: 'rgba(255,255,255,0.08)' }}>

              {/* Compass rose + direction label */}
              <div className="flex-shrink-0 flex flex-col items-center gap-1.5">
                <div className="relative w-[92px] h-[92px]">
                  <svg width="92" height="92" viewBox="0 0 92 92">
                    <circle cx="46" cy="46" r="44" fill="none" stroke="white" strokeOpacity="0.2" strokeWidth="1.5" />
                    <circle cx="46" cy="46" r="34" fill="none" stroke="white" strokeOpacity="0.08" strokeWidth="0.8" />
                    {Array.from({ length: 36 }).map((_, i) => {
                      const angle = i * 10
                      const rad = (angle - 90) * Math.PI / 180
                      const isMajor = angle % 90 === 0
                      const isMinor = angle % 45 === 0
                      const r1 = isMajor ? 34 : isMinor ? 36 : 38
                      const r2 = 42
                      return (
                        <line key={i}
                          x1={46 + Math.cos(rad) * r1} y1={46 + Math.sin(rad) * r1}
                          x2={46 + Math.cos(rad) * r2} y2={46 + Math.sin(rad) * r2}
                          stroke="white" strokeOpacity={isMajor ? 0.5 : isMinor ? 0.3 : 0.1} strokeWidth={isMajor ? 2 : isMinor ? 1.2 : 0.6}
                        />
                      )
                    })}
                    {(['N', 'E', 'S', 'O'] as const).map((label, i) => {
                      const angle = i * 90
                      const rad = (angle - 90) * Math.PI / 180
                      const r = 27
                      return (
                        <text key={label} x={46 + Math.cos(rad) * r} y={46 + Math.sin(rad) * r}
                          textAnchor="middle" dominantBaseline="central"
                          fill="white" fillOpacity="0.6" fontSize="10" fontWeight="800">
                          {label}
                        </text>
                      )
                    })}
                    <g transform={`rotate(${dir + 180}, 46, 46)`}>
                      <path d="M46 10L39 60l7-7 7 7z" fill="white" fillOpacity="0.95" />
                    </g>
                    <circle cx="46" cy="46" r="3.5" fill="white" fillOpacity="0.9" />
                  </svg>
                </div>
                <div className="px-2.5 py-1 rounded-full bg-white/15 backdrop-blur-sm text-center">
                  <span className="text-[13px] font-extrabold text-white tracking-wide">{compass}</span>
                  <span className="text-[12px] font-semibold text-white/50 ml-1 tabular-nums">{Math.round(dir)}°</span>
                </div>
              </div>

              {/* Wind values */}
              <div className="flex-1 flex flex-col gap-3">
                {station.ts && (
                  <div className="flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-white/10 self-start">
                    <span className="w-1.5 h-1.5 rounded-full bg-[#34c759] animate-pulse" />
                    <span className="text-[11px] font-medium text-white/70 tabular-nums">
                      {(() => {
                        const diff = Math.floor((Date.now() - new Date(station.ts).getTime()) / 60000)
                        if (diff < 1) return "à l'instant"
                        if (diff < 60) return `il y a ${diff} min`
                        if (diff < 1440) return `il y a ${Math.floor(diff / 60)}h${diff % 60 > 0 ? String(diff % 60).padStart(2, '0') : ''}`
                        return `il y a ${Math.floor(diff / 1440)}j`
                      })()}
                    </span>
                  </div>
                )}
                <div>
                  <div className="text-[10px] font-semibold text-white/50 uppercase tracking-widest mb-0.5">Vent moyen</div>
                  <div className="flex items-baseline gap-1.5">
                    <span className="text-[44px] font-black text-white tabular-nums leading-none">{Math.round(station.wind)}</span>
                    <span className="text-[14px] font-semibold text-white/50">nds</span>
                  </div>
                </div>
                <div className="h-px bg-white/10" />
                <div>
                  <div className="text-[10px] font-semibold text-white/50 uppercase tracking-widest mb-0.5">Rafales</div>
                  <div className="flex items-baseline gap-1.5">
                    <span className="text-[32px] font-black text-white/80 tabular-nums leading-none">{Math.round(station.gust)}</span>
                    <span className="text-[13px] font-semibold text-white/40">nds</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Wind animation at bottom of hero */}
            <svg style={{ position: 'absolute', bottom: 0, left: 0, width: '100%', height: '33%', opacity: 0.1, zIndex: 0 }} viewBox="0 0 400 60" preserveAspectRatio="none">
              <path fill="white" opacity="0.5">
                <animate attributeName="d"
                  values="M0 35 C40 20 80 45 120 30 S200 15 240 30 S320 45 360 30 S400 20 400 30 V60 H0 Z;M0 30 C40 45 80 20 120 35 S200 45 240 30 S320 15 360 35 S400 45 400 30 V60 H0 Z;M0 35 C40 20 80 45 120 30 S200 15 240 30 S320 45 360 30 S400 20 400 30 V60 H0 Z"
                  dur="7s" repeatCount="indefinite" />
              </path>
              <path fill="white">
                <animate attributeName="d"
                  values="M0 38 C50 28 100 48 150 35 S250 22 300 38 S380 48 400 35 V60 H0 Z;M0 32 C50 45 100 25 150 38 S250 48 300 32 S380 22 400 38 V60 H0 Z;M0 38 C50 28 100 48 150 35 S250 22 300 38 S380 48 400 35 V60 H0 Z"
                  dur="5s" repeatCount="indefinite" />
              </path>
            </svg>
          </div>

          {/* Extra data — compact horizontal (only show non-zero values) */}
          {(hasTemp || hasHumidity || hasPressure) && (
            <div className="flex gap-2 mx-4 mb-3">
              {hasTemp && (
                <div className="flex-1 glass-card rounded-xl px-3 py-2 text-center">
                  <div className="text-[10px] font-semibold text-[#8e8e93] uppercase tracking-wide">Temp</div>
                  <div className="text-[18px] font-bold text-[#ff9500] tabular-nums leading-tight">{Math.round(station.temperature!)}°</div>
                </div>
              )}
              {hasHumidity && (
                <div className="flex-1 glass-card rounded-xl px-3 py-2 text-center">
                  <div className="text-[10px] font-semibold text-[#8e8e93] uppercase tracking-wide">Humid.</div>
                  <div className="text-[18px] font-bold text-[#007aff] tabular-nums leading-tight">{Math.round(station.humidity!)}%</div>
                </div>
              )}
              {hasPressure && (
                <div className="flex-1 glass-card rounded-xl px-3 py-2 text-center">
                  <div className="text-[10px] font-semibold text-[#8e8e93] uppercase tracking-wide">Pression</div>
                  <div className="text-[18px] font-bold text-[#5856d6] tabular-nums leading-tight">{Math.round(station.pressure!)}</div>
                </div>
              )}
            </div>
          )}

          {/* Chart header */}
          <div className="flex items-center justify-between px-4 mb-2">
            <span className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider">Historique</span>
            <div className="flex glass-card rounded-xl p-0.5">
              {[3, 6, 12, 24].map(h => (
                <button key={h} onClick={() => setHours(h)}
                  className={`px-2.5 py-1 text-[12px] font-semibold rounded-lg transition ${hours === h ? 'bg-white/80 text-[#1c1c1e] shadow-sm' : 'text-[#8e8e93]'}`}>
                  {h}h
                </button>
              ))}
            </div>
          </div>

          {/* Chart */}
          <div className="glass-card rounded-2xl mx-4 mb-4 p-3">
            <div className="h-44">
              {loading ? (
                <div className="w-full h-full flex items-center justify-center">
                  <div className="w-5 h-5 border-2 border-white/30 border-t-[#007aff] rounded-full animate-spin" />
                </div>
              ) : history.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={history} margin={{ top: 5, right: 5, left: -20, bottom: 5 }}>
                    <defs>
                      <linearGradient id="wg" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#007aff" stopOpacity={0.2} />
                        <stop offset="95%" stopColor="#007aff" stopOpacity={0} />
                      </linearGradient>
                      <linearGradient id="gg" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#ff3b30" stopOpacity={0.12} />
                        <stop offset="95%" stopColor="#ff3b30" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.05)" vertical={false} />
                    <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
                    <YAxis tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} width={30} />
                    <Tooltip content={<WindTooltip />} />
                    <Area type="monotone" dataKey="gust" stroke="#ff3b30" strokeWidth={1.5} fill="url(#gg)" dot={false} name="Rafales" />
                    <Area type="monotone" dataKey="wind" stroke="#007aff" strokeWidth={2} fill="url(#wg)" dot={false} name="Vent" />
                  </AreaChart>
                </ResponsiveContainer>
              ) : (
                <div className="w-full h-full flex items-center justify-center text-[#8e8e93] text-[15px]">Pas de donnees</div>
              )}
            </div>
            <div className="flex items-center justify-center gap-5 mt-2 text-[11px] font-medium text-[#8e8e93]">
              <div className="flex items-center gap-1.5"><span className="w-3 h-[2.5px] bg-[#007aff] rounded-full" />Vent</div>
              <div className="flex items-center gap-1.5"><span className="w-3 h-[2.5px] bg-[#ff3b30] rounded-full" />Rafales</div>
            </div>
          </div>

          {/* Forecast comparison */}
          {forecast && (
            <div className="mx-4 mb-3">
              <button onClick={() => setShowForecast(!showForecast)}
                className="w-full flex items-center justify-between glass-card rounded-xl px-3 py-2">
                <div className="flex items-center gap-2">
                  <svg className="w-3.5 h-3.5 text-[#ff9500] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path d="M3 3v18h18" /><path d="M7 16l4-8 4 4 5-10" /></svg>
                  <span className="text-[12px] font-semibold text-[#1c1c1e]">AROME vs Reel</span>
                  <span className="text-[11px] text-[#8e8e93]">±{forecast.meanError} nds · {forecast.withinTolerance}%</span>
                </div>
                <svg className={`w-3.5 h-3.5 text-[#8e8e93] transition-transform ${showForecast ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6" /></svg>
              </button>

              {showForecast && (
                <div className="glass-card rounded-2xl mt-2 p-3">
                  {/* Stats row */}
                  <div className="flex gap-2 mb-3">
                    <div className="flex-1 rounded-xl bg-white/60 px-2.5 py-2 text-center">
                      <div className="text-[10px] font-semibold text-[#8e8e93] uppercase">Err. moy</div>
                      <div className={`text-[18px] font-bold tabular-nums ${forecast.meanError < 3 ? 'text-[#34c759]' : forecast.meanError < 5 ? 'text-[#ff9500]' : 'text-[#ff3b30]'}`}>
                        {forecast.meanError}<span className="text-[11px] font-medium text-[#8e8e93] ml-0.5">nds</span>
                      </div>
                    </div>
                    <div className="flex-1 rounded-xl bg-white/60 px-2.5 py-2 text-center">
                      <div className="text-[10px] font-semibold text-[#8e8e93] uppercase">Err. max</div>
                      <div className="text-[18px] font-bold text-[#ff3b30] tabular-nums">
                        {forecast.maxError}<span className="text-[11px] font-medium text-[#8e8e93] ml-0.5">nds</span>
                      </div>
                    </div>
                    <div className="flex-1 rounded-xl bg-white/60 px-2.5 py-2 text-center">
                      <div className="text-[10px] font-semibold text-[#8e8e93] uppercase">±5 nds</div>
                      <div className={`text-[18px] font-bold tabular-nums ${forecast.withinTolerance >= 80 ? 'text-[#34c759]' : forecast.withinTolerance >= 60 ? 'text-[#ff9500]' : 'text-[#ff3b30]'}`}>
                        {forecast.withinTolerance}%
                      </div>
                    </div>
                    <div className="flex-1 rounded-xl bg-white/60 px-2.5 py-2 text-center">
                      <div className="text-[10px] font-semibold text-[#8e8e93] uppercase">Biais</div>
                      <div className="text-[18px] font-bold tabular-nums text-[#5856d6] flex items-center justify-center gap-0.5">
                        {forecast.bias > 0.5 ? '↑' : forecast.bias < -0.5 ? '↓' : '='}{Math.abs(forecast.bias)}
                      </div>
                    </div>
                  </div>

                  {/* Comparison chart */}
                  <div className="h-36">
                    <ResponsiveContainer width="100%" height="100%">
                      <AreaChart data={forecast.points} margin={{ top: 5, right: 5, left: -20, bottom: 5 }}>
                        <defs>
                          <linearGradient id="fg" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="5%" stopColor="#ff9500" stopOpacity={0.15} />
                            <stop offset="95%" stopColor="#ff9500" stopOpacity={0} />
                          </linearGradient>
                        </defs>
                        <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.05)" vertical={false} />
                        <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
                        <YAxis tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} width={30} />
                        <Tooltip contentStyle={{ background: 'rgba(255,255,255,0.9)', backdropFilter: 'blur(16px)', border: 'none', borderRadius: 12, fontSize: 12, boxShadow: '0 4px 16px rgba(0,0,0,0.1)' }} />
                        <Area type="monotone" dataKey="forecast" stroke="#ff9500" strokeWidth={1.5} strokeDasharray="5 3" fill="url(#fg)" dot={{ r: 2, fill: '#ff9500' }} name="AROME" />
                        <Area type="monotone" dataKey="actual" stroke="#007aff" strokeWidth={2} fill="none" dot={false} name="Reel" />
                      </AreaChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="flex items-center justify-center gap-5 mt-2 text-[11px] font-medium text-[#8e8e93]">
                    <div className="flex items-center gap-1.5"><span className="w-3 h-[2.5px] bg-[#007aff] rounded-full" />Reel</div>
                    <div className="flex items-center gap-1.5"><span className="w-3 h-[2.5px] bg-[#ff9500] rounded-full border-dashed" style={{ borderTop: '2px dashed #ff9500', height: 0, width: 12 }} />AROME</div>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Data timestamp */}
          {station.ts && (
            <div className="mx-4 mb-2 glass-card rounded-xl px-3 py-2 flex items-center gap-2">
              <svg className="w-4 h-4 text-[#8e8e93] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
              <span className="text-[12px] text-[#8e8e93]">
                Donnees du {new Date(station.ts).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                {' · '}{(() => {
                  const diff = Math.floor((Date.now() - new Date(station.ts).getTime()) / 60000)
                  if (diff < 1) return "à l'instant"
                  if (diff < 60) return `il y a ${diff} min`
                  if (diff < 1440) return `il y a ${Math.floor(diff / 60)}h${diff % 60 > 0 ? String(diff % 60).padStart(2, '0') : ''}`
                  return `il y a ${Math.floor(diff / 1440)}j`
                })()}
              </span>
            </div>
          )}

          {/* Footer: source + freshness + embed */}
          <div className="flex items-center justify-between px-4 pb-4 pt-1">
            <span className="text-[12px] font-bold px-2.5 py-0.5 rounded-full text-white" style={{ background: SOURCE_COLORS[station.source] || '#8e8e93' }}>
              {station.source}
            </span>
            <div className="flex items-center gap-3">
              <EmbedPicker type="station" id={station.stableId || station.id} />
              <div className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-[#34c759] animate-pulse" />
                <span className="text-[12px] text-[#8e8e93] tabular-nums">{ago}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}

// Compact inline tooltip with wind arrow
function WindTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null
  const wind = payload.find((p: any) => p.dataKey === 'wind')
  const gust = payload.find((p: any) => p.dataKey === 'gust')
  const dirVal = payload[0]?.payload?.dir

  return (
    <div style={{
      background: 'rgba(248,248,250,0.95)', backdropFilter: 'blur(16px)',
      borderRadius: 10, padding: '5px 12px', border: '0.5px solid rgba(0,0,0,0.06)',
      boxShadow: '0 2px 12px rgba(0,0,0,0.08)',
      display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
      transform: 'translateY(-10px)',
    }}>
      <span style={{ fontSize: 10, color: '#8e8e93', fontWeight: 600 }}>{label}</span>
      {dirVal !== undefined && dirVal !== null && (
        <svg width="16" height="16" viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
          <circle cx="8" cy="8" r="7" fill="none" stroke="#e5e5ea" strokeWidth="0.8" />
          <g transform={`rotate(${dirVal + 180}, 8, 8)`}>
            <path d="M8 2L6.5 12l1.5-1.5 1.5 1.5z" fill="#007aff" />
          </g>
        </svg>
      )}
      {wind && <>
        <span style={{ fontSize: 12, fontWeight: 800, color: '#007aff' }}>{wind.value}</span>
      </>}
      {gust && <>
        <span style={{ fontSize: 10, color: '#c7c7cc' }}>/</span>
        <span style={{ fontSize: 12, fontWeight: 800, color: '#ff3b30' }}>{gust.value}</span>
      </>}
      <span style={{ fontSize: 10, color: '#aeaeb2', fontWeight: 500 }}>nds</span>
      {dirVal !== undefined && dirVal !== null && (
        <span style={{ fontSize: 10, color: '#aeaeb2', fontWeight: 600 }}>{degToCompassFR(dirVal)}</span>
      )}
    </div>
  )
}
