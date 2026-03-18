'use client'

import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { fetchWindForecast, fetchMarineForecast, MODEL_LABELS } from '@/lib/forecast-api'
import { getWindColor, getWaveColor, degToCompassFR } from '@/lib/utils'
import { getWeatherIcon } from '@/lib/types'
import type { ForecastModel, ForecastPoint, ForecastResponse, MarinePoint, MarineResponse } from '@/lib/types'

// ===== Color helpers =====

function windBg(kts: number): string {
  if (kts < 3) return 'transparent'
  return getWindColor(kts) + '40'
}

function windText(kts: number): string {
  // High contrast: dark text on light colors, white on strong colors
  if (kts < 7) return '#1a5568'
  if (kts < 11) return '#0e6474'
  if (kts < 17) return '#15603a'
  if (kts < 22) return '#6b5b0a'
  if (kts < 28) return '#7c4a08'
  return '#fff'
}

function waveBg(m: number): string {
  if (m <= 0) return 'transparent'
  return getWaveColor(m) + '40'
}

function waveText(m: number): string {
  if (m < 1.0) return '#1e4a8a'
  if (m < 1.5) return '#0e6474'
  if (m < 2.0) return '#15603a'
  if (m < 2.5) return '#7c4a08'
  return '#991b1b'
}

function tempColor(t: number): string {
  if (t < 0) return '#818cf8'
  if (t < 5) return '#93c5fd'
  if (t < 10) return '#67e8f9'
  if (t < 15) return '#86efac'
  if (t < 20) return '#fde047'
  if (t < 25) return '#fdba74'
  if (t < 30) return '#fb923c'
  return '#f87171'
}

function precipBg(mm: number): string {
  if (mm <= 0) return 'transparent'
  if (mm < 1) return '#dbeafe'
  if (mm < 3) return '#93c5fd'
  if (mm < 8) return '#60a5fa'
  return '#3b82f6'
}

// ===== Direction arrow =====

function DirArrow({ deg, size = 12 }: { deg: number; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ transform: `rotate(${deg + 180}deg)`, opacity: 0.65 }}>
      <path d="M12 2L6 18h12z" fill="currentColor" />
    </svg>
  )
}

// ===== Group hours by day =====

interface DayGroup {
  label: string
  hours: number
}

function groupByDay(times: string[]): DayGroup[] {
  const DAYS = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam']
  const groups: DayGroup[] = []
  let current = ''
  let count = 0
  for (const t of times) {
    const dateStr = t.slice(0, 10)
    if (dateStr !== current) {
      if (current) {
        const d = new Date(current + 'T12:00')
        groups.push({ label: `${DAYS[d.getDay()]} ${d.getDate()}`, hours: count })
      }
      current = dateStr
      count = 0
    }
    count++
  }
  if (current && count > 0) {
    const d = new Date(current + 'T12:00')
    groups.push({ label: `${DAYS[d.getDay()]} ${d.getDate()}`, hours: count })
  }
  return groups
}

const MODELS: ForecastModel[] = ['arome', 'ecmwf', 'gfs', 'icon']
const CW = 48 // cell width

// ===== Row renderers =====

type RowDef = {
  id: string
  label: string
  height: number
  render: (p: ForecastPoint, mp?: MarinePoint) => React.ReactNode
}

function makeRows(showMarine: boolean): RowDef[] {
  const rows: RowDef[] = [
    {
      id: 'weather', label: '', height: 26,
      render: (p) => <span className="text-[15px] leading-none">{getWeatherIcon(p.weatherCode)}</span>,
    },
    {
      id: 'wind', label: 'Vent', height: 30,
      render: (p) => (
        <div className="w-full h-full flex items-center justify-center" style={{ background: p.windSpeed >= 28 ? getWindColor(p.windSpeed) : windBg(p.windSpeed) }}>
          <span className="text-[14px] font-bold" style={{ color: windText(p.windSpeed) }}>{Math.round(p.windSpeed)}</span>
        </div>
      ),
    },
    {
      id: 'gust', label: 'Raf.', height: 28,
      render: (p) => (
        <div className="w-full h-full flex items-center justify-center" style={{ background: p.windGust >= 28 ? getWindColor(p.windGust) : windBg(p.windGust) }}>
          <span className="text-[13px] font-bold" style={{ color: windText(p.windGust) }}>{Math.round(p.windGust)}</span>
        </div>
      ),
    },
    {
      id: 'dir', label: 'Dir.', height: 34,
      render: (p) => (
        <div className="flex flex-col items-center justify-center gap-0.5">
          <DirArrow deg={p.windDirection} size={14} />
          <span className="text-[10px] font-medium text-[var(--text-secondary)] leading-none">{degToCompassFR(p.windDirection)}</span>
        </div>
      ),
    },
    {
      id: 'temp', label: '°C', height: 28,
      render: (p) => <span className="text-[13px] font-bold" style={{ color: tempColor(p.temperature) }}>{Math.round(p.temperature)}°</span>,
    },
    {
      id: 'precip', label: 'Pluie', height: 26,
      render: (p) => p.precipitation > 0.05 ? (
        <div className="w-full h-full flex items-center justify-center" style={{ background: precipBg(p.precipitation) }}>
          <span className="text-[12px] font-semibold text-blue-700 dark:text-blue-300">{p.precipitation.toFixed(1)}</span>
        </div>
      ) : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
    },
    {
      id: 'cloud', label: 'Nua.', height: 26,
      render: (p) => {
        const total = Math.max(p.cloudCoverHigh, p.cloudCoverMid, p.cloudCoverLow)
        const gray = Math.round(240 - (total / 100) * 110)
        return (
          <div className="w-full h-full flex items-center justify-center" style={{ background: `rgb(${gray},${gray},${gray})` }}>
            <span className="text-[12px] font-semibold" style={{ color: total > 60 ? '#fff' : '#444' }}>{Math.round(total)}%</span>
          </div>
        )
      },
    },
    {
      id: 'uv', label: 'UV', height: 26,
      render: (p) => {
        const uv = p.uvIndex
        if (uv <= 0) return <span className="text-[11px] text-[var(--text-tertiary)]">-</span>
        const uvColor = uv < 3 ? '#34c759' : uv < 6 ? '#ffd60a' : uv < 8 ? '#ff9500' : uv < 11 ? '#ff3b30' : '#af52de'
        const uvBg = uv < 3 ? 'transparent' : uv < 6 ? '#ffd60a25' : uv < 8 ? '#ff950030' : uv < 11 ? '#ff3b3035' : '#af52de35'
        return (
          <div className="w-full h-full flex items-center justify-center" style={{ background: uvBg }}>
            <span className="text-[12px] font-bold" style={{ color: uvColor }}>{Math.round(uv)}</span>
          </div>
        )
      },
    },
  ]

  if (showMarine) {
    rows.push(
      {
        id: 'wave', label: 'Vag.', height: 30,
        render: (_, mp) => mp && mp.waveHeight > 0 ? (
          <div className="w-full h-full flex items-center justify-center" style={{ background: waveBg(mp.waveHeight) }}>
            <span className="text-[13px] font-bold" style={{ color: waveText(mp.waveHeight) }}>{mp.waveHeight.toFixed(1)}</span>
          </div>
        ) : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      {
        id: 'waveP', label: 'Per.', height: 26,
        render: (_, mp) => mp && mp.wavePeriod > 0
          ? <span className="text-[12px] font-semibold text-[var(--text-secondary)]">{mp.wavePeriod.toFixed(0)}s</span>
          : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      {
        id: 'waveD', label: 'Dir.H', height: 30,
        render: (_, mp) => mp ? (
          <div className="flex flex-col items-center gap-0.5">
            <DirArrow deg={mp.waveDirection} size={13} />
            <span className="text-[9px] font-medium text-[var(--text-secondary)]">{degToCompassFR(mp.waveDirection)}</span>
          </div>
        ) : null,
      },
      // Swell decomposition
      {
        id: 'swell', label: 'Houle', height: 30,
        render: (_, mp) => mp && mp.swellHeight > 0 ? (
          <div className="w-full h-full flex items-center justify-center" style={{ background: `${getWaveColor(mp.swellHeight)}25` }}>
            <span className="text-[13px] font-bold" style={{ color: '#6366f1' }}>{mp.swellHeight.toFixed(1)}</span>
          </div>
        ) : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      {
        id: 'swellP', label: 'Per.H', height: 26,
        render: (_, mp) => mp && mp.swellPeriod > 0
          ? <span className="text-[12px] font-semibold" style={{ color: mp.swellPeriod >= 12 ? '#6366f1' : mp.swellPeriod >= 8 ? '#818cf8' : '#a5b4fc' }}>{mp.swellPeriod.toFixed(0)}s</span>
          : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      {
        id: 'swellD', label: 'Dir.H', height: 30,
        render: (_, mp) => mp && mp.swellDirection > 0 ? (
          <div className="flex flex-col items-center gap-0.5">
            <svg width={13} height={13} viewBox="0 0 24 24" style={{ transform: `rotate(${mp.swellDirection + 180}deg)`, color: '#6366f1' }}>
              <path d="M12 2L6 18h12z" fill="currentColor" />
            </svg>
            <span className="text-[9px] font-medium" style={{ color: '#6366f1' }}>{degToCompassFR(mp.swellDirection)}</span>
          </div>
        ) : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      // Wind waves
      {
        id: 'windWave', label: 'M.vent', height: 30,
        render: (_, mp) => mp && mp.windWaveHeight > 0 ? (
          <div className="w-full h-full flex items-center justify-center" style={{ background: `${getWaveColor(mp.windWaveHeight)}25` }}>
            <span className="text-[13px] font-bold" style={{ color: '#0ea5e9' }}>{mp.windWaveHeight.toFixed(1)}</span>
          </div>
        ) : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
      {
        id: 'windWaveP', label: 'Per.MV', height: 26,
        render: (_, mp) => mp && mp.windWavePeriod > 0
          ? <span className="text-[12px] font-semibold" style={{ color: '#0ea5e9' }}>{mp.windWavePeriod.toFixed(0)}s</span>
          : <span className="text-[11px] text-[var(--text-tertiary)]">-</span>,
      },
    )
  }

  return rows
}

// ===== Main Component =====

interface ForecastPanelProps {
  lat: number
  lon: number
  name?: string
  onClose: () => void
  isCoastal?: boolean
}

export default function ForecastPanel({ lat, lon, name, onClose, isCoastal = true }: ForecastPanelProps) {
  const [activeModel, setActiveModel] = useState<ForecastModel>('arome')
  const [forecasts, setForecasts] = useState<Record<string, ForecastResponse>>({})
  const [marine, setMarine] = useState<MarineResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [step, setStep] = useState<1 | 3>(3)
  const scrollRef = useRef<HTMLDivElement>(null)

  // Fetch all models + marine
  useEffect(() => {
    let cancelled = false
    setLoading(true)
    const load = async () => {
      const results = await Promise.allSettled([
        ...MODELS.map(m => fetchWindForecast(lat, lon, m)),
        ...(isCoastal ? [fetchMarineForecast(lat, lon)] : []),
      ])
      if (cancelled) return
      const fc: Record<string, ForecastResponse> = {}
      MODELS.forEach((m, i) => {
        if (results[i].status === 'fulfilled') fc[m] = (results[i] as PromiseFulfilledResult<ForecastResponse>).value
      })
      setForecasts(fc)
      if (isCoastal && results.length > MODELS.length) {
        const mr = results[MODELS.length]
        if (mr.status === 'fulfilled') setMarine((mr as PromiseFulfilledResult<MarineResponse>).value)
      }
      setLoading(false)
    }
    load()
    return () => { cancelled = true }
  }, [lat, lon, isCoastal])

  const data = forecasts[activeModel]
  const points = useMemo(() => {
    if (!data) return []
    return step === 1 ? data.points : data.points.filter((_, i) => i % step === 0)
  }, [data, step])

  const times = useMemo(() => points.map(p => p.time), [points])
  const dayGroups = useMemo(() => groupByDay(times), [times])
  const rows = useMemo(() => makeRows(isCoastal && !!marine), [isCoastal, marine])

  const marineMap = useMemo(() => {
    if (!marine) return new Map<string, MarinePoint>()
    const m = new Map<string, MarinePoint>()
    for (const p of marine.points) m.set(p.time, p)
    return m
  }, [marine])

  const nowIdx = useMemo(() => {
    const now = Date.now()
    return times.findIndex(t => new Date(t).getTime() >= now)
  }, [times])

  // Scroll to now
  useEffect(() => {
    if (!scrollRef.current || nowIdx <= 0) return
    scrollRef.current.scrollLeft = Math.max(0, (nowIdx - 3) * CW)
  }, [nowIdx, step])

  return (
    <div
      className="absolute bottom-0 left-0 right-0 z-[700] flex flex-col rounded-t-2xl overflow-hidden"
      style={{
        maxHeight: '60vh',
        background: 'var(--sheet-bg)',
        backdropFilter: 'blur(40px) saturate(1.8)',
        WebkitBackdropFilter: 'blur(40px) saturate(1.8)',
        boxShadow: '0 -4px 30px rgba(0,0,0,0.12), 0 0 0 0.5px var(--glass-border) inset',
      }}
    >
      {/* Header */}
      <div
        className="shrink-0"
        style={{ background: 'var(--bg-secondary)' }}
      >
        <div className="flex justify-center pt-2 pb-1">
          <div className="w-9 h-1 rounded-full" style={{ background: 'color-mix(in srgb, var(--text-primary) 15%, transparent)' }} />
        </div>

        <div className="flex items-center justify-between px-3 pb-2.5 gap-2">
          <h3 className="text-[15px] font-bold text-[var(--text-primary)] truncate shrink min-w-0">
            {name || `${lat.toFixed(2)}°N, ${lon.toFixed(2)}°${lon >= 0 ? 'E' : 'O'}`}
          </h3>

          {/* Liquid glass model switcher */}
          <div
            className="relative flex items-center gap-1 p-1 rounded-full shrink-0"
            style={{
              background: 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
              backdropFilter: 'blur(12px) saturate(150%)',
              WebkitBackdropFilter: 'blur(12px) saturate(150%)',
              boxShadow: 'inset 0 0 0 1px color-mix(in srgb, var(--text-primary) 8%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15), 0 2px 8px rgba(0,0,0,0.06)',
            }}
          >
            {MODELS.map(m => {
              const info = MODEL_LABELS[m]
              const has = !!forecasts[m]
              const active = activeModel === m
              return (
                <button
                  key={m}
                  onClick={() => has && setActiveModel(m)}
                  className={`relative z-10 px-2.5 py-1 rounded-full text-[11px] font-bold transition-all duration-300 ${
                    active ? 'text-white' : has ? 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]' : 'opacity-25 cursor-default'
                  }`}
                  style={active ? {
                    background: info.color,
                    boxShadow: `0 2px 8px ${info.color}50, inset 0 1px 0 rgba(255,255,255,0.25)`,
                  } : undefined}
                >
                  {info.name}
                </button>
              )
            })}
          </div>

          <div className="flex items-center gap-1 shrink-0">
            {/* Liquid glass step toggle */}
            <div
              className="flex items-center p-0.5 rounded-full"
              style={{
                background: 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
                backdropFilter: 'blur(8px) saturate(150%)',
                WebkitBackdropFilter: 'blur(8px) saturate(150%)',
                boxShadow: 'inset 0 0 0 1px color-mix(in srgb, var(--text-primary) 8%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.1)',
              }}
            >
              {([1, 3] as const).map(s => (
                <button
                  key={s}
                  onClick={() => setStep(s)}
                  className={`w-7 h-6 rounded-full text-[10px] font-bold transition-all duration-300 ${
                    step === s ? 'text-white' : 'text-[var(--text-tertiary)] hover:text-[var(--text-secondary)]'
                  }`}
                  style={step === s ? {
                    background: '#007aff',
                    boxShadow: '0 2px 6px rgba(0,122,255,0.35), inset 0 1px 0 rgba(255,255,255,0.2)',
                  } : undefined}
                >
                  {s}h
                </button>
              ))}
            </div>
            <button
              onClick={onClose}
              className="ml-0.5 w-7 h-7 rounded-full flex items-center justify-center transition-all"
              style={{
                background: 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
                backdropFilter: 'blur(8px)',
                WebkitBackdropFilter: 'blur(8px)',
                boxShadow: 'inset 0 0 0 1px color-mix(in srgb, var(--text-primary) 8%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.1)',
              }}
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
            </button>
          </div>
        </div>
      </div>

      {/* Loading */}
      {loading && (
        <div className="flex-1 flex items-center justify-center gap-2">
          <div className="w-5 h-5 border-2 border-[var(--border)] border-t-[#007aff] rounded-full animate-spin" />
          <span className="text-[12px] text-[var(--text-secondary)]">Chargement...</span>
        </div>
      )}

      {/* Table */}
      {!loading && data && (
        <div className="flex-1 flex overflow-hidden">
          {/* Fixed label column */}
          <div className="shrink-0 flex flex-col border-r border-[var(--border)]" style={{ background: 'var(--bg-secondary)', width: 52 }}>
            {/* Day spacer */}
            <div className="border-b border-[var(--border)]" style={{ height: 22 }} />
            {/* Hour spacer */}
            <div className="border-b border-[var(--border)]" style={{ height: 24 }} />
            {/* Row labels */}
            {rows.map(r => (
              <div key={r.id} className="flex items-center justify-end pr-2 border-b border-[var(--border)]" style={{ height: r.height }}>
                <span className="text-[11px] font-semibold text-[var(--text-secondary)]">{r.label}</span>
              </div>
            ))}
          </div>

          {/* Scrollable data */}
          <div ref={scrollRef} className="flex-1 overflow-x-auto overflow-y-hidden">
            <div style={{ minWidth: points.length * CW }}>
              {/* Day headers */}
              <div className="flex border-b border-[var(--border)]" style={{ height: 22, background: 'var(--bg-secondary)' }}>
                {dayGroups.map((g, gi) => (
                  <div
                    key={gi}
                    className="flex items-center justify-center text-[12px] font-bold text-[var(--text-primary)] border-r border-[var(--border)]"
                    style={{ width: g.hours * CW }}
                  >
                    {g.label}
                  </div>
                ))}
              </div>

              {/* Hour headers */}
              <div className="flex border-b border-[var(--border)]" style={{ height: 24, background: 'var(--bg-secondary)' }}>
                {points.map((p, i) => {
                  const h = new Date(p.time).getHours()
                  const isNow = i === nowIdx
                  const isNight = h < 7 || h >= 21
                  return (
                    <div
                      key={i}
                      className="flex items-center justify-center text-[12px] font-bold border-r"
                      style={{
                        width: CW, minWidth: CW,
                        borderColor: 'var(--border)',
                        color: isNow ? '#007aff' : isNight ? 'var(--text-tertiary)' : 'var(--text-secondary)',
                        background: isNow ? 'rgba(0,122,255,0.08)' : isNight ? 'rgba(0,0,0,0.03)' : undefined,
                      }}
                    >
                      {h}h
                    </div>
                  )
                })}
              </div>

              {/* Data rows */}
              {rows.map(r => (
                <div key={r.id} className="flex border-b border-[var(--border)]" style={{ height: r.height }}>
                  {points.map((p, i) => {
                    const h = new Date(p.time).getHours()
                    const isNow = i === nowIdx
                    const isNight = h < 7 || h >= 21
                    const mp = marineMap.get(p.time)
                    return (
                      <div
                        key={i}
                        className="flex items-center justify-center border-r overflow-hidden"
                        style={{
                          width: CW, minWidth: CW,
                          borderColor: 'var(--border)',
                          background: isNow ? 'rgba(0,122,255,0.06)' : isNight ? 'rgba(0,0,0,0.015)' : undefined,
                          borderLeft: isNow ? '1.5px solid rgba(0,122,255,0.3)' : undefined,
                          borderRight: isNow ? '1.5px solid rgba(0,122,255,0.3)' : undefined,
                        }}
                      >
                        {r.render(p, mp)}
                      </div>
                    )
                  })}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Bottom bar: model comparison */}
      {!loading && data && (
        <div className="shrink-0 flex items-center gap-2 px-3 py-1.5 overflow-x-auto glass-footer">
          {MODELS.map(m => {
            const info = MODEL_LABELS[m]
            const fc = forecasts[m]
            if (!fc) return null
            const now = Date.now()
            const next24 = fc.points.filter(p => { const t = new Date(p.time).getTime(); return t >= now && t <= now + 86400000 })
            const maxW = next24.reduce((mx, p) => Math.max(mx, p.windSpeed), 0)
            const maxG = next24.reduce((mx, p) => Math.max(mx, p.windGust), 0)
            return (
              <button
                key={m}
                onClick={() => setActiveModel(m)}
                className={`flex items-center gap-1.5 px-2.5 py-1 rounded-xl shrink-0 transition-all duration-200 ${
                  activeModel === m ? '' : 'opacity-50 hover:opacity-80'
                }`}
                style={activeModel === m ? {
                  background: `color-mix(in srgb, ${info.color} 10%, transparent)`,
                  backdropFilter: 'blur(8px) saturate(1.4)',
                  WebkitBackdropFilter: 'blur(8px) saturate(1.4)',
                  boxShadow: `inset 0 0 0 1px color-mix(in srgb, ${info.color} 25%, transparent), inset 0 1px 0 rgba(255,255,255,0.15), 0 2px 8px ${info.color}20`,
                } : undefined}
              >
                <div className="w-1.5 h-1.5 rounded-full" style={{ background: info.color }} />
                <div>
                  <div className="text-[11px] font-bold text-[var(--text-primary)] leading-none">{info.name} <span className="opacity-50">{info.days}j</span></div>
                  <div className="text-[11px] leading-none mt-0.5">
                    <span className="font-bold" style={{ color: getWindColor(maxW) }}>{Math.round(maxW)}</span>
                    <span className="text-[var(--text-tertiary)] mx-0.5">/</span>
                    <span className="font-bold" style={{ color: getWindColor(maxG) }}>{Math.round(maxG)}</span>
                    <span className="text-[var(--text-tertiary)] ml-0.5">kts</span>
                  </div>
                </div>
              </button>
            )
          })}
          <div className="ml-auto flex items-center gap-2 text-[10px] shrink-0">
            {marine && (
              <div className="flex items-center gap-1.5">
                <span className="flex items-center gap-0.5"><span className="w-1.5 h-1.5 rounded-full" style={{ background: '#6366f1' }} />Houle</span>
                <span className="flex items-center gap-0.5"><span className="w-1.5 h-1.5 rounded-full" style={{ background: '#0ea5e9' }} />M.vent</span>
              </div>
            )}
            <span className="text-[var(--text-tertiary)]">kts / °C / mm</span>
          </div>
        </div>
      )}
    </div>
  )
}
