'use client'

import { useState, useEffect, useMemo } from 'react'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import type { TidePort } from '@/store/appStore'
import type { TideEvent, TideChartPoint } from '@/lib/types'
import { getCoeffColor, getCoeffLabel, interpolateTideCurve, getTideState } from '@/lib/tide-utils'
import { API, apiFetch } from '@/lib/api'

interface Props {
  port: TidePort
  expanded: boolean
  onExpand: () => void
}

interface TideData {
  tides: TideEvent[]
  nextHighTide?: { time: string; height: number; coefficient?: number }
  nextLowTide?: { time: string; height: number }
  todayCoefficient?: number
}

export function TidePopupContent({ port, expanded, onExpand }: Props) {
  const [data, setData] = useState<TideData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    setLoading(true)
    apiFetch(`${API}/tide?port=${encodeURIComponent(port.cst)}&duration=7`)
      .then(r => r.json())
      .then(d => {
        // Map API fields to TideEvent format (datetime→time, coefficient→coeff)
        const tides: TideEvent[] = (d.tides || []).map((t: any) => ({
          type: t.type,
          time: t.datetime || t.time,
          height: t.height,
          coeff: t.coefficient ?? t.coeff,
        }))
        setData({
          tides,
          nextHighTide: d.nextHighTide,
          nextLowTide: d.nextLowTide,
          todayCoefficient: d.todayCoefficient,
        })
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [port.cst])

  const todayCoeff = data?.todayCoefficient ?? 0
  const coeffColor = todayCoeff > 0 ? getCoeffColor(todayCoeff) : '#8e8e93'
  const coeffLabel = todayCoeff > 0 ? getCoeffLabel(todayCoeff) : ''

  // Current tide state
  const tideState = useMemo(() => {
    if (!data?.tides.length) return null
    return getTideState(data.tides)
  }, [data?.tides])

  // Today's tides
  const todayTides = useMemo(() => {
    if (!data?.tides) return []
    const today = new Date().toISOString().slice(0, 10)
    return data.tides.filter(t => t.time.startsWith(today))
  }, [data?.tides])

  // Chart data — next 24h interpolated curve
  const chartData = useMemo(() => {
    if (!data?.tides.length) return []
    const now = Date.now()
    const in24h = now + 24 * 3600 * 1000
    const relevant = data.tides.filter(t => {
      const ts = new Date(t.time).getTime()
      return ts >= now - 6 * 3600 * 1000 && ts <= in24h
    })
    if (relevant.length < 2) return []
    return interpolateTideCurve(relevant, 96).map(p => ({
      time: p.time,
      height: Math.round(p.height * 100) / 100,
      label: new Date(p.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
    }))
  }, [data?.tides])

  // Tide event markers for chart
  const tideMarkers = useMemo(() => {
    if (!data?.tides.length) return []
    const now = Date.now()
    const in24h = now + 24 * 3600 * 1000
    return data.tides
      .filter(t => {
        const ts = new Date(t.time).getTime()
        return ts >= now - 6 * 3600 * 1000 && ts <= in24h
      })
      .map(t => ({
        time: new Date(t.time).getTime(),
        type: t.type,
        height: t.height,
        coeff: t.coeff,
        label: new Date(t.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
      }))
  }, [data?.tides])

  // Week overview — group by day with max coeff
  const weekDays = useMemo(() => {
    if (!data?.tides) return []
    const days: Record<string, { date: string; maxCoeff: number; count: number }> = {}
    for (const t of data.tides) {
      const d = t.time.slice(0, 10)
      if (!days[d]) days[d] = { date: d, maxCoeff: 0, count: 0 }
      days[d].count++
      if (t.coeff && t.coeff > days[d].maxCoeff) days[d].maxCoeff = t.coeff
    }
    return Object.values(days).sort((a, b) => a.date.localeCompare(b.date)).slice(0, 7)
  }, [data?.tides])

  const nowMs = Date.now()

  if (loading) {
    return (
      <div className="px-4 py-8 flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#14b8a6] rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div>
      {/* Hero */}
      <div className="px-4 py-3 relative overflow-hidden" style={{ background: 'linear-gradient(135deg, #14b8a6, #0f766e)' }}>
        <div className="glass-hero-shimmer" />
        <div className="text-[13px] font-semibold text-white/80 truncate relative">{port.name}</div>
        <div className="flex items-center gap-4 mt-1 relative">
          {/* Coefficient */}
          {todayCoeff > 0 && (
            <div className="flex items-baseline gap-1.5">
              <span className="text-[32px] font-black text-white leading-none">{todayCoeff}</span>
              <div className="flex flex-col">
                <span className="text-[10px] font-bold text-white/60 uppercase">Coeff</span>
                <span className="text-[11px] font-bold" style={{ color: coeffColor }}>{coeffLabel}</span>
              </div>
            </div>
          )}
          {/* Tide state */}
          {tideState && tideState.state && (
            <div className="flex flex-col gap-1 ml-auto">
              <div className="flex items-center gap-1.5">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round">
                  {tideState.state === 'Montante'
                    ? <path d="M12 19V5M5 12l7-7 7 7" />
                    : <path d="M12 5v14M5 12l7 7 7-7" />
                  }
                </svg>
                <span className="text-[12px] font-bold text-white">{tideState.state}</span>
              </div>
              <div className="w-20 h-1.5 rounded-full bg-white/20 overflow-hidden">
                <div className="h-full rounded-full bg-white/80 transition-all" style={{ width: `${Math.round(tideState.progress * 100)}%` }} />
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Next tides — compact */}
      <div className="px-3 pt-2 pb-1">
        <div className="flex gap-1.5">
          {data?.nextHighTide && (
            <div className="flex-1 rounded-xl px-2 py-1.5" style={{
              background: 'color-mix(in srgb, #007aff 6%, transparent)',
              backdropFilter: 'blur(12px) saturate(1.4)',
              WebkitBackdropFilter: 'blur(12px) saturate(1.4)',
              border: '0.5px solid color-mix(in srgb, #007aff 12%, transparent)',
              boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.15), 0 1px 3px rgba(0,0,0,0.04)',
            }}>
              <div className="flex items-center gap-1">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#007aff" strokeWidth="3" strokeLinecap="round"><path d="M12 19V5M5 12l7-7 7 7" /></svg>
                <span className="text-[9px] font-semibold text-[#8e8e93] uppercase">PM</span>
              </div>
              <div className="text-[16px] font-bold text-[#007aff] tabular-nums">
                {new Date(data.nextHighTide.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
              </div>
              <div className="text-[10px] text-[#8e8e93] tabular-nums">{data.nextHighTide.height.toFixed(2)}m</div>
            </div>
          )}
          {data?.nextLowTide && (
            <div className="flex-1 rounded-xl px-2 py-1.5" style={{
              background: 'color-mix(in srgb, #06b6d4 6%, transparent)',
              backdropFilter: 'blur(12px) saturate(1.4)',
              WebkitBackdropFilter: 'blur(12px) saturate(1.4)',
              border: '0.5px solid color-mix(in srgb, #06b6d4 12%, transparent)',
              boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.15), 0 1px 3px rgba(0,0,0,0.04)',
            }}>
              <div className="flex items-center gap-1">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#06b6d4" strokeWidth="3" strokeLinecap="round"><path d="M12 5v14M5 12l7 7 7-7" /></svg>
                <span className="text-[9px] font-semibold text-[#8e8e93] uppercase">BM</span>
              </div>
              <div className="text-[16px] font-bold text-[#06b6d4] tabular-nums">
                {new Date(data.nextLowTide.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
              </div>
              <div className="text-[10px] text-[#8e8e93] tabular-nums">{data.nextLowTide.height.toFixed(2)}m</div>
            </div>
          )}
        </div>
      </div>

      {/* Expanded */}
      {expanded && (
        <div className="px-3 pb-1">
          {/* Chart */}
          {chartData.length > 0 && (
            <div className="mt-2">
              <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Courbe des marées</span>
              <div className="h-40 mt-1">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={chartData} margin={{ top: 8, right: 4, left: -24, bottom: 0 }}>
                    <defs>
                      <linearGradient id="tideGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#14b8a6" stopOpacity={0.25} />
                        <stop offset="95%" stopColor="#14b8a6" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <XAxis
                      dataKey="time"
                      tick={{ fill: '#8e8e93', fontSize: 9 }}
                      tickLine={false}
                      axisLine={false}
                      tickFormatter={(v) => new Date(v).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                      interval={Math.floor(chartData.length / 6)}
                    />
                    <YAxis tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} width={28} unit="m" />
                    <Tooltip content={<TideTooltip />} />
                    <ReferenceLine x={nowMs} stroke="#ff9500" strokeDasharray="4 3" strokeWidth={1.5} label={{ value: 'Maint.', position: 'top', fill: '#ff9500', fontSize: 9, fontWeight: 700 }} />
                    {tideMarkers.map((m, i) => (
                      <ReferenceLine
                        key={i}
                        x={m.time}
                        stroke={m.type === 'high' ? '#007aff' : '#06b6d4'}
                        strokeDasharray="2 4"
                        strokeWidth={0.8}
                        label={{
                          value: `${m.type === 'high' ? 'PM' : 'BM'} ${m.label}`,
                          position: m.type === 'high' ? 'top' : 'bottom',
                          fill: m.type === 'high' ? '#007aff' : '#06b6d4',
                          fontSize: 8,
                          fontWeight: 600,
                        }}
                      />
                    ))}
                    <Area type="monotone" dataKey="height" stroke="#14b8a6" strokeWidth={2} fill="url(#tideGrad)" dot={false} />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {/* Today's tides list */}
          {todayTides.length > 0 && (
            <div className="mt-2">
              <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Marées du jour</span>
              <div className="mt-1 space-y-1">
                {todayTides.map((t, i) => {
                  const isHigh = t.type === 'high'
                  return (
                    <div key={i} className="flex items-center gap-2 glass-stat px-3 py-1.5">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={isHigh ? '#007aff' : '#06b6d4'} strokeWidth="2.5" strokeLinecap="round">
                        {isHigh ? <path d="M12 19V5M5 12l7-7 7 7" /> : <path d="M12 5v14M5 12l7 7 7-7" />}
                      </svg>
                      <span className="text-[11px] font-bold text-[#1c1c1e] tabular-nums w-10">
                        {new Date(t.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                      </span>
                      <span className="text-[11px] font-semibold" style={{ color: isHigh ? '#007aff' : '#06b6d4' }}>
                        {isHigh ? 'PM' : 'BM'}
                      </span>
                      <span className="text-[11px] text-[#8e8e93] tabular-nums ml-auto">{t.height.toFixed(2)}m</span>
                      {t.coeff && (
                        <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-md text-white glass-tag" style={{ background: getCoeffColor(t.coeff) }}>
                          {t.coeff}
                        </span>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          )}

          {/* Week overview */}
          {weekDays.length > 0 && (
            <div className="mt-2">
              <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Semaine</span>
              <div className="flex gap-1 mt-1 overflow-x-auto pb-1">
                {weekDays.map(day => {
                  const d = new Date(day.date)
                  const isToday = day.date === new Date().toISOString().slice(0, 10)
                  return (
                    <div key={day.date}
                      className={`flex-shrink-0 w-[60px] rounded-xl px-1 py-1.5 text-center ${isToday ? '' : 'glass-stat'}`}
                      style={isToday ? {
                        background: 'color-mix(in srgb, #14b8a6 10%, transparent)',
                        backdropFilter: 'blur(12px) saturate(1.5)',
                        WebkitBackdropFilter: 'blur(12px) saturate(1.5)',
                        border: '0.5px solid color-mix(in srgb, #14b8a6 25%, transparent)',
                        boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.15), 0 2px 8px rgba(20,184,166,0.12)',
                        borderRadius: 12,
                      } : undefined}>
                      <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">
                        {d.toLocaleDateString('fr-FR', { weekday: 'short' })}
                      </div>
                      <div className={`text-[14px] font-bold tabular-nums ${isToday ? 'text-[#14b8a6]' : 'text-[#1c1c1e]'}`}>
                        {d.getDate()}
                      </div>
                      {day.maxCoeff > 0 && (
                        <div className="text-[10px] font-bold tabular-nums mt-0.5" style={{ color: getCoeffColor(day.maxCoeff) }}>
                          {day.maxCoeff}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          )}

          {/* Source */}
          <div className="mt-2 text-[9px] text-[#8e8e93] text-center">
            Données SHOM · Service Hydrographique et Océanographique de la Marine
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="px-3 py-2 flex items-center justify-between glass-footer">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white glass-tag" style={{ background: '#14b8a6' }}>
          SHOM
        </span>
        {!expanded ? (
          <button onClick={onExpand}
            className="text-[12px] font-semibold text-[#14b8a6] px-2.5 py-1 rounded-full glass-action-btn flex items-center gap-0.5"
            style={{
              background: 'color-mix(in srgb, #14b8a6 8%, transparent)',
              boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #14b8a6 20%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)',
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

function TideTooltip({ active, payload }: any) {
  if (!active || !payload?.length) return null
  const point = payload[0]
  return (
    <div style={{
      background: 'rgba(248,248,250,0.75)', backdropFilter: 'blur(24px) saturate(1.8)',
      WebkitBackdropFilter: 'blur(24px) saturate(1.8)',
      borderRadius: 12, padding: '5px 12px', border: '0.5px solid rgba(255,255,255,0.5)',
      boxShadow: '0 4px 16px rgba(0,0,0,0.1), inset 0 1px 0 rgba(255,255,255,0.6), inset 0 0 0 0.5px rgba(255,255,255,0.3)',
      display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
      transform: 'translateY(-8px)',
    }}>
      <span style={{ fontSize: 9, color: '#8e8e93', fontWeight: 600 }}>
        {new Date(point.payload.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
      </span>
      <span style={{ fontSize: 11, fontWeight: 800, color: '#14b8a6' }}>{point.value.toFixed(2)}</span>
      <span style={{ fontSize: 9, color: '#aeaeb2', fontWeight: 500 }}>m</span>
    </div>
  )
}
