'use client'

import { useEffect, useRef, useCallback } from 'react'
import type mapboxgl from 'mapbox-gl'
import { WindGL } from '@/lib/wind-gl'
import type { WindData } from '@/lib/wind-gl'
import { API as API_BASE, apiFetch } from '@/lib/api'
const LAYER_ID = 'wind-gl-layer'
const COASTLINE_ID = 'wind-coastline'
const FETCH_THROTTLE_MS = 800 // Min delay between API calls


interface WindOverlayProps {
  map: mapboxgl.Map
  visible: boolean
  forecastHour: number
  onWindGLChange?: (windGL: import('@/lib/wind-gl').WindGL | null) => void
  onWindDataChange?: (data: WindData | null) => void
}

// Simple in-memory cache for wind data (shared across re-renders)
const windDataCache = new Map<number, WindData>()

export default function WindOverlay({ map, visible, forecastHour, onWindGLChange, onWindDataChange }: WindOverlayProps) {
  const windGLRef = useRef<WindGL | null>(null)
  const abortRef = useRef<AbortController | null>(null)
  const lastFetchTime = useRef(0)
  const pendingHour = useRef<number | null>(null)
  const throttleTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Fetch wind data and pass to renderer
  const loadData = useCallback(async (hour: number, windGL: WindGL) => {
    // Check cache first
    const cached = windDataCache.get(hour)
    if (cached) {
      windGL.setWindData(cached)
      onWindDataChange?.(cached)
      map.triggerRepaint()
      return
    }

    // Throttle: if we fetched recently, defer this request
    const now = Date.now()
    const elapsed = now - lastFetchTime.current
    if (elapsed < FETCH_THROTTLE_MS) {
      pendingHour.current = hour
      if (!throttleTimer.current) {
        throttleTimer.current = setTimeout(() => {
          throttleTimer.current = null
          const h = pendingHour.current
          pendingHour.current = null
          if (h !== null && windGLRef.current) {
            loadData(h, windGLRef.current)
          }
        }, FETCH_THROTTLE_MS - elapsed)
      }
      return
    }

    abortRef.current?.abort()
    const controller = new AbortController()
    abortRef.current = controller
    lastFetchTime.current = now

    try {
      const res = await apiFetch(`${API_BASE}/wind-tiles?t=${hour}`, {
        signal: controller.signal,
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data: WindData = await res.json()
      if (!controller.signal.aborted) {
        windDataCache.set(hour, data)
        windGL.setWindData(data)
        onWindDataChange?.(data)
        map.triggerRepaint()
      }
    } catch (e: any) {
      if (e.name !== 'AbortError') {
        console.error('[WindOverlay] Failed to load wind data:', e.message)
      }
    }
  }, [map])

  // Main effect: manage layer lifecycle
  useEffect(() => {
    if (!visible) {
      for (const lid of [COASTLINE_ID, LAYER_ID]) {
        if (map.getLayer(lid)) { try { map.removeLayer(lid) } catch {} }
      }

      if (windGLRef.current) {
        windGLRef.current.dispose()
        windGLRef.current = null
        onWindGLChange?.(null)
        onWindDataChange?.(null)
      }
      return
    }

    const windGL = new WindGL()
    windGLRef.current = windGL
    onWindGLChange?.(windGL)

    const addLayer = () => {
      if (map.getLayer(LAYER_ID)) return
      try {
        // Find first symbol layer (labels, POIs, cities) — insert wind below it
        // so coastlines, borders, city names, and roads all render on top
        const layers = map.getStyle()?.layers || []
        let beforeId: string | undefined
        for (const l of layers) {
          if (l.type === 'symbol' || l.id.includes('admin') || l.id.includes('boundary') || l.id.includes('label')) {
            beforeId = l.id
            break
          }
        }
        map.addLayer(windGL as any, beforeId)

        // Add coastline outline on top of wind (water polygon border = land/sea edge)
        if (!map.getLayer(COASTLINE_ID) && map.getSource('composite')) {
          map.addLayer({
            id: COASTLINE_ID,
            type: 'line',
            source: 'composite',
            'source-layer': 'water',
            paint: {
              'line-color': '#000000',
              'line-width': ['interpolate', ['linear'], ['zoom'], 4, 0.5, 8, 1, 12, 1.5],
              'line-opacity': 0.7,
            },
          })
        }

        console.log('[WindOverlay] Layer added to map, before:', beforeId)
      } catch (e: any) {
        console.error('[WindOverlay] Failed to add layer:', e.message)
      }
    }

    if (map.isStyleLoaded()) {
      addLayer()
    } else {
      map.once('style.load', addLayer)
    }

    const onStyleLoad = () => {
      if (!windGLRef.current || windGLRef.current !== windGL) return
      setTimeout(() => {
        if (windGLRef.current === windGL) {
          if (!map.getLayer(LAYER_ID)) {
            addLayer()
          }
          loadData(forecastHour, windGL)
        }
      }, 300)
    }
    map.on('style.load', onStyleLoad)

    loadData(forecastHour, windGL)

    return () => {
      map.off('style.load', onStyleLoad)
      abortRef.current?.abort()
      if (throttleTimer.current) clearTimeout(throttleTimer.current)
      for (const lid of [COASTLINE_ID, LAYER_ID]) {
        if (map.getLayer(lid)) { try { map.removeLayer(lid) } catch {} }
      }

      windGL.dispose()
      windGLRef.current = null
      onWindGLChange?.(null)
    }
  }, [map, visible]) // eslint-disable-line react-hooks/exhaustive-deps

  // Reload data when forecast hour changes
  useEffect(() => {
    if (!visible || !windGLRef.current) return
    loadData(forecastHour, windGLRef.current)
  }, [forecastHour, visible, loadData])

  return null
}
