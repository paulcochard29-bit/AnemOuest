'use client'

import type { Spot } from '@/store/appStore'

interface Props { spot: Spot; onClose: () => void }

const TYPE_LABELS: Record<string, { label: string; color: string; darkColor: string; icon: string }> = {
  kite: { label: 'Kitesurf', color: '#34c759', darkColor: '#1a7a30', icon: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z' },
  surf: { label: 'Surf', color: '#007aff', darkColor: '#004eaa', icon: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z' },
  paragliding: { label: 'Parapente', color: '#ff9500', darkColor: '#b36800', icon: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z' },
}

export function SpotSheet({ spot, onClose }: Props) {
  const info = TYPE_LABELS[spot.spotType] || { label: spot.spotType, color: '#8e8e93', darkColor: '#636366', icon: '' }

  return (
    <>
      <div className="sheet-backdrop" onClick={onClose} />
      <div className="sheet">
        <div className="flex justify-center pt-1.5 pb-1 md:hidden">
          <div className="w-9 h-[5px] rounded-full bg-white/30" />
        </div>
        <div className="overflow-auto max-h-[calc(50vh-20px)] md:max-h-screen">
          {/* Header */}
          <div className="flex items-start justify-between px-4 pt-3 pb-1">
            <div>
              <h2 className="text-[18px] font-bold text-[#1c1c1e] tracking-tight">{spot.name}</h2>
              <div className="flex items-center gap-2 mt-1">
                <span className="text-[12px] font-bold px-2.5 py-0.5 rounded-full text-white shadow-sm" style={{ background: info.color }}>
                  {info.label}
                </span>
                {spot.level && (
                  <span className="text-[12px] font-semibold px-2 py-0.5 rounded-full bg-black/5 text-[#636366]">{spot.level}</span>
                )}
              </div>
            </div>
            <button onClick={onClose} className="px-3 py-1 rounded-full text-[13px] font-medium text-[#007aff] glass-btn">Fermer</button>
          </div>

          {/* Hero banner */}
          <div className="mx-4 mt-2 mb-3 rounded-2xl overflow-hidden" style={{ background: `linear-gradient(135deg, ${info.darkColor}, ${info.darkColor}dd)` }}>
            <div className="p-4 flex items-center gap-4" style={{ background: 'rgba(255,255,255,0.08)' }}>
              {/* Orientation compass */}
              {spot.orientation && spot.orientation.length > 0 && (
                <div className="flex-shrink-0">
                  <div className="relative w-[72px] h-[72px]">
                    <svg width="72" height="72" viewBox="0 0 72 72">
                      <circle cx="36" cy="36" r="34" fill="none" stroke="white" strokeOpacity="0.2" strokeWidth="1.2" />
                      {['N', 'E', 'S', 'O'].map((label, i) => {
                        const angle = i * 90
                        const rad = (angle - 90) * Math.PI / 180
                        const r = 26
                        return (
                          <text key={label} x={36 + Math.cos(rad) * r} y={36 + Math.sin(rad) * r}
                            textAnchor="middle" dominantBaseline="central"
                            fill="white" fillOpacity="0.5" fontSize="9" fontWeight="800">
                            {label}
                          </text>
                        )
                      })}
                      {/* Highlight oriented directions */}
                      {spot.orientation.map((o) => {
                        const dirMap: Record<string, number> = { N: 0, NE: 45, E: 90, SE: 135, S: 180, SO: 225, SW: 225, O: 270, W: 270, NO: 315, NW: 315 }
                        const angle = dirMap[o] ?? 0
                        const rad = (angle - 90) * Math.PI / 180
                        const r1 = 16
                        const r2 = 30
                        return (
                          <line key={o}
                            x1={36 + Math.cos(rad) * r1} y1={36 + Math.sin(rad) * r1}
                            x2={36 + Math.cos(rad) * r2} y2={36 + Math.sin(rad) * r2}
                            stroke="white" strokeOpacity="0.8" strokeWidth="3" strokeLinecap="round"
                          />
                        )
                      })}
                      <circle cx="36" cy="36" r="3" fill="white" fillOpacity="0.7" />
                    </svg>
                  </div>
                </div>
              )}
              <div className="flex-1">
                <div className="text-[10px] font-semibold text-white/50 uppercase tracking-widest mb-1">Orientation</div>
                <div className="text-[20px] font-black text-white leading-tight">
                  {spot.orientation && spot.orientation.length > 0 ? spot.orientation.join(' · ') : '—'}
                </div>
                {spot.altitude !== undefined && (
                  <div className="mt-2 flex items-baseline gap-1">
                    <span className="text-[24px] font-black text-white/80 tabular-nums leading-none">{spot.altitude}</span>
                    <span className="text-[12px] font-semibold text-white/40">m alt.</span>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Details */}
          <div className="glass-card rounded-2xl mx-4 mb-4 overflow-hidden">
            {spot.surfType && (
              <div className="flex items-center justify-between px-4 py-3 border-b glass-divider">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: `${info.color}15` }}>
                    <svg className="w-4 h-4" fill="none" stroke={info.color} strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M2 12c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /><path strokeLinecap="round" d="M2 18c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /></svg>
                  </div>
                  <span className="text-[15px] text-[#1c1c1e]">Type de vague</span>
                </div>
                <span className="text-[15px] font-bold text-[#1c1c1e]">{spot.surfType}</span>
              </div>
            )}
            {spot.kiteType && (
              <div className="flex items-center justify-between px-4 py-3 border-b glass-divider">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ background: `${info.color}15` }}>
                    <svg className="w-4 h-4" fill="none" stroke={info.color} strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M12 2v20M2 12h20" /></svg>
                  </div>
                  <span className="text-[15px] text-[#1c1c1e]">Type de spot</span>
                </div>
                <span className="text-[15px] font-bold text-[#1c1c1e]">{spot.kiteType}</span>
              </div>
            )}
            <div className="flex items-center justify-between px-4 py-3">
              <div className="flex items-center gap-2.5">
                <div className="w-7 h-7 rounded-lg bg-[#8e8e93]/10 flex items-center justify-center">
                  <svg className="w-4 h-4 text-[#8e8e93]" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path strokeLinecap="round" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
                </div>
                <span className="text-[15px] text-[#1c1c1e]">Coordonnees</span>
              </div>
              <span className="text-[14px] font-semibold text-[#8e8e93] tabular-nums">{spot.lat.toFixed(4)}, {spot.lon.toFixed(4)}</span>
            </div>
          </div>

          {/* Description */}
          {spot.description && (
            <div className="glass-card rounded-2xl mx-4 mb-4 px-4 py-3">
              <div className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5">Description</div>
              <div className="text-[15px] text-[#3c3c43] leading-relaxed">{spot.description}</div>
            </div>
          )}
        </div>
      </div>
    </>
  )
}
