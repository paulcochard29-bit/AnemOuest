'use client'

import { COLOR_STOPS_KTS } from '@/lib/wind-gl'

// Pick representative stops for the legend gradient
const LEGEND_STOPS = [0, 5, 11, 16, 22, 30, 43, 65]

function ktsToColor(kts: number): string {
  if (kts <= COLOR_STOPS_KTS[0][0]) return `rgb(${COLOR_STOPS_KTS[0][1]},${COLOR_STOPS_KTS[0][2]},${COLOR_STOPS_KTS[0][3]})`
  for (let i = 1; i < COLOR_STOPS_KTS.length; i++) {
    if (kts <= COLOR_STOPS_KTS[i][0]) {
      const [k0, r0, g0, b0] = COLOR_STOPS_KTS[i - 1]
      const [k1, r1, g1, b1] = COLOR_STOPS_KTS[i]
      const t = (kts - k0) / (k1 - k0)
      return `rgb(${Math.round(r0 + t * (r1 - r0))},${Math.round(g0 + t * (g1 - g0))},${Math.round(b0 + t * (b1 - b0))})`
    }
  }
  const last = COLOR_STOPS_KTS[COLOR_STOPS_KTS.length - 1]
  return `rgb(${last[1]},${last[2]},${last[3]})`
}

export default function WindLegend() {
  const gradient = LEGEND_STOPS.map(kts => ktsToColor(kts)).join(', ')

  return (
    <div className="absolute bottom-6 left-2.5 z-10 glass-bar rounded-xl px-3 py-2 flex flex-col gap-1">
      <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Vent (nds)</span>
      <div className="flex items-center gap-1.5">
        <div
          className="w-32 h-2.5 rounded-full"
          style={{ background: `linear-gradient(to right, ${gradient})` }}
        />
      </div>
      <div className="flex justify-between w-32">
        {[0, 10, 20, 35, 50].map(v => (
          <span key={v} className="text-[9px] text-[#8e8e93] tabular-nums">{v}</span>
        ))}
      </div>
    </div>
  )
}
