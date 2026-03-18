'use client'

import { useCallback, useEffect, useRef, useState, useMemo } from 'react'
import { getWindColor } from '@/lib/utils'

interface WindTimelineProps {
  forecastHour: number
  onChange: (hour: number) => void
}

const DAYS_FR = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam']
const MONTHS_FR = ['jan', 'fev', 'mar', 'avr', 'mai', 'jun', 'jul', 'aou', 'sep', 'oct', 'nov', 'dec']

function getDateForHour(h: number): Date {
  const d = new Date()
  d.setMinutes(0, 0, 0)
  d.setHours(d.getHours() + h)
  return d
}

function formatFullDate(h: number): string {
  const d = getDateForHour(h)
  return `${DAYS_FR[d.getDay()]} ${d.getDate()} ${MONTHS_FR[d.getMonth()]} - ${String(d.getHours()).padStart(2, '0')}:00`
}

function formatShort(h: number): string {
  if (h === 0) return 'Maintenant'
  const abs = Math.abs(h)
  const sign = h > 0 ? '+' : '-'
  if (abs < 24) return `${sign}${abs}h`
  const days = Math.floor(abs / 24)
  const rem = abs % 24
  return rem === 0 ? `${sign}${days}j` : `${sign}${days}j${rem}h`
}

// Generate hour ticks for the timeline bar
function generateTicks(): { hour: number, major: boolean }[] {
  const ticks: { hour: number, major: boolean }[] = []
  for (let h = -72; h <= 72; h += 3) {
    const d = getDateForHour(h)
    ticks.push({ hour: h, major: d.getHours() === 0 })
  }
  return ticks
}

// Playback speeds
const SPEEDS = [
  { label: '1x', ms: 600 },
  { label: '2x', ms: 300 },
  { label: '4x', ms: 150 },
]

export default function WindTimeline({ forecastHour, onChange }: WindTimelineProps) {
  const [playing, setPlaying] = useState(false)
  const [speedIdx, setSpeedIdx] = useState(0)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const trackRef = useRef<HTMLDivElement>(null)
  const isDragging = useRef(false)

  const ticks = useMemo(generateTicks, [])

  // Play animation
  const hourRef = useRef(forecastHour)
  hourRef.current = forecastHour

  useEffect(() => {
    if (!playing) {
      if (intervalRef.current) clearInterval(intervalRef.current)
      intervalRef.current = null
      return
    }
    intervalRef.current = setInterval(() => {
      const next = hourRef.current + 1
      if (next > 72) {
        setPlaying(false)
      } else {
        onChange(next)
      }
    }, SPEEDS[speedIdx].ms)
    return () => { if (intervalRef.current) clearInterval(intervalRef.current) }
  }, [playing, speedIdx, onChange])

  const togglePlay = useCallback(() => setPlaying(p => !p), [])

  const cycleSpeed = useCallback(() => {
    setSpeedIdx(i => (i + 1) % SPEEDS.length)
  }, [])

  const step = useCallback((delta: number) => {
    setPlaying(false)
    onChange(Math.max(-72, Math.min(72, forecastHour + delta)))
  }, [forecastHour, onChange])

  const goToNow = useCallback(() => {
    setPlaying(false)
    onChange(0)
  }, [onChange])

  // Click/drag on the custom track
  const hourFromEvent = useCallback((e: React.MouseEvent | MouseEvent) => {
    if (!trackRef.current) return forecastHour
    const rect = trackRef.current.getBoundingClientRect()
    const x = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
    return Math.round(x * 144 - 72)
  }, [forecastHour])

  const onTrackDown = useCallback((e: React.MouseEvent) => {
    isDragging.current = true
    setPlaying(false)
    onChange(hourFromEvent(e))
    const onMove = (me: MouseEvent) => {
      if (!isDragging.current) return
      onChange(Math.max(-72, Math.min(72, hourFromEvent(me))))
    }
    const onUp = () => {
      isDragging.current = false
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }, [hourFromEvent, onChange])

  // Touch support
  const onTouchStart = useCallback((e: React.TouchEvent) => {
    if (!trackRef.current) return
    isDragging.current = true
    setPlaying(false)
    const rect = trackRef.current.getBoundingClientRect()
    const x = Math.max(0, Math.min(1, (e.touches[0].clientX - rect.left) / rect.width))
    onChange(Math.round(x * 144 - 72))
    const onMove = (te: TouchEvent) => {
      if (!isDragging.current || !trackRef.current) return
      te.preventDefault()
      const r = trackRef.current.getBoundingClientRect()
      const tx = Math.max(0, Math.min(1, (te.touches[0].clientX - r.left) / r.width))
      onChange(Math.max(-72, Math.min(72, Math.round(tx * 144 - 72))))
    }
    const onEnd = () => {
      isDragging.current = false
      window.removeEventListener('touchmove', onMove)
      window.removeEventListener('touchend', onEnd)
    }
    window.addEventListener('touchmove', onMove, { passive: false })
    window.addEventListener('touchend', onEnd)
  }, [onChange])

  const progress = ((forecastHour + 72) / 144) * 100
  const nowPos = 50 // "now" is always at the center (hour 0)

  // Day markers on the track
  const dayMarkers = useMemo(() => {
    const markers: { pos: number, label: string }[] = []
    for (let h = -72; h <= 72; h++) {
      const d = getDateForHour(h)
      if (d.getHours() === 0) {
        markers.push({
          pos: ((h + 72) / 144) * 100,
          label: `${DAYS_FR[d.getDay()]} ${d.getDate()}`
        })
      }
    }
    return markers
  }, [])

  return (
    <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-10 w-[92vw] max-w-[520px]">
      <div className="glass-bar rounded-2xl overflow-hidden">
        {/* Header: date + badge */}
        <div className="flex items-center justify-between px-4 pt-3 pb-1.5">
          <div className="flex items-center gap-2">
            <span className="text-[13px] font-semibold text-[var(--text-primary)]">
              {formatFullDate(forecastHour)}
            </span>
          </div>
          <button
            onClick={goToNow}
            className={`text-[11px] font-semibold px-2.5 py-1 rounded-full transition-all ${
              forecastHour === 0
                ? 'bg-[#007aff]/15 text-[#007aff]'
                : forecastHour < 0
                  ? 'bg-[#8e8e93]/15 text-[#8e8e93] hover:bg-[#8e8e93]/25 cursor-pointer'
                  : 'bg-[#34c759]/15 text-[#34c759] hover:bg-[#34c759]/25 cursor-pointer'
            }`}
          >
            {formatShort(forecastHour)}
          </button>
        </div>

        {/* Timeline track */}
        <div className="px-4 pb-1">
          <div
            ref={trackRef}
            className="relative h-10 cursor-pointer select-none"
            onMouseDown={onTrackDown}
            onTouchStart={onTouchStart}
          >
            {/* Track background */}
            <div className="absolute top-4 left-0 right-0 h-[6px] rounded-full bg-[#e5e5ea] dark:bg-[#3a3a3c] overflow-hidden">
              {/* Progress fill */}
              <div
                className="h-full bg-gradient-to-r from-[#8e8e93] via-[#007aff] to-[#34c759] transition-[width] duration-75"
                style={{ width: `${progress}%` }}
              />
            </div>

            {/* Day dividers */}
            {dayMarkers.map((m, i) => (
              <div key={i} className="absolute top-2" style={{ left: `${m.pos}%` }}>
                <div className="w-px h-5 bg-[#8e8e93]/30" />
                <span className="absolute top-5 -translate-x-1/2 text-[8px] font-medium text-[#8e8e93] whitespace-nowrap">
                  {m.label}
                </span>
              </div>
            ))}

            {/* "Now" marker */}
            <div
              className="absolute top-[11px] w-[3px] h-[14px] rounded-full bg-[#007aff] pointer-events-none"
              style={{ left: `${nowPos}%`, transform: 'translateX(-50%)' }}
            />

            {/* Thumb */}
            <div
              className="absolute top-[8px] pointer-events-none"
              style={{ left: `${progress}%`, transform: 'translateX(-50%)' }}
            >
              <div className="w-5 h-5 rounded-full bg-white shadow-[0_1px_6px_rgba(0,0,0,0.2),0_0_0_1px_rgba(0,0,0,0.08)] border border-white" />
            </div>
          </div>
        </div>

        {/* Controls row */}
        <div className="flex items-center justify-between px-3 pb-3 pt-1">
          {/* Transport */}
          <div className="flex items-center gap-0.5">
            {/* Skip -6h */}
            <button onClick={() => step(-6)} className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-black/5 dark:hover:bg-white/10 active:scale-90 transition" title="-6h">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="11 17 6 12 11 7" /><polyline points="18 17 13 12 18 7" />
              </svg>
            </button>

            {/* Step -1h */}
            <button onClick={() => step(-1)} className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-black/5 dark:hover:bg-white/10 active:scale-90 transition" title="-1h">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6" />
              </svg>
            </button>

            {/* Play / Pause */}
            <button
              onClick={togglePlay}
              className="w-10 h-10 flex items-center justify-center rounded-full bg-[#007aff] text-white hover:bg-[#0066d6] active:scale-90 transition shadow-sm mx-0.5"
            >
              {playing ? (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                  <rect x="6" y="4" width="4" height="16" rx="1.5" />
                  <rect x="14" y="4" width="4" height="16" rx="1.5" />
                </svg>
              ) : (
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M7 4.5v15l12-7.5z" />
                </svg>
              )}
            </button>

            {/* Step +1h */}
            <button onClick={() => step(1)} className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-black/5 dark:hover:bg-white/10 active:scale-90 transition" title="+1h">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="9 18 15 12 9 6" />
              </svg>
            </button>

            {/* Skip +6h */}
            <button onClick={() => step(6)} className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-black/5 dark:hover:bg-white/10 active:scale-90 transition" title="+6h">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="13 17 18 12 13 7" /><polyline points="6 17 11 12 6 7" />
              </svg>
            </button>
          </div>

          {/* Speed + quick jumps */}
          <div className="flex items-center gap-1.5">
            {/* Speed toggle */}
            <button
              onClick={cycleSpeed}
              className="text-[10px] font-bold px-2 py-1 rounded-lg bg-[#007aff]/10 text-[#007aff] hover:bg-[#007aff]/20 active:scale-95 transition tabular-nums"
            >
              {SPEEDS[speedIdx].label}
            </button>

            {/* Separator */}
            <div className="w-px h-4 bg-[#8e8e93]/20 mx-0.5" />

            {/* Quick jumps */}
            {[
              { label: '-1j', h: -24 },
              { label: 'Now', h: 0 },
              { label: '+1j', h: 24 },
              { label: '+2j', h: 48 },
            ].map(({ label, h }) => (
              <button
                key={h}
                onClick={() => { setPlaying(false); onChange(h) }}
                className={`text-[10px] font-semibold px-2 py-1 rounded-lg transition ${
                  forecastHour === h
                    ? 'bg-[#007aff] text-white shadow-sm'
                    : 'text-[#8e8e93] hover:bg-black/5 dark:hover:bg-white/10'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
