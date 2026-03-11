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
}

export function SpotPopupContent({ spot, expanded, onExpand }: Props) {
  const info = SPOT_INFO[spot.spotType] || { label: spot.spotType, color: '#8e8e93' }

  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full text-white" style={{ background: info.color }}>
          {info.label}
        </span>
        {spot.level && (
          <span className="text-[10px] font-semibold text-[#8e8e93] px-2 py-0.5 rounded-full bg-[#f2f2f7]">{spot.level}</span>
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
        <div className="mt-2 text-[12px] text-[#3c3c43] leading-relaxed">{spot.description}</div>
      )}

      <div className="flex justify-end mt-2">
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
