'use client'

import { useState, useEffect, useMemo } from 'react'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import type { TidePort } from '@/store/appStore'
import type { TideEvent } from '@/lib/types'
import { getCoeffColor, getCoeffLabel, interpolateTideCurve, getTideState } from '@/lib/tide-utils'
import { API, apiFetch } from '@/lib/api'

interface TidePanelProps {
  port: TidePort
  onClose: () => void
}

interface TideData {
  tides: TideEvent[]
  nextHighTide?: { time: string; height: number; coefficient?: number }
  nextLowTide?: { time: string; height: number }
  todayCoefficient?: number
}

export function TidePanel({ port, onClose }: TidePanelProps) {
  const [data, setData] = useState<TideData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    setLoading(true)
    apiFetch(`${API}/tide?port=${encodeURIComponent(port.cst)}&duration=7`)
      .then(r => r.json())
      .then(d => {
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

  const tideState = useMemo(() => {
    if (!data?.tides.length) return null
    return getTideState(data.tides)
  }, [data?.tides])

  const todayTides = useMemo(() => {
    if (!data?.tides) return []
    const today = new Date().toISOString().slice(0, 10)
    return data.tides.filter(t => t.time.startsWith(today))
  }, [data?.tides])

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

  return (
    <div className="tide-panel-enter">
      {/* Header */}
      <div className="flex items-center justify-between px-3 pt-2.5 pb-1.5">
        <div className="flex items-center gap-2 min-w-0">
          <svg className="w-4 h-4 text-[#14b8a6] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" strokeLinecap="round">
            <path d="M2 10c2-3 4-3 6 0s4 3 6 0 4-3 6 0" />
            <path d="M2 16c2-3 4-3 6 0s4 3 6 0 4-3 6 0" />
          </svg>
          <span className="text-[14px] font-semibold text-[#1c1c1e] truncate">{port.name}</span>
        </div>
        <button onClick={onClose} className="w-6 h-6 rounded-full bg-[#e5e5ea]/60 flex items-center justify-center hover:bg-[#d1d1d6] transition flex-shrink-0">
          <svg className="w-3 h-3 text-[#8e8e93]" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24">
            <path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      {loading ? (
        <div className="px-4 py-8 flex items-center justify-center">
          <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#14b8a6] rounded-full animate-spin" />
        </div>
      ) : (
        <div className="px-3 pb-3">
          {/* Coefficient + State */}
          <div className="flex items-center gap-3 py-1.5">
            {todayCoeff > 0 && (
              <div className="flex items-baseline gap-1">
                <span className="text-[28px] font-black leading-none tabular-nums" style={{ color: coeffColor }}>{todayCoeff}</span>
                <div className="flex flex-col">
                  <span className="text-[9px] font-semibold text-[#8e8e93] uppercase">Coef</span>
                  <span className="text-[10px] font-bold" style={{ color: coeffColor }}>{coeffLabel}</span>
                </div>
              </div>
            )}
            {tideState && tideState.state && (
              <div className="flex flex-col gap-1 ml-auto">
                <div className="flex items-center gap-1.5">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke={tideState.state === 'Montante' ? '#3b82f6' : '#06b6d4'} strokeWidth="2.5" strokeLinecap="round">
                    {tideState.state === 'Montante'
                      ? <path d="M12 19V5M5 12l7-7 7 7" />
                      : <path d="M12 5v14M5 12l7 7 7-7" />
                    }
                  </svg>
                  <span className="text-[11px] font-bold text-[#1c1c1e]">{tideState.state}</span>
                </div>
                <div className="w-16 h-1.5 rounded-full bg-[#e5e5ea] overflow-hidden">
                  <div className="h-full rounded-full transition-all" style={{ width: `${Math.round(tideState.progress * 100)}%`, background: tideState.state === 'Montante' ? '#3b82f6' : '#06b6d4' }} />
                </div>
              </div>
            )}
          </div>

          {/* Next tides */}
          <div className="flex gap-1.5 mt-1">
            {data?.nextHighTide && (
              <div className="flex-1 bg-white/50 rounded-xl px-2.5 py-1.5">
                <div className="flex items-center gap-1">
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#3b82f6" strokeWidth="3" strokeLinecap="round"><path d="M12 19V5M5 12l7-7 7 7" /></svg>
                  <span className="text-[9px] font-semibold text-[#8e8e93] uppercase">PM</span>
                </div>
                <div className="text-[15px] font-bold text-[#3b82f6] tabular-nums">
                  {new Date(data.nextHighTide.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                </div>
                <div className="text-[10px] text-[#8e8e93] tabular-nums">{data.nextHighTide.height.toFixed(2)}m</div>
              </div>
            )}
            {data?.nextLowTide && (
              <div className="flex-1 bg-white/50 rounded-xl px-2.5 py-1.5">
                <div className="flex items-center gap-1">
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#06b6d4" strokeWidth="3" strokeLinecap="round"><path d="M12 5v14M5 12l7 7 7-7" /></svg>
                  <span className="text-[9px] font-semibold text-[#8e8e93] uppercase">BM</span>
                </div>
                <div className="text-[15px] font-bold text-[#06b6d4] tabular-nums">
                  {new Date(data.nextLowTide.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                </div>
                <div className="text-[10px] text-[#8e8e93] tabular-nums">{data.nextLowTide.height.toFixed(2)}m</div>
              </div>
            )}
          </div>

          {/* Chart */}
          {chartData.length > 0 && (
            <div className="mt-2.5">
              <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Courbe des marées</span>
              <div className="h-44 mt-1 -mx-1">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={chartData} margin={{ top: 16, right: 8, left: -16, bottom: 4 }}>
                    <defs>
                      <linearGradient id="tidePanelGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#14b8a6" stopOpacity={0.2} />
                        <stop offset="95%" stopColor="#14b8a6" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <XAxis
                      dataKey="time"
                      tick={{ fill: '#8e8e93', fontSize: 9 }}
                      tickLine={false}
                      axisLine={false}
                      tickFormatter={(v) => new Date(v).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                      interval={Math.floor(chartData.length / 5)}
                    />
                    <YAxis
                      tick={{ fill: '#8e8e93', fontSize: 9 }}
                      tickLine={false}
                      axisLine={false}
                      width={32}
                      unit="m"
                      domain={['dataMin - 0.5', 'dataMax + 0.5']}
                    />
                    <Tooltip content={<TideTooltip />} />
                    <ReferenceLine x={nowMs} stroke="#ff9500" strokeDasharray="4 3" strokeWidth={1.5} label={{ value: 'Maint.', position: 'top', fill: '#ff9500', fontSize: 9, fontWeight: 700 }} />
                    {tideMarkers.map((m, i) => (
                      <ReferenceLine
                        key={i}
                        x={m.time}
                        stroke={m.type === 'high' ? '#3b82f6' : '#06b6d4'}
                        strokeDasharray="2 4"
                        strokeWidth={0.8}
                        label={{
                          value: `${m.type === 'high' ? 'PM' : 'BM'} ${m.label}`,
                          position: m.type === 'high' ? 'top' : 'bottom',
                          fill: m.type === 'high' ? '#3b82f6' : '#06b6d4',
                          fontSize: 8,
                          fontWeight: 600,
                        }}
                      />
                    ))}
                    <Area type="monotone" dataKey="height" stroke="#14b8a6" strokeWidth={2} fill="url(#tidePanelGrad)" dot={false} />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          {/* Today's tides */}
          {todayTides.length > 0 && (
            <div className="mt-2">
              <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Marées du jour</span>
              <div className="mt-1 space-y-1">
                {todayTides.map((t, i) => {
                  const isHigh = t.type === 'high'
                  return (
                    <div key={i} className="flex items-center gap-2 bg-white/50 rounded-lg px-3 py-1.5">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke={isHigh ? '#3b82f6' : '#06b6d4'} strokeWidth="2.5" strokeLinecap="round">
                        {isHigh ? <path d="M12 19V5M5 12l7-7 7 7" /> : <path d="M12 5v14M5 12l7 7 7-7" />}
                      </svg>
                      <span className="text-[11px] font-bold text-[#1c1c1e] tabular-nums w-10">
                        {new Date(t.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                      </span>
                      <span className="text-[11px] font-semibold" style={{ color: isHigh ? '#3b82f6' : '#06b6d4' }}>
                        {isHigh ? 'PM' : 'BM'}
                      </span>
                      <span className="text-[11px] text-[#8e8e93] tabular-nums ml-auto">{t.height.toFixed(2)}m</span>
                      {t.coeff && (
                        <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-md text-white" style={{ background: getCoeffColor(t.coeff) }}>
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
                      className={`flex-shrink-0 w-[60px] rounded-lg px-1 py-1.5 text-center ${isToday ? 'bg-[#14b8a6]/10 ring-1 ring-[#14b8a6]/30' : 'bg-white/50'}`}>
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

          {/* SHOM badge */}
          <div className="mt-2 text-[9px] text-[#8e8e93] text-center">
            Données SHOM
          </div>
        </div>
      )}
    </div>
  )
}

function TideTooltip({ active, payload }: any) {
  if (!active || !payload?.length) return null
  const point = payload[0]
  return (
    <div style={{
      background: 'rgba(248,248,250,0.95)', backdropFilter: 'blur(16px)',
      borderRadius: 10, padding: '4px 10px', border: '0.5px solid rgba(0,0,0,0.06)',
      boxShadow: '0 2px 12px rgba(0,0,0,0.08)',
      display: 'flex', alignItems: 'center', gap: 5, whiteSpace: 'nowrap',
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
