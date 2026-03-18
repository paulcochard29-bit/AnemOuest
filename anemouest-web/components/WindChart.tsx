'use client'

import { useEffect, useState } from 'react'
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

import { API } from '@/lib/api'

interface WindChartProps { stationId: string; source: string; hours?: number; windsupToken?: string | null }
interface ChartData { time: string; wind: number; gust: number }

export function WindChart({ stationId, source, hours = 6, windsupToken }: WindChartProps) {
  const [data, setData] = useState<ChartData[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    setLoading(true)
    const endpoint = source === 'pioupiou' ? 'pioupiou'
      : source === 'windcornouaille' ? 'windcornouaille'
      : source === 'meteofrance' ? 'meteofrance'
      : source === 'holfuy' || source === 'gowind' ? 'gowind'
      : source === 'windsup' ? 'windsup'
      : 'pioupiou'
    let url = `${API}/${endpoint}?history=${stationId}&hours=${hours}`
    if (source === 'windsup' && windsupToken) url += `&token=${encodeURIComponent(windsupToken)}`
    fetch(url)
      .then(r => r.json())
      .then(json => {
        setData((json.observations || []).map((o: any) => ({
          time: new Date(o.ts).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
          wind: Math.round(o.wind * 10) / 10,
          gust: Math.round(o.gust * 10) / 10,
        })))
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [stationId, source, hours, windsupToken])

  if (loading) return <div className="h-52 flex items-center justify-center"><div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" /></div>
  if (!data.length) return <div className="h-52 flex items-center justify-center text-[#8e8e93] text-[15px]">Pas de donnees</div>

  return (
    <div className="h-52">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 5, right: 5, left: -20, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e5ea" vertical={false} />
          <XAxis dataKey="time" tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} interval="preserveStartEnd" />
          <YAxis tick={{ fill: '#8e8e93', fontSize: 10 }} tickLine={false} axisLine={false} width={30} />
          <Tooltip contentStyle={{ background: '#fff', border: '1px solid #e5e5ea', borderRadius: 8, fontSize: 12, color: '#1c1c1e' }} />
          <Area type="monotone" dataKey="gust" stroke="#ff3b30" strokeWidth={1.5} fill="#ff3b3010" dot={false} name="Rafales" />
          <Area type="monotone" dataKey="wind" stroke="#007aff" strokeWidth={2} fill="#007aff12" dot={false} name="Vent" />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}
