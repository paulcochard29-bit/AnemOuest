'use client'

import { useMemo } from 'react'
import type { TideEvent } from '@/lib/types'
import { getCoeffColor, getTideState } from '@/lib/tide-utils'

interface TideWidgetProps {
  portName: string
  tideData: TideEvent[] | null
  nextTideEvents: TideEvent[] | null
  onClick: () => void
}

export function TideWidget({ portName, tideData, nextTideEvents, onClick }: TideWidgetProps) {
  const tideState = useMemo(() => {
    if (!tideData?.length) return null
    return getTideState(tideData)
  }, [tideData])

  const nextTide = nextTideEvents?.[0] ?? null

  if (!nextTide) return null

  const isHigh = nextTide.type === 'PM' || nextTide.type === 'high'
  const typeLabel = isHigh ? 'PM' : 'BM'
  const timeStr = new Date(nextTide.time).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
  const coeff = nextTide.coeff
  const coeffColor = coeff ? getCoeffColor(coeff) : undefined

  return (
    <button
      onClick={onClick}
      className="glass-bar rounded-2xl px-2.5 py-1.5 flex items-center gap-2 transition-all duration-300 hover:scale-[1.02] active:scale-[0.98]"
      title={`Marées — ${portName}`}
    >
      {/* Tide direction icon */}
      <div className="flex items-center justify-center w-7 h-7 rounded-full" style={{ background: isHigh ? 'rgba(59,130,246,0.15)' : 'rgba(6,182,212,0.15)' }}>
        {isHigh ? (
          <svg className="w-4 h-4" fill="none" stroke="#3b82f6" strokeWidth={2} viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 19V5m0 0l-5 5m5-5l5 5" />
          </svg>
        ) : (
          <svg className="w-4 h-4" fill="none" stroke="#06b6d4" strokeWidth={2} viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 5v14m0 0l5-5m-5 5l-5-5" />
          </svg>
        )}
      </div>

      {/* Info */}
      <div className="flex flex-col items-start min-w-0">
        <span className="text-[10px] text-[#8e8e93] font-medium leading-tight truncate max-w-[100px]">{portName}</span>
        <div className="flex items-center gap-1.5">
          <span className="text-[11px] font-bold rounded px-1 py-[1px] leading-tight"
            style={{ background: isHigh ? 'rgba(59,130,246,0.15)' : 'rgba(6,182,212,0.15)', color: isHigh ? '#3b82f6' : '#06b6d4' }}>
            {typeLabel}
          </span>
          <span className="text-[13px] font-semibold text-[#1c1c1e] tabular-nums" style={{ fontVariantNumeric: 'tabular-nums' }}>
            {timeStr}
          </span>
        </div>
      </div>

      {/* Coefficient */}
      {coeff && (
        <div className="flex flex-col items-center ml-0.5">
          <span className="text-[9px] text-[#8e8e93] leading-tight">Coef</span>
          <span className="text-[14px] font-bold leading-tight tabular-nums" style={{ color: coeffColor }}>
            {coeff}
          </span>
        </div>
      )}

      {/* Tide state indicator */}
      {tideState && tideState.state && (
        <div className="flex flex-col items-center ml-0.5">
          <span className="text-[9px] text-[#8e8e93] leading-tight">
            {tideState.state === 'Montante' ? '↗' : '↘'}
          </span>
          <div className="w-5 h-1 rounded-full bg-[#e5e5ea] overflow-hidden mt-0.5">
            <div className="h-full rounded-full transition-all duration-1000"
              style={{ width: `${tideState.progress * 100}%`, background: tideState.state === 'Montante' ? '#3b82f6' : '#06b6d4' }} />
          </div>
        </div>
      )}
    </button>
  )
}
