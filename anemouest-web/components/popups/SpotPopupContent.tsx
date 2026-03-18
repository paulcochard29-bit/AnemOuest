'use client'

import type { Spot } from '@/store/appStore'

const SPOT_INFO: Record<string, { label: string; color: string }> = {
  kite: { label: 'Kitesurf', color: '#34c759' },
  surf: { label: 'Surf', color: '#007aff' },
  paragliding: { label: 'Parapente', color: '#ff9500' },
}

interface Props {
  spot: Spot
  expanded: boolean
  onExpand: () => void
  onForecast?: (lat: number, lon: number, name: string) => void
}

export function SpotPopupContent({ spot, expanded, onExpand, onForecast }: Props) {
  const info = SPOT_INFO[spot.spotType] || { label: spot.spotType, color: '#8e8e93' }

  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white glass-tag" style={{ background: info.color }}>
          {info.label}
        </span>
        {spot.level && (
          <span className="text-[10px] font-semibold text-[#8e8e93] px-2 py-0.5 rounded-full glass-stat">{spot.level}</span>
        )}
      </div>
      <div className="text-[16px] font-bold text-[#1c1c1e] mt-1.5">{spot.name}</div>
      <div className="flex items-center gap-3 mt-1.5 text-[12px] text-[#8e8e93]">
        {spot.orientation && spot.orientation.length > 0 && (
          <span className="font-semibold">{spot.orientation.join(' · ')}</span>
        )}
        {spot.altitude != null && spot.altitude > 0 && (
          <span>{spot.altitude}m</span>
        )}
      </div>

      {expanded && spot.description && (
        <div className="mt-2 text-[12px] text-[#3c3c43] leading-relaxed glass-stat px-3 py-2">{spot.description}</div>
      )}

      {onForecast && (
        <button onClick={() => onForecast(spot.lat, spot.lon, spot.name)}
          className="w-full mt-2 py-2.5 rounded-full text-[13px] font-bold flex items-center justify-center gap-1.5 active:scale-[0.98] transition-all duration-200"
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
      )}

      <div className="flex justify-end mt-2">
        {!expanded ? (
          <button onClick={onExpand}
            className="text-[12px] font-semibold px-2.5 py-1 rounded-full glass-action-btn flex items-center gap-0.5"
            style={{
              color: info.color,
              background: `color-mix(in srgb, ${info.color} 8%, transparent)`,
              boxShadow: `inset 0 0 0 0.5px color-mix(in srgb, ${info.color} 20%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)`,
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
