'use client'

import { useState, useEffect } from 'react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import type { WaveBuoy } from '@/store/appStore'
import { getWaveColor, degToCompassFR } from '@/lib/utils'

const API = 'https://anemouest-api.vercel.app/api'

interface Props {
  buoy: WaveBuoy
  expanded: boolean
  onExpand: () => void
}

interface HistoryPoint { time: string; hm0: number; hmax?: number; tp?: number }

export function BuoyPopupContent({ buoy, expanded, onExpand }: Props) {
  const wc = getWaveColor(buoy.hm0)
  const compass = degToCompassFR(buoy.direction ?? 0)
  const [history, setHistory] = useState<HistoryPoint[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch(`${API}/candhis?id=${buoy.id}&history=true`)
      .then(r => r.json())
      .then(data => {
        if (data.history && data.history.length > 0) {
          setHistory(data.history.slice(-48).map((h: any) => ({
            time: new Date(h.timestamp).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
            hm0: h.hm0,
            hmax: h.hmax,
            tp: h.tp,
          })))
        }
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [buoy.id])

  return (
    <div>
      {/* Hero */}
      <div className="px-4 py-3" style={{ background: `linear-gradient(135deg, ${wc}, #1a3a5c)` }}>
        <div className="text-[13px] font-semibold text-white/80 truncate">{buoy.name}</div>
        <div className="flex items-center gap-3 mt-1">
          <div className="flex items-baseline gap-1.5">
            <span className="text-[32px] font-black text-white leading-none">{buoy.hm0.toFixed(1)}</span>
            <span className="text-[13px] font-bold text-white/60">m</span>
          </div>
          <div className="flex flex-col gap-0.5 text-[12px] font-semibold text-white/80">
            <span>{Math.round(buoy.tp)}s</span>
            <span>{compass} {Math.round(buoy.direction ?? 0)}°</span>
          </div>
          {buoy.seaTemp > 0 && (
            <div className="ml-auto text-[18px] font-bold text-white/70">
              {buoy.seaTemp.toFixed(1)}°
            </div>
          )}
        </div>
      </div>

      {/* Chart */}
      <div className="px-3 pt-2 pb-1">
        <span className="text-[10px] font-bold text-[#8e8e93] uppercase tracking-wider">Historique 48h</span>
        <div className="h-24 mt-1">
          {loading ? (
            <div className="w-full h-full flex items-center justify-center">
              <div className="w-4 h-4 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
            </div>
          ) : history.length > 0 ? (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={history} margin={{ top: 4, right: 4, left: -24, bottom: 0 }}>
                <defs>
                  <linearGradient id="bwg" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={wc} stopOpacity={0.25} />
                    <stop offset="95%" stopColor={wc} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.05)" vertical={false} />
                <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fill: '#8e8e93', fontSize: 9 }} tickLine={false} axisLine={false} width={28} />
                <Tooltip contentStyle={{ background: 'rgba(255,255,255,0.92)', backdropFilter: 'blur(16px)', border: 'none', borderRadius: 10, fontSize: 11, boxShadow: '0 2px 12px rgba(0,0,0,0.1)' }} />
                {history[0]?.hmax !== undefined && (
                  <Area type="monotone" dataKey="hmax" stroke="#ff3b30" strokeWidth={1} fill="none" dot={false} strokeDasharray="3 3" name="Hmax" />
                )}
                <Area type="monotone" dataKey="hm0" stroke={wc} strokeWidth={2} fill="url(#bwg)" dot={false} name="H1/3" />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="w-full h-full flex items-center justify-center text-[#8e8e93] text-[12px]">Pas de données</div>
          )}
        </div>
      </div>

      {/* Expanded: extra details */}
      {expanded && (
        <div className="px-3 pb-1">
          <div className="flex gap-1.5 mb-2">
            <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Hmax</div>
              <div className="text-[16px] font-bold text-[#ff3b30] tabular-nums">{buoy.hmax.toFixed(1)}m</div>
            </div>
            <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
              <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Période</div>
              <div className="text-[16px] font-bold text-[#007aff] tabular-nums">{buoy.tp.toFixed(1)}s</div>
            </div>
            {buoy.depth && (
              <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2 py-1.5 text-center">
                <div className="text-[9px] font-semibold text-[#8e8e93] uppercase">Prof.</div>
                <div className="text-[16px] font-bold text-[#5856d6] tabular-nums">{buoy.depth}m</div>
              </div>
            )}
          </div>
          {buoy.lastUpdate && (
            <div className="bg-[#f2f2f7] rounded-lg px-3 py-1.5 flex items-center gap-2 mb-1">
              <svg className="w-3.5 h-3.5 text-[#8e8e93] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
              <span className="text-[11px] text-[#8e8e93]">
                {new Date(buoy.lastUpdate).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          )}
        </div>
      )}

      {/* Footer */}
      <div className="px-3 py-2 flex items-center justify-between">
        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#007aff] text-white">CANDHIS</span>
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
