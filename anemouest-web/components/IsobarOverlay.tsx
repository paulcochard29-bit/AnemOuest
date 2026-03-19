'use client'

import { useEffect, useRef, useState, useCallback } from 'react'
import type mapboxgl from 'mapbox-gl'
import type { WindData } from '@/lib/wind-gl'

interface IsobarOverlayProps {
  map: mapboxgl.Map
  windData: WindData | null
  visible: boolean
  forecastHour: number
}

const GRID = 20
const BOUNDS = { latMin: 38, latMax: 55, lonMin: -8, lonMax: 13 }

// Cache pressure grids by forecast hour
const pressureCache = new Map<number, (number | null)[]>()

// Isobar levels in hPa (every 4 hPa, standard meteorological practice)
const ISOBAR_INTERVAL = 4
const LABEL_INTERVAL = 8 // label every 8 hPa (every other line)

/** Bilinear interpolation of pressure at fractional grid position */
function samplePressure(pressure: (number | null)[], w: number, h: number, gx: number, gy: number): number | null {
  const x0 = Math.floor(gx)
  const y0 = Math.floor(gy)
  const x1 = Math.min(x0 + 1, w - 1)
  const y1 = Math.min(y0 + 1, h - 1)
  const fx = gx - x0
  const fy = gy - y0

  const p00 = pressure[y0 * w + x0]
  const p10 = pressure[y0 * w + x1]
  const p01 = pressure[y1 * w + x0]
  const p11 = pressure[y1 * w + x1]

  if (p00 === null || p10 === null || p01 === null || p11 === null) return null

  return (
    p00 * (1 - fx) * (1 - fy) +
    p10 * fx * (1 - fy) +
    p01 * (1 - fx) * fy +
    p11 * fx * fy
  )
}

/** Generate isobar line segments using marching squares */
function generateIsobars(
  pressure: (number | null)[],
  w: number,
  h: number,
  bounds: { latMin: number; latMax: number; lonMin: number; lonMax: number },
  level: number,
): [number, number, number, number][] {
  // Returns array of [lon1, lat1, lon2, lat2] segments
  const segments: [number, number, number, number][] = []

  for (let j = 0; j < h - 1; j++) {
    for (let i = 0; i < w - 1; i++) {
      const p00 = pressure[j * w + i]
      const p10 = pressure[j * w + i + 1]
      const p01 = pressure[(j + 1) * w + i]
      const p11 = pressure[(j + 1) * w + i + 1]

      if (p00 === null || p10 === null || p01 === null || p11 === null) continue

      // Marching squares: classify corners
      const b00 = p00 >= level ? 1 : 0
      const b10 = p10 >= level ? 1 : 0
      const b01 = p01 >= level ? 1 : 0
      const b11 = p11 >= level ? 1 : 0
      const code = b00 | (b10 << 1) | (b01 << 2) | (b11 << 3)

      if (code === 0 || code === 15) continue

      // Interpolation helpers (fractional position along edge)
      const lerp = (a: number, b: number) => a === b ? 0.5 : (level - a) / (b - a)

      // Edge midpoints (fractional grid coords)
      const top = [i + lerp(p00, p10), j] as [number, number]       // top edge
      const bottom = [i + lerp(p01, p11), j + 1] as [number, number] // bottom edge
      const left = [i, j + lerp(p00, p01)] as [number, number]       // left edge
      const right = [i + 1, j + lerp(p10, p11)] as [number, number]  // right edge

      // Convert grid coord to lon/lat
      const toLonLat = (gx: number, gy: number): [number, number] => [
        bounds.lonMin + (gx / (w - 1)) * (bounds.lonMax - bounds.lonMin),
        bounds.latMin + (gy / (h - 1)) * (bounds.latMax - bounds.latMin),
      ]

      const addSeg = (a: [number, number], b: [number, number]) => {
        const [lon1, lat1] = toLonLat(a[0], a[1])
        const [lon2, lat2] = toLonLat(b[0], b[1])
        segments.push([lon1, lat1, lon2, lat2])
      }

      // Marching squares cases
      switch (code) {
        case 1: case 14: addSeg(top, left); break
        case 2: case 13: addSeg(top, right); break
        case 3: case 12: addSeg(left, right); break
        case 4: case 11: addSeg(left, bottom); break
        case 5:  addSeg(top, right); addSeg(left, bottom); break
        case 6: case 9: addSeg(top, bottom); break
        case 7: case 8: addSeg(right, bottom); break
        case 10: addSeg(top, left); addSeg(right, bottom); break
      }
    }
  }

  return segments
}

/** Upsample pressure grid using bilinear interpolation for smoother contours */
function upsamplePressure(
  pressure: (number | null)[],
  w: number,
  h: number,
  factor: number,
): { data: (number | null)[]; width: number; height: number } {
  const nw = (w - 1) * factor + 1
  const nh = (h - 1) * factor + 1
  const out: (number | null)[] = new Array(nw * nh)

  for (let j = 0; j < nh; j++) {
    for (let i = 0; i < nw; i++) {
      const gx = (i / (nw - 1)) * (w - 1)
      const gy = (j / (nh - 1)) * (h - 1)
      out[j * nw + i] = samplePressure(pressure, w, h, gx, gy)
    }
  }

  return { data: out, width: nw, height: nh }
}

export default function IsobarOverlay({ map, windData, visible, forecastHour }: IsobarOverlayProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const animRef = useRef<number>(0)
  const [pressureGrid, setPressureGrid] = useState<(number | null)[] | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  // Fetch pressure from Open-Meteo directly (fallback when API doesn't include it)
  const fetchPressure = useCallback(async (hour: number) => {
    // Use windData.pressure if available
    if (windData?.pressure) {
      const valid = windData.pressure.filter(p => p !== null).length
      if (valid > windData.width * windData.height * 0.5) {
        setPressureGrid(windData.pressure)
        return
      }
    }

    // Check cache
    if (pressureCache.has(hour)) {
      setPressureGrid(pressureCache.get(hour)!)
      return
    }

    // Fetch from Open-Meteo
    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller

    try {
      const points: { lat: string; lon: string }[] = []
      for (let i = 0; i < GRID; i++) {
        for (let j = 0; j < GRID; j++) {
          points.push({
            lat: (BOUNDS.latMin + (BOUNDS.latMax - BOUNDS.latMin) * (i / (GRID - 1))).toFixed(4),
            lon: (BOUNDS.lonMin + (BOUNDS.lonMax - BOUNDS.lonMin) * (j / (GRID - 1))).toFixed(4),
          })
        }
      }

      const lats = points.map(p => p.lat).join(',')
      const lons = points.map(p => p.lon).join(',')
      const pastHours = hour < 0 ? Math.abs(hour) : 0
      const fcastHours = hour >= 0 ? Math.max(hour + 1, 24) : 24
      const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}&hourly=pressure_msl&past_hours=${pastHours}&forecast_hours=${fcastHours}&models=best_match&timezone=auto`

      const res = await fetch(url, { signal: controller.signal })
      if (!res.ok) return
      const data = await res.json()
      const arr = Array.isArray(data) ? data : [data]

      const grid: (number | null)[] = new Array(GRID * GRID)
      for (let idx = 0; idx < points.length && idx < arr.length; idx++) {
        const pd = arr[idx]
        const totalHours = pd.hourly?.pressure_msl?.length || 1
        const hourIndex = Math.min(Math.max(0, pastHours + hour), totalHours - 1)
        grid[idx] = pd.hourly?.pressure_msl?.[hourIndex] ?? null
      }

      if (!controller.signal.aborted) {
        pressureCache.set(hour, grid)
        setPressureGrid(grid)
      }
    } catch (e: any) {
      if (e.name !== 'AbortError') console.error('[Isobar] Pressure fetch failed:', e.message)
    }
  }, [windData])

  useEffect(() => {
    if (!visible) return
    fetchPressure(forecastHour)
    return () => { abortRef.current?.abort() }
  }, [visible, forecastHour, fetchPressure])

  useEffect(() => {
    if (!visible || !map || !pressureGrid) {
      if (canvasRef.current?.parentNode) {
        canvasRef.current.parentNode.removeChild(canvasRef.current)
        canvasRef.current = null
      }
      return
    }

    const pressure = pressureGrid
    const gw = windData?.width ?? GRID
    const gh = windData?.height ?? GRID
    const bounds = windData?.bounds ?? BOUNDS

    const validCount = pressure.filter(p => p !== null).length
    if (validCount < gw * gh * 0.3) return

    // Upsample for smoother contours (4x)
    const up = upsamplePressure(pressure, gw, gh, 4)

    // Determine isobar range
    const validPressures = pressure.filter((p): p is number => p !== null)
    const pMin = Math.floor(Math.min(...validPressures) / ISOBAR_INTERVAL) * ISOBAR_INTERVAL
    const pMax = Math.ceil(Math.max(...validPressures) / ISOBAR_INTERVAL) * ISOBAR_INTERVAL

    // Generate all isobar levels
    const levels: { level: number; segments: [number, number, number, number][]; isLabel: boolean }[] = []
    for (let p = pMin; p <= pMax; p += ISOBAR_INTERVAL) {
      const segs = generateIsobars(up.data, up.width, up.height, bounds, p)
      if (segs.length > 0) {
        levels.push({ level: p, segments: segs, isLabel: p % LABEL_INTERVAL === 0 })
      }
    }

    // Create canvas
    const container = map.getCanvasContainer()
    const mapCanvas = map.getCanvas()
    const canvas = document.createElement('canvas')
    canvas.style.position = 'absolute'
    canvas.style.top = '0'
    canvas.style.left = '0'
    canvas.style.pointerEvents = 'none'
    canvas.style.zIndex = '10'
    canvas.width = mapCanvas.width
    canvas.height = mapCanvas.height
    canvas.style.width = mapCanvas.style.width
    canvas.style.height = mapCanvas.style.height
    container.appendChild(canvas)
    canvasRef.current = canvas

    const ctx = canvas.getContext('2d')!
    const dpr = window.devicePixelRatio || 1

    const resize = () => {
      const mc = map.getCanvas()
      canvas.width = mc.width
      canvas.height = mc.height
      canvas.style.width = mc.style.width
      canvas.style.height = mc.style.height
    }
    map.on('resize', resize)

    // Draw function
    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      for (const { level, segments, isLabel } of levels) {
        // Build path once, reuse for outline + fill
        const pathPoints: [number, number, number, number][] = []
        for (const [lon1, lat1, lon2, lat2] of segments) {
          if (Math.abs(lat1) > 85 || Math.abs(lat2) > 85 || Math.abs(lon1) > 180 || Math.abs(lon2) > 180) continue
          try {
            const p1 = map.project([lon1, lat1])
            const p2 = map.project([lon2, lat2])
            pathPoints.push([p1.x * dpr, p1.y * dpr, p2.x * dpr, p2.y * dpr])
          } catch { continue }
        }

        const drawPath = () => {
          ctx.beginPath()
          for (const [x1, y1, x2, y2] of pathPoints) {
            ctx.moveTo(x1, y1)
            ctx.lineTo(x2, y2)
          }
        }

        // Pass 1: dark outline for contrast against heatmap
        drawPath()
        ctx.strokeStyle = isLabel ? 'rgba(0,0,0,0.6)' : 'rgba(0,0,0,0.25)'
        ctx.lineWidth = isLabel ? 3.5 * dpr : 2 * dpr
        ctx.lineJoin = 'round'
        ctx.lineCap = 'round'
        ctx.stroke()

        // Pass 2: white line on top
        drawPath()
        ctx.strokeStyle = isLabel ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.4)'
        ctx.lineWidth = isLabel ? 1.8 * dpr : 0.8 * dpr
        ctx.lineJoin = 'round'
        ctx.lineCap = 'round'
        ctx.stroke()

        // Draw labels on major isobars
        if (isLabel && segments.length > 6) {
          const labelText = `${level}`
          ctx.font = `bold ${11 * dpr}px -apple-system, BlinkMacSystemFont, sans-serif`
          ctx.textAlign = 'center'
          ctx.textBaseline = 'middle'

          // Place labels at intervals along the contour
          const step = Math.max(1, Math.floor(segments.length / 3))
          for (let si = Math.floor(step / 2); si < segments.length; si += step) {
            const [x1, y1, x2, y2] = pathPoints[si]
            const mx = (x1 + x2) / 2
            const my = (y1 + y2) / 2

            // Skip if outside canvas
            if (mx < 0 || mx > canvas.width || my < 0 || my > canvas.height) continue

            // Background pill
            const tw = ctx.measureText(labelText).width
            const pad = 4 * dpr
            ctx.fillStyle = 'rgba(0,0,0,0.7)'
            ctx.beginPath()
            const rx = mx - tw / 2 - pad
            const ry = my - 7 * dpr
            const rw = tw + pad * 2
            const rh = 14 * dpr
            const r = 5 * dpr
            ctx.roundRect(rx, ry, rw, rh, r)
            ctx.fill()

            // White border on pill
            ctx.strokeStyle = 'rgba(255,255,255,0.3)'
            ctx.lineWidth = 0.5 * dpr
            ctx.stroke()

            // Text
            ctx.fillStyle = '#ffffff'
            ctx.fillText(labelText, mx, my)
          }
        }
      }
    }

    // Initial draw + redraw on move
    draw()
    const onMoveEnd = () => {
      cancelAnimationFrame(animRef.current)
      animRef.current = requestAnimationFrame(draw)
    }
    map.on('moveend', onMoveEnd)
    map.on('zoomend', onMoveEnd)

    return () => {
      cancelAnimationFrame(animRef.current)
      map.off('resize', resize)
      map.off('moveend', onMoveEnd)
      map.off('zoomend', onMoveEnd)
      if (canvas.parentNode) canvas.parentNode.removeChild(canvas)
      canvasRef.current = null
    }
  }, [visible, map, pressureGrid, windData])

  return null
}
