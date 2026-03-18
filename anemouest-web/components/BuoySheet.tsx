'use client'

import type { WaveBuoy } from '@/store/appStore'
import { getWaveColor, degToCompassFR } from '@/lib/utils'
import { useSwipe } from '@/hooks/useSwipe'
import { EmbedPicker } from './EmbedPicker'

interface Props { buoy: WaveBuoy; onClose: () => void; onSwipe?: (dir: 'left' | 'right') => void }

export function BuoySheet({ buoy, onClose, onSwipe }: Props) {
  const wc = getWaveColor(buoy.hm0)
  const dir = buoy.direction ?? 0
  const compass = degToCompassFR(dir)

  // Darker wave color for hero gradient
  const wcDark = (() => {
    const hm0 = buoy.hm0
    if (hm0 < 0.5) return '#1e4a8a'
    if (hm0 < 1.0) return '#0e7a8a'
    if (hm0 < 1.5) return '#12723a'
    if (hm0 < 2.0) return '#9a7206'
    if (hm0 < 2.5) return '#b85a0e'
    return '#b82020'
  })()

  const swipe = useSwipe(onSwipe)

  return (
    <>
      <div className="sheet-backdrop" onClick={onClose} />
      <div className="sheet" {...swipe}>
        <div className="flex justify-center pt-1.5 pb-1 md:hidden">
          <div className="w-9 h-[5px] rounded-full bg-white/30" />
        </div>
        <div className="overflow-auto max-h-[calc(50vh-20px)] md:max-h-screen">
          {/* Header */}
          <div className="flex items-start justify-between px-4 pt-3 pb-1">
            <div>
              <h2 className="text-[18px] font-bold text-[#1c1c1e] tracking-tight">{buoy.name}</h2>
              <span className="text-[13px] text-[#8e8e93]">CANDHIS{buoy.region ? ` · ${buoy.region}` : ''}</span>
            </div>
            <button onClick={onClose} className="px-3 py-1 rounded-full text-[13px] font-medium text-[#007aff] glass-btn">Fermer</button>
          </div>

          {/* Hero: Wave data */}
          <div className="mx-4 mb-3 rounded-2xl overflow-hidden" style={{ background: `linear-gradient(135deg, ${wcDark}, ${wcDark}dd)` }}>
            <div className="p-4" style={{ background: 'rgba(255,255,255,0.08)' }}>
              {/* Main wave values */}
              <div className="flex items-end gap-4 mb-4">
                <div className="flex-1">
                  <div className="text-[10px] font-semibold text-white/50 uppercase tracking-widest mb-1">Hauteur significative</div>
                  <div className="flex items-baseline gap-1.5">
                    <span className="text-[52px] font-black text-white tabular-nums leading-none">{buoy.hm0.toFixed(1)}</span>
                    <span className="text-[16px] font-semibold text-white/50">m</span>
                  </div>
                </div>
                {/* Direction compass mini */}
                <div className="flex-shrink-0 flex flex-col items-center gap-1">
                  <div className="relative w-[52px] h-[52px]">
                    <svg width="52" height="52" viewBox="0 0 52 52">
                      <circle cx="26" cy="26" r="24" fill="none" stroke="white" strokeOpacity="0.2" strokeWidth="1" />
                      {['N', 'E', 'S', 'O'].map((label, i) => {
                        const angle = i * 90
                        const rad = (angle - 90) * Math.PI / 180
                        const r = 17
                        return (
                          <text key={label} x={26 + Math.cos(rad) * r} y={26 + Math.sin(rad) * r}
                            textAnchor="middle" dominantBaseline="central"
                            fill="white" fillOpacity="0.5" fontSize="7" fontWeight="800">
                            {label}
                          </text>
                        )
                      })}
                      <g transform={`rotate(${dir + 180}, 26, 26)`}>
                        <path d="M26 6L22 38l4-4 4 4z" fill="white" fillOpacity="0.9" />
                      </g>
                      <circle cx="26" cy="26" r="2" fill="white" fillOpacity="0.8" />
                    </svg>
                  </div>
                  <div className="px-1.5 py-0.5 rounded-full bg-white/15 text-[10px] font-bold text-white tabular-nums">
                    {compass} {Math.round(dir)}°
                  </div>
                </div>
              </div>

              {/* Secondary values */}
              <div className="flex gap-2">
                <div className="flex-1 rounded-xl bg-white/10 backdrop-blur-sm p-3 text-center">
                  <div className="text-[9px] font-semibold text-white/45 uppercase tracking-widest mb-1">Hmax</div>
                  <div className="text-[26px] font-black text-white/90 tabular-nums leading-none">{buoy.hmax.toFixed(1)}</div>
                  <div className="text-[11px] font-medium text-white/40 mt-0.5">m</div>
                </div>
                <div className="flex-1 rounded-xl bg-white/10 backdrop-blur-sm p-3 text-center">
                  <div className="text-[9px] font-semibold text-white/45 uppercase tracking-widest mb-1">Periode</div>
                  <div className="text-[26px] font-black text-white/90 tabular-nums leading-none">{buoy.tp.toFixed(1)}</div>
                  <div className="text-[11px] font-medium text-white/40 mt-0.5">s</div>
                </div>
                {buoy.seaTemp > 0 && (
                  <div className="flex-1 rounded-xl bg-white/10 backdrop-blur-sm p-3 text-center">
                    <div className="text-[9px] font-semibold text-white/45 uppercase tracking-widest mb-1">Temp. mer</div>
                    <div className="text-[26px] font-black text-white/90 tabular-nums leading-none">{buoy.seaTemp.toFixed(1)}</div>
                    <div className="text-[11px] font-medium text-white/40 mt-0.5">°C</div>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Details */}
          <div className="glass-card rounded-2xl mx-4 mb-4 overflow-hidden">
            {buoy.depth && (
              <div className="flex items-center justify-between px-4 py-3 border-b glass-divider">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg bg-[#007aff]/10 flex items-center justify-center">
                    <svg className="w-4 h-4 text-[#007aff]" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M19 14l-7 7m0 0l-7-7m7 7V3" /></svg>
                  </div>
                  <span className="text-[15px] text-[#1c1c1e]">Profondeur</span>
                </div>
                <span className="text-[15px] font-bold text-[#1c1c1e] tabular-nums">{buoy.depth} m</span>
              </div>
            )}
            {buoy.lastUpdate && (
              <div className="flex items-center justify-between px-4 py-3">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg bg-[#34c759]/10 flex items-center justify-center">
                    <svg className="w-4 h-4 text-[#34c759]" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
                  </div>
                  <span className="text-[15px] text-[#1c1c1e]">Mise a jour</span>
                </div>
                <span className="text-[15px] font-semibold text-[#8e8e93]">
                  {new Date(buoy.lastUpdate).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                  {' · '}{(() => {
                    const diff = Math.floor((Date.now() - new Date(buoy.lastUpdate!).getTime()) / 60000)
                    if (diff < 1) return "à l'instant"
                    if (diff < 60) return `${diff} min`
                    if (diff < 1440) return `${Math.floor(diff / 60)}h`
                    return `${Math.floor(diff / 1440)}j`
                  })()}
                </span>
              </div>
            )}
          </div>

          {/* Embed button */}
          <div className="flex justify-end px-4 pb-4 pt-1">
            <EmbedPicker type="buoy" id={buoy.id} />
          </div>
        </div>
      </div>
    </>
  )
}
