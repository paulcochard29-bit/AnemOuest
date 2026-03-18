'use client'

import { useEffect, useCallback, useState, useRef } from 'react'
import type mapboxgl from 'mapbox-gl'
import type { WindGL } from '@/lib/wind-gl'

interface WindTooltipProps {
  map: mapboxgl.Map
  windGL: WindGL | null
  visible: boolean
}

const DIRECTION_LABELS = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO']

function degToLabel(deg: number): string {
  const idx = Math.round(deg / 22.5) % 16
  return DIRECTION_LABELS[idx]
}

export default function WindTooltip({ map, windGL, visible }: WindTooltipProps) {
  const [data, setData] = useState<{ x: number, y: number, speedKts: number, directionDeg: number } | null>(null)
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const handleClick = useCallback((e: mapboxgl.MapMouseEvent) => {
    if (!windGL || !visible) return

    const { lng, lat } = e.lngLat
    const wind = windGL.getWindAtPoint(lng, lat)
    if (!wind) {
      setData(null)
      return
    }

    const point = map.project(e.lngLat)
    setData({ x: point.x, y: point.y, speedKts: wind.speedKts, directionDeg: wind.directionDeg })

    // Auto-hide after 4s
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    timeoutRef.current = setTimeout(() => setData(null), 4000)
  }, [map, windGL, visible])

  useEffect(() => {
    if (!visible) {
      setData(null)
      return
    }

    map.on('click', handleClick)
    return () => {
      map.off('click', handleClick)
      if (timeoutRef.current) clearTimeout(timeoutRef.current)
    }
  }, [map, visible, handleClick])

  // Update position on map move
  useEffect(() => {
    if (!data) return
    const onMove = () => {
      // Tooltip is screen-space, just hide on move
      setData(null)
    }
    map.on('movestart', onMove)
    return () => { map.off('movestart', onMove) }
  }, [map, data])

  if (!data) return null

  return (
    <div
      className="absolute z-40 pointer-events-none"
      style={{ left: data.x, top: data.y, transform: 'translate(-50%, -120%)' }}
    >
      <div className="glass-bar rounded-xl px-3 py-2 flex items-center gap-2 text-xs shadow-lg">
        {/* Wind arrow */}
        <svg
          width="20" height="20" viewBox="0 0 20 20"
          style={{ transform: `rotate(${data.directionDeg}deg)` }}
          className="shrink-0"
        >
          <path d="M10 2 L14 14 L10 11 L6 14 Z" fill="#007aff" />
        </svg>
        <div className="flex flex-col leading-tight">
          <span className="font-bold text-[13px]">{data.speedKts} nds</span>
          <span className="text-[10px] text-[#8e8e93]">{degToLabel(data.directionDeg)} ({data.directionDeg}°)</span>
        </div>
      </div>
      {/* Arrow pointing down */}
      <div className="w-0 h-0 mx-auto border-l-[6px] border-r-[6px] border-t-[6px] border-l-transparent border-r-transparent border-t-[rgba(255,255,255,0.12)]" />
    </div>
  )
}
