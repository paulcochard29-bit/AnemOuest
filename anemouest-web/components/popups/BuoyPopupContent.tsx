'use client'

import { useState, useEffect } from 'react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import type { WaveBuoy } from '@/store/appStore'
import type { MarinePoint } from '@/lib/types'
import { getWaveColor, degToCompassFR, haversineDistance } from '@/lib/utils'
import { fetchMarineForecast } from '@/lib/forecast-api'
import { API, apiFetch } from '@/lib/api'

interface Props {
  buoy: WaveBuoy
  expanded: boolean
  onExpand: () => void
  onForecast?: (lat: number, lon: number, name: string) => void
}

interface HistoryPoint { time: string; hm0: number; hmax?: number; tp?: number; rawTs?: number }

export function BuoyPopupContent({ buoy, expanded, onExpand, onForecast }: Props) {
  const wc = getWaveColor(buoy.hm0)
  const compass = degToCompassFR(buoy.direction ?? 0)
  const [history, setHistory] = useState<HistoryPoint[]>([])
  const [loading, setLoading] = useState(true)
  const [tideEvents, setTideEvents] = useState<{ type: string; time: string; height: number; coeff?: number }[]>([])
  const [tidePortName, setTidePortName] = useState('')
  const [marineForecast, setMarineForecast] = useState<MarinePoint[]>([])
  const [marineLoading, setMarineLoading] = useState(false)

  useEffect(() => {
    apiFetch(`${API}/candhis?id=${buoy.id}&history=true`)
      .then(r => r.json())
      .then(data => {
        if (data.history && data.history.length > 0) {
          setHistory(data.history.slice(-48).map((h: any) => {
            const d = new Date(h.timestamp)
            return {
              time: d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
              hm0: h.hm0,
              hmax: h.hmax,
              tp: h.tp,
              rawTs: d.getTime(),
            }
          }))
        }
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [buoy.id])

  // Fetch nearest tide port data
  useEffect(() => {
    apiFetch(`${API}/tide?list=true`)
      .then(r => r.json())
      .then(data => {
        const ports = data.ports || []
        if (ports.length === 0) return
        let nearest = ports[0]
        let minDist = haversineDistance(buoy.lat, buoy.lon, nearest.lat, nearest.lon)
        for (const p of ports) {
          const d = haversineDistance(buoy.lat, buoy.lon, p.lat, p.lon)
          if (d < minDist) { nearest = p; minDist = d }
        }
        if (minDist > 100) return
        setTidePortName(nearest.name)
        return apiFetch(`${API}/tide?port=${encodeURIComponent(nearest.cst)}`)
      })
      .then(r => r?.json())
      .then(data => {
        if (!data?.tides) return
        const events = data.tides.map((t: any) => ({
          type: t.type === 'high' ? 'PM' : t.type === 'low' ? 'BM' : t.type,
          time: t.datetime || t.time,
          height: t.height,
          coeff: t.coefficient ?? t.coeff,
        }))
        setTideEvents(events)
      })
      .catch(() => {})
  }, [buoy.lat, buoy.lon])

  // Fetch marine forecast when expanded
  useEffect(() => {
    if (!expanded || marineForecast.length > 0) return
    setMarineLoading(true)
    fetchMarineForecast(buoy.lat, buoy.lon)
      .then(data => setMarineForecast(data.points))
      .catch(() => {})
      .finally(() => setMarineLoading(false))
  }, [expanded, buoy.lat, buoy.lon, marineForecast.length])

  // Find midnight crossings for day separators
  const midnights = history.reduce<{ time: string; label: string }[]>((acc, pt, i) => {
    if (i === 0 || !pt.rawTs || !history[i - 1].rawTs) return acc
    const prevDate = new Date(history[i - 1].rawTs!).getDate()
    const curDate = new Date(pt.rawTs!).getDate()
    if (curDate !== prevDate) {
      const dayName = new Date(pt.rawTs!).toLocaleDateString('fr-FR', { weekday: 'short' })
      acc.push({ time: pt.time, label: dayName })
    }
    return acc
  }, [])

  const tickInterval = history.length > 0 ? Math.max(1, Math.floor(history.length / 6)) : 1

  return (
    <div>
      {/* Hero */}
      <div className="px-4 py-3 relative overflow-hidden" style={{ background: `linear-gradient(135deg, ${wc}, #1a3a5c)` }}>
        <div className="glass-hero-shimmer" />
        <div className="text-[13px] font-semibold text-white/80 truncate relative">{buoy.name}</div>
        <div className="flex items-center gap-3 mt-1 relative">
          <div className="flex items-baseline gap-1.5">
            <span className="text-[32px] font-black text-white leading-none">{buoy.hm0.toFixed(1)}</span>
            <span className="text-[13px] font-bold text-white/60">m</span>
          </div>
          <div className="flex flex-col gap-0.5 text-[12px] font-semibold text-white/80">
            <span>{Math.round(buoy.tp)}s</span>
          </div>
          {buoy.direction !== undefined && buoy.direction !== null && (
            <div className="flex flex-col items-center gap-0.5 ml-auto">
              <svg width="28" height="28" viewBox="0 0 32 32" style={{ transform: `rotate(${(buoy.direction ?? 0) + 180}deg)` }}>
                <path d="M16 4L10 26l6-4 6 4z" fill="#fff" stroke="rgba(255,255,255,0.3)" strokeWidth="0.5" strokeLinejoin="round" />
              </svg>
              <span className="text-[10px] font-bold text-white/70">{compass} {Math.round(buoy.direction)}°</span>
            </div>
          )}
        </div>
      </div>

      {/* Chart */}
      <div className="px-3 pt-2 pb-1">
        <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Historique 48h</span>
        <div className="h-40 mt-1">
          {loading ? (
            <div className="w-full h-full flex items-center justify-center">
              <div className="w-4 h-4 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
            </div>
          ) : history.length > 0 ? (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={history} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
                <defs>
                  <linearGradient id="bwg" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={wc} stopOpacity={0.25} />
                    <stop offset="95%" stopColor={wc} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.05)" vertical={false} />
                <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} interval={tickInterval} />
                <YAxis tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} width={28} domain={[0, 'auto']} />
                <Tooltip content={<WaveTooltip wc={wc} />} />
                {midnights.map(m => (
                  <ReferenceLine key={m.time} x={m.time} stroke="#c7c7cc" strokeDasharray="4 3" strokeWidth={1} label={{ value: m.label, position: 'top', fill: '#8e8e93', fontSize: 9, fontWeight: 600 }} />
                ))}
                {history[0]?.hmax !== undefined && (
                  <Area type="monotone" dataKey="hmax" stroke="#ff3b30" strokeWidth={1} fill="none" dot={false} strokeDasharray="3 3" name="Hmax" />
                )}
                <Area type="monotone" dataKey="hm0" stroke={wc} strokeWidth={2} fill="url(#bwg)" dot={false} name="H1/3" />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="w-full h-full flex items-center justify-center text-[#8e8e93] text-[12px]">Pas de données</div>
          )}
        </div>
      </div>

      {/* Expanded: extra details */}
      {expanded && (
        <div className="px-3 pb-1">
          <div className="flex gap-1.5 mb-2">
            <div className="flex-1 glass-stat px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Hmax</div>
              <div className="text-[16px] font-bold text-[#ff3b30] tabular-nums">{buoy.hmax.toFixed(1)}m</div>
            </div>
            <div className="flex-1 glass-stat px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Période</div>
              <div className="text-[16px] font-bold text-[#007aff] tabular-nums">{buoy.tp.toFixed(1)}s</div>
            </div>
            {buoy.seaTemp > 0 && (
              <div className="flex-1 glass-stat px-2 py-1.5 text-center">
                <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Temp. mer</div>
                <div className="text-[16px] font-bold text-[#34aadc] tabular-nums">{buoy.seaTemp.toFixed(1)}°</div>
              </div>
            )}
            {buoy.depth && (
              <div className="flex-1 glass-stat px-2 py-1.5 text-center">
                <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Prof.</div>
                <div className="text-[16px] font-bold text-[#5856d6] tabular-nums">{buoy.depth}m</div>
              </div>
            )}
          </div>
          {buoy.lastUpdate && (
            <div className="glass-stat px-3 py-1.5 flex items-center gap-2 mb-1">
              <svg className="w-3.5 h-3.5 text-[#8e8e93] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
              <span className="text-[11px] text-[#8e8e93]">
                {new Date(buoy.lastUpdate).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          )}

          {/* Swell decomposition */}
          {(() => {
            const now = new Date()
            const currentMarine = marineForecast.find(p => {
              const t = new Date(p.time)
              return Math.abs(t.getTime() - now.getTime()) < 2 * 3600000
            })
            const next12h = marineForecast.filter(p => {
              const t = new Date(p.time).getTime()
              return t >= now.getTime() && t <= now.getTime() + 12 * 3600000
            })

            return (
              <div className="mt-2 mb-1">
                <div className="flex items-center gap-2 mb-1.5">
                  <svg className="w-3.5 h-3.5" style={{ color: '#6366f1' }} fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" strokeLinecap="round">
                    <path d="M2 6c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /><path d="M2 12c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /><path d="M2 18c2-3 4-3 6 0s4 3 6 0 4-3 6 0" />
                  </svg>
                  <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Décomposition houle</span>
                </div>

                {marineLoading ? (
                  <div className="flex items-center justify-center py-3">
                    <div className="w-4 h-4 border-2 border-[#e5e5ea] border-t-[#6366f1] rounded-full animate-spin" />
                  </div>
                ) : currentMarine ? (
                  <>
                    {/* Current swell vs wind waves */}
                    <div className="flex gap-1.5 mb-1.5">
                      {/* Swell */}
                      <div className="flex-1 rounded-xl px-2 py-2 text-center" style={{
                        background: 'color-mix(in srgb, #6366f1 8%, transparent)',
                        backdropFilter: 'blur(8px) saturate(1.3)',
                        WebkitBackdropFilter: 'blur(8px) saturate(1.3)',
                        boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #6366f1 18%, transparent), inset 0 1px 0 rgba(255,255,255,0.12)',
                      }}>
                        <div className="text-[9px] font-bold text-[#6366f1] uppercase tracking-wider mb-1">Houle</div>
                        <div className="flex items-center justify-center gap-1.5">
                          {currentMarine.swellDirection > 0 && (
                            <svg width="18" height="18" viewBox="0 0 24 24" style={{ transform: `rotate(${currentMarine.swellDirection + 180}deg)`, color: '#6366f1' }}>
                              <path d="M12 2L7 18h10z" fill="currentColor" opacity="0.7" />
                            </svg>
                          )}
                          <div>
                            <span className="text-[18px] font-black text-[#6366f1] leading-none">{currentMarine.swellHeight.toFixed(1)}</span>
                            <span className="text-[10px] font-bold text-[#6366f1]/60 ml-0.5">m</span>
                          </div>
                        </div>
                        <div className="flex items-center justify-center gap-1.5 mt-1 text-[10px] font-semibold text-[#8e8e93]">
                          <span>{currentMarine.swellPeriod.toFixed(0)}s</span>
                          {currentMarine.swellDirection > 0 && <span>{degToCompassFR(currentMarine.swellDirection)}</span>}
                        </div>
                      </div>

                      {/* Wind waves */}
                      <div className="flex-1 rounded-xl px-2 py-2 text-center" style={{
                        background: 'color-mix(in srgb, #0ea5e9 8%, transparent)',
                        backdropFilter: 'blur(8px) saturate(1.3)',
                        WebkitBackdropFilter: 'blur(8px) saturate(1.3)',
                        boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #0ea5e9 18%, transparent), inset 0 1px 0 rgba(255,255,255,0.12)',
                      }}>
                        <div className="text-[9px] font-bold text-[#0ea5e9] uppercase tracking-wider mb-1">Mer du vent</div>
                        <div className="flex items-center justify-center gap-1.5">
                          {currentMarine.windWaveDirection > 0 && (
                            <svg width="18" height="18" viewBox="0 0 24 24" style={{ transform: `rotate(${currentMarine.windWaveDirection + 180}deg)`, color: '#0ea5e9' }}>
                              <path d="M12 2L7 18h10z" fill="currentColor" opacity="0.7" />
                            </svg>
                          )}
                          <div>
                            <span className="text-[18px] font-black text-[#0ea5e9] leading-none">{currentMarine.windWaveHeight.toFixed(1)}</span>
                            <span className="text-[10px] font-bold text-[#0ea5e9]/60 ml-0.5">m</span>
                          </div>
                        </div>
                        <div className="flex items-center justify-center gap-1.5 mt-1 text-[10px] font-semibold text-[#8e8e93]">
                          <span>{currentMarine.windWavePeriod.toFixed(0)}s</span>
                          {currentMarine.windWaveDirection > 0 && <span>{degToCompassFR(currentMarine.windWaveDirection)}</span>}
                        </div>
                      </div>
                    </div>

                    {/* 12h forecast mini timeline */}
                    {next12h.length > 2 && (
                      <div className="glass-stat px-2 py-1.5">
                        <div className="text-[9px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1">Prochaines 12h</div>
                        <div className="flex items-end gap-0.5" style={{ height: 36 }}>
                          {next12h.filter((_, i) => i % 2 === 0).map((mp, i) => {
                            const maxH = Math.max(...next12h.map(p => p.waveHeight), 1)
                            const swellPct = mp.waveHeight > 0 ? mp.swellHeight / mp.waveHeight : 0
                            const totalPct = mp.waveHeight / maxH
                            const h = new Date(mp.time).getHours()
                            return (
                              <div key={i} className="flex-1 flex flex-col items-center gap-0.5">
                                <div className="w-full flex flex-col items-center" style={{ height: 28 }}>
                                  <div className="w-full rounded-t-sm" style={{
                                    height: `${Math.max(2, totalPct * 28 * (1 - swellPct))}px`,
                                    background: '#0ea5e9',
                                    opacity: 0.5,
                                    marginTop: 'auto',
                                  }} />
                                  <div className="w-full rounded-b-sm" style={{
                                    height: `${Math.max(2, totalPct * 28 * swellPct)}px`,
                                    background: '#6366f1',
                                    opacity: 0.6,
                                  }} />
                                </div>
                                <span className="text-[8px] text-[#8e8e93] font-semibold tabular-nums">{h}h</span>
                              </div>
                            )
                          })}
                        </div>
                        <div className="flex items-center justify-center gap-3 mt-1">
                          <span className="flex items-center gap-1 text-[8px] font-semibold text-[#6366f1]">
                            <span className="w-2 h-2 rounded-sm" style={{ background: '#6366f1', opacity: 0.6 }} /> Houle
                          </span>
                          <span className="flex items-center gap-1 text-[8px] font-semibold text-[#0ea5e9]">
                            <span className="w-2 h-2 rounded-sm" style={{ background: '#0ea5e9', opacity: 0.5 }} /> Mer du vent
                          </span>
                        </div>
                      </div>
                    )}
                  </>
                ) : (
                  <div className="text-[11px] text-[#8e8e93] text-center py-2">Données non disponibles</div>
                )}
              </div>
            )
          })()}

          {/* Tide section */}
          {tideEvents.length > 0 && (() => {
            const now = new Date()
            const upcoming = tideEvents
              .filter(e => new Date(e.time) > now)
              .slice(0, 4)
            if (upcoming.length === 0) return null
            // Determine current tide state
            const lastPast = [...tideEvents].reverse().find(e => new Date(e.time) <= now)
            const tideState = lastPast?.type === 'PM' ? 'Descendante' : lastPast?.type === 'BM' ? 'Montante' : ''
            const stateColor = lastPast?.type === 'PM' ? '#ff9500' : '#14b8a6'
            return (
              <div className="mt-2 mb-1">
                <div className="flex items-center gap-2 mb-1.5">
                  <svg className="w-3.5 h-3.5 text-[#14b8a6]" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" strokeLinecap="round"><path d="M2 10c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /><path d="M2 16c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /></svg>
                  <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Marée · {tidePortName}</span>
                  {tideState && (
                    <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full ml-auto glass-tag" style={{ color: stateColor, background: `${stateColor}18` }}>{tideState}</span>
                  )}
                </div>
                <div className="flex gap-1">
                  {upcoming.map((e, i) => {
                    const d = new Date(e.time)
                    const isPM = e.type === 'PM'
                    return (
                      <div key={i} className="flex-1 rounded-xl px-1.5 py-1.5 text-center" style={{
                        background: isPM ? 'color-mix(in srgb, #14b8a6 8%, transparent)' : 'color-mix(in srgb, #007aff 6%, transparent)',
                        backdropFilter: 'blur(8px) saturate(1.3)',
                        WebkitBackdropFilter: 'blur(8px) saturate(1.3)',
                        boxShadow: `inset 0 0 0 0.5px ${isPM ? 'color-mix(in srgb, #14b8a6 15%, transparent)' : 'color-mix(in srgb, #007aff 12%, transparent)'}, inset 0 1px 0 rgba(255,255,255,0.12)`,
                      }}>
                        <div className="flex items-center justify-center gap-0.5 mb-0.5">
                          <svg className="w-2.5 h-2.5" fill="none" stroke={isPM ? '#14b8a6' : '#007aff'} strokeWidth="2.5" viewBox="0 0 24 24" strokeLinecap="round">
                            <path d={isPM ? 'M12 19V5M5 12l7-7 7 7' : 'M12 5v14M5 12l7 7 7-7'} />
                          </svg>
                          <span className="text-[9px] font-bold" style={{ color: isPM ? '#14b8a6' : '#007aff' }}>{isPM ? 'PM' : 'BM'}</span>
                        </div>
                        <div className="text-[13px] font-bold text-[#1c1c1e] tabular-nums">{d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}</div>
                        <div className="text-[10px] font-semibold text-[#8e8e93] tabular-nums">{e.height.toFixed(1)}m</div>
                        {e.coeff && <div className="text-[9px] font-bold text-[#af52de] tabular-nums">C{e.coeff}</div>}
                      </div>
                    )
                  })}
                </div>
              </div>
            )
          })()}
        </div>
      )}

      {/* Forecast button */}
      {onForecast && (
        <div className="mx-3 mb-1.5">
          <button onClick={() => onForecast(buoy.lat, buoy.lon, buoy.name)}
            className="w-full py-2.5 rounded-full text-[13px] font-bold flex items-center justify-center gap-1.5 active:scale-[0.98] transition-all duration-200"
            style={{
              color: '#34c759',
              background: 'color-mix(in srgb, #34c759 8%, transparent)',
              backdropFilter: 'blur(12px) saturate(150%)',
              WebkitBackdropFilter: 'blur(12px) saturate(150%)',
              boxShadow: 'inset 0 0 0 1px color-mix(in srgb, #34c759 20%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15), 0 2px 8px rgba(52,199,89,0.1)',
            }}>
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" strokeLinecap="round" strokeLinejoin="round"><path d="M3 17l4-9 4 5 4-7 6 11" /></svg>
            Prévisions multi-modèles
          </button>
        </div>
      )}

      {/* Footer */}
      <div className="px-3 py-2 flex items-center justify-between glass-footer">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white glass-tag" style={{ background: '#007aff' }}>CANDHIS</span>
        {!expanded ? (
          <button onClick={onExpand}
            className="text-[12px] font-semibold text-[#007aff] px-2.5 py-1 rounded-full glass-action-btn flex items-center gap-0.5"
            style={{
              background: 'color-mix(in srgb, #007aff 8%, transparent)',
              boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #007aff 20%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)',
            }}>
            Voir plus
            <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
          </button>
        ) : (
          <button onClick={onExpand}
            className="text-[12px] font-semibold text-[#8e8e93] px-2.5 py-1 rounded-full glass-action-btn flex items-center gap-0.5"
            style={{
              background: 'color-mix(in srgb, var(--text-primary) 5%, transparent)',
              boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, var(--text-primary) 10%, transparent), inset 0 1px 0 rgba(255,255,255,0.1)',
            }}>
            Réduire
            <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M6 9l6 6 6-6" /></svg>
          </button>
        )}
      </div>
    </div>
  )
}

function WaveTooltip({ active, payload, label, wc }: any) {
  if (!active || !payload?.length) return null
  const hm0 = payload.find((p: any) => p.dataKey === 'hm0')
  const hmax = payload.find((p: any) => p.dataKey === 'hmax')
  const tpVal = payload[0]?.payload?.tp

  return (
    <div style={{
      background: 'rgba(248,248,250,0.75)', backdropFilter: 'blur(24px) saturate(1.8)',
      WebkitBackdropFilter: 'blur(24px) saturate(1.8)',
      borderRadius: 12, padding: '5px 12px', border: '0.5px solid rgba(255,255,255,0.5)',
      boxShadow: '0 4px 16px rgba(0,0,0,0.1), inset 0 1px 0 rgba(255,255,255,0.6), inset 0 0 0 0.5px rgba(255,255,255,0.3)',
      display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
      transform: 'translateY(-8px)',
    }}>
      <span style={{ fontSize: 9, color: '#8e8e93', fontWeight: 600 }}>{label}</span>
      {hm0 && <span style={{ fontSize: 11, fontWeight: 800, color: wc }}>{hm0.value.toFixed(1)}</span>}
      {hmax && <>
        <span style={{ fontSize: 9, color: '#c7c7cc' }}>/</span>
        <span style={{ fontSize: 11, fontWeight: 800, color: '#ff3b30' }}>{hmax.value.toFixed(1)}</span>
      </>}
      <span style={{ fontSize: 9, color: '#aeaeb2', fontWeight: 500 }}>m</span>
      {tpVal !== undefined && <>
        <span style={{ fontSize: 9, color: '#c7c7cc' }}>·</span>
        <span style={{ fontSize: 11, fontWeight: 700, color: '#007aff' }}>{Math.round(tpVal)}s</span>
      </>}
    </div>
  )
}
