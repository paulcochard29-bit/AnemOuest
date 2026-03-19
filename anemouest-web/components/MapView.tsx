'use client'

import { useRef, useEffect, useCallback, useState } from 'react'
import mapboxgl from 'mapbox-gl'
import 'mapbox-gl/dist/mapbox-gl.css'
import type { WindStation, WaveBuoy, Webcam, Spot, MapStyle, LayerVisibility, SpotScoreColor } from '@/store/appStore'
import { getWindColor, getWindColorDark } from '@/lib/utils'
import { API } from '@/lib/api'

interface MapViewProps {
  stations: WindStation[]
  buoys: WaveBuoy[]
  webcams: Webcam[]
  spots: Spot[]
  spotScores: Record<string, SpotScoreColor>
  mapStyle: MapStyle
  layers: LayerVisibility
  selectedId: string | null
  radarTileUrl?: string | null
  flyTo?: { lon: number; lat: number; zoom?: number; offset?: [number, number] } | null
  onStationClick: (station: WindStation) => void
  onBuoyClick: (buoy: WaveBuoy) => void
  onWebcamClick: (webcam: Webcam) => void
  onSpotClick: (spot: Spot) => void
  onMapReady?: (map: mapboxgl.Map) => void
  onMapClick?: () => void
  mapboxToken: string
}

const STYLE_URLS: Record<MapStyle, string> = {
  streets: 'mapbox://styles/mapbox/streets-v12',
  satellite: 'mapbox://styles/mapbox/satellite-streets-v12',
  outdoors: 'mapbox://styles/mapbox/outdoors-v12',
  dark: 'mapbox://styles/mapbox/dark-v11',
}

const SPOT_COLORS: Record<string, string> = {
  kite: '#34c759',
  surf: '#007aff',
  paragliding: '#ff9500',
}

/** Dynamic density filter: calculates grid size from visible bounds to keep ~targetCount markers */
function filterByDensity<T extends { lat?: number; lon?: number; latitude?: number; longitude?: number }>(
  items: T[],
  bounds: mapboxgl.LngLatBounds,
  targetCount: number,
  pickBest?: (existing: T, candidate: T) => T,
): T[] {
  const sw = bounds.getSouthWest()
  const ne = bounds.getNorthEast()
  // Filter to visible bounds
  const visible = items.filter(item => {
    const lat = item.lat ?? item.latitude
    const lon = item.lon ?? item.longitude
    if (!isFinite(lat as number) || !isFinite(lon as number)) return false
    return (lat as number) >= sw.lat && (lat as number) <= ne.lat && (lon as number) >= sw.lng && (lon as number) <= ne.lng
  })
  if (visible.length <= targetCount) return visible
  // Calculate dynamic grid size
  const latRange = ne.lat - sw.lat
  const lonRange = ne.lng - sw.lng
  const cellsPerAxis = Math.max(2, Math.floor(Math.sqrt(targetCount)))
  const gridLat = latRange / cellsPerAxis
  const gridLon = lonRange / cellsPerAxis
  const grid: Record<string, T> = {}
  for (const item of visible) {
    const lat = item.lat ?? item.latitude ?? 0
    const lon = item.lon ?? item.longitude ?? 0
    const key = `${Math.floor(lat / gridLat)},${Math.floor(lon / gridLon)}`
    if (!grid[key]) grid[key] = item
    else if (pickBest) grid[key] = pickBest(grid[key], item)
  }
  return Object.values(grid)
}

/** Cluster stations: returns representative station + count + avg wind for each grid cell */
function clusterStations(
  stations: WindStation[],
  bounds: mapboxgl.LngLatBounds,
  targetCount: number,
): { station: WindStation; count: number; avgWind: number; avgGust: number }[] {
  const sw = bounds.getSouthWest()
  const ne = bounds.getNorthEast()
  const visible = stations.filter(s => s.lat >= sw.lat && s.lat <= ne.lat && s.lon >= sw.lng && s.lon <= ne.lng)
  if (visible.length <= targetCount) return visible.map(s => ({ station: s, count: 1, avgWind: s.wind, avgGust: s.gust }))
  const latRange = ne.lat - sw.lat
  const lonRange = ne.lng - sw.lng
  const cellsPerAxis = Math.max(2, Math.floor(Math.sqrt(targetCount)))
  const gridLat = latRange / cellsPerAxis
  const gridLon = lonRange / cellsPerAxis
  const grid: Record<string, { best: WindStation; items: WindStation[] }> = {}
  for (const s of visible) {
    const key = `${Math.floor(s.lat / gridLat)},${Math.floor(s.lon / gridLon)}`
    if (!grid[key]) grid[key] = { best: s, items: [s] }
    else {
      grid[key].items.push(s)
      if (s.wind > grid[key].best.wind) grid[key].best = s
    }
  }
  return Object.values(grid).map(g => ({
    station: g.best,
    count: g.items.length,
    avgWind: Math.round(g.items.reduce((sum, s) => sum + s.wind, 0) / g.items.length),
    avgGust: Math.round(g.items.reduce((sum, s) => sum + s.gust, 0) / g.items.length),
  }))
}

function filterByDensityWithCounts<T extends { lat?: number; lon?: number; latitude?: number; longitude?: number }>(
  items: T[],
  bounds: mapboxgl.LngLatBounds,
  targetCount: number,
): { item: T; count: number }[] {
  const sw = bounds.getSouthWest()
  const ne = bounds.getNorthEast()
  const visible = items.filter(item => {
    const lat = item.lat ?? item.latitude
    const lon = item.lon ?? item.longitude
    if (!isFinite(lat as number) || !isFinite(lon as number)) return false
    return (lat as number) >= sw.lat && (lat as number) <= ne.lat && (lon as number) >= sw.lng && (lon as number) <= ne.lng
  })
  if (visible.length <= targetCount) return visible.map(item => ({ item, count: 1 }))
  const latRange = ne.lat - sw.lat
  const lonRange = ne.lng - sw.lng
  const cellsPerAxis = Math.max(2, Math.floor(Math.sqrt(targetCount)))
  const gridLat = latRange / cellsPerAxis
  const gridLon = lonRange / cellsPerAxis
  const grid: Record<string, { item: T; count: number }> = {}
  for (const item of visible) {
    const lat = item.lat ?? item.latitude ?? 0
    const lon = item.lon ?? item.longitude ?? 0
    const key = `${Math.floor(lat / gridLat)},${Math.floor(lon / gridLon)}`
    if (!grid[key]) grid[key] = { item, count: 1 }
    else grid[key].count++
  }
  return Object.values(grid)
}

export function MapView({
  stations, buoys, webcams, spots, spotScores,
  mapStyle, layers, selectedId, radarTileUrl, flyTo,
  onStationClick, onBuoyClick, onWebcamClick, onSpotClick,
  onMapReady, onMapClick, mapboxToken,
}: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<mapboxgl.Map | null>(null)
  const markersRef = useRef<Map<string, mapboxgl.Marker>>(new Map())

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return
    mapboxgl.accessToken = mapboxToken
    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: STYLE_URLS[mapStyle],
      center: [-3.5, 47.5],
      zoom: 7,
      projection: 'mercator',
      attributionControl: false,
    })
    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'bottom-right')
    mapRef.current = map
    onMapReady?.(map)
    return () => { map.remove(); mapRef.current = null }
  }, [mapboxToken])

  // Map background click (for closing popups)
  useEffect(() => {
    const map = mapRef.current
    if (!map || !onMapClick) return
    const handler = () => onMapClick()
    map.on('click', handler)
    return () => { map.off('click', handler) }
  }, [onMapClick])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    map.setStyle(STYLE_URLS[mapStyle])
  }, [mapStyle])

  useEffect(() => {
    if (!flyTo || !mapRef.current) return
    if (!isFinite(flyTo.lat) || !isFinite(flyTo.lon) || Math.abs(flyTo.lat) > 90 || Math.abs(flyTo.lon) > 180) return
    mapRef.current.flyTo({ center: [flyTo.lon, flyTo.lat], zoom: flyTo.zoom || 12, duration: 1200, offset: flyTo.offset || [0, 0] })
  }, [flyTo])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    const applyRadar = () => {
      if (map.getLayer('radar-layer')) map.removeLayer('radar-layer')
      if (map.getSource('radar-source')) map.removeSource('radar-source')
      if (!radarTileUrl) return
      map.addSource('radar-source', { type: 'raster', tiles: [radarTileUrl], tileSize: 256 })
      map.addLayer({ id: 'radar-layer', type: 'raster', source: 'radar-source', paint: { 'raster-opacity': 0.5 } })
    }
    if (map.isStyleLoaded()) applyRadar()
    else map.once('style.load', applyRadar)
  }, [radarTileUrl])


  const clearMarkers = useCallback((prefix: string) => {
    markersRef.current.forEach((marker, key) => {
      if (key.startsWith(prefix)) {
        marker.remove()
        markersRef.current.delete(key)
      }
    })
  }, [])

  // Webcam image refresh tick (updates every 2min to bust cache)
  const [webcamTick, setWebcamTick] = useState(0)
  useEffect(() => {
    const i = setInterval(() => setWebcamTick(t => t + 1), 120000)
    return () => clearInterval(i)
  }, [])

  // Re-render markers on zoom/move
  const [mapBounds, setMapBounds] = useState<mapboxgl.LngLatBounds | null>(null)
  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    const update = () => setMapBounds(map.getBounds())
    map.on('moveend', update)
    map.on('zoomend', update)
    map.once('load', update)
    return () => { map.off('moveend', update); map.off('zoomend', update) }
  }, [])

  // Wind stations (with clustering)
  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    clearMarkers('wind-')
    const bounds = map.getBounds()
    if (!bounds) return
    const onlineStations = stations.filter(s => s.isOnline && isFinite(s.lat) && isFinite(s.lon))
    const clusters = clusterStations(onlineStations, bounds, 80)
    for (const { station: s, count, avgWind, avgGust } of clusters) {
      const el = document.createElement('div')
      el.className = 'wind-marker'
      const isSelected = selectedId === s.id
      const wc = getWindColor(s.wind)
      const wcDark = getWindColorDark(s.wind)
      el.innerHTML = `
        <div class="wind-pill ${isSelected ? 'selected' : ''}" style="--wc:${wc};--wc-dark:${wcDark}">
          <svg class="arrow" width="18" height="18" viewBox="0 0 18 18" style="transform:rotate(${s.direction+180}deg)"><path d="M9 2L5 15l4-3 4 3z" fill="#fff" stroke="rgba(255,255,255,0.3)" stroke-width="0.5" stroke-linejoin="round"/></svg>
          <div class="vals">
            <span class="avg">${Math.round(s.wind)}</span>
            ${s.source !== 'ndbc' ? `<span class="dot">&bull;</span><span class="gust">${Math.round(s.gust)}</span>` : ''}
          </div>
          ${count > 1 ? `<div class="wind-cluster-badge">${count}</div>` : ''}
        </div>
      `
      el.addEventListener('click', (e) => { e.stopPropagation(); onStationClick(s) })
      const marker = new mapboxgl.Marker({ element: el, anchor: 'center' }).setLngLat([s.lon, s.lat]).addTo(map)
      marker.getElement().style.zIndex = '10'
      markersRef.current.set(`wind-${s.id}`, marker)
    }
  }, [stations, selectedId, onStationClick, clearMarkers, mapBounds])

  // Buoys
  useEffect(() => {
    const map = mapRef.current
    if (!map || !layers.buoys) { clearMarkers('buoy-'); return }
    clearMarkers('buoy-')
    for (const b of buoys.filter(b => isFinite(b.lat) && isFinite(b.lon))) {
      const el = document.createElement('div')
      el.className = 'buoy-marker'
      const isSelected = selectedId === b.id
      const hm0 = (b.hm0 ?? 0).toFixed(1)
      const tp = Math.round(b.tp ?? 0)
      const dir = Math.round(b.direction ?? 0)
      el.innerHTML = `
        <div class="buoy-pill ${isSelected ? 'selected' : ''}">
          <div class="buoy-data">
            <span>${hm0}<span class="buoy-unit">m</span></span>
            <span>${tp}<span class="buoy-unit">s</span></span>
            <span>${dir}<span class="buoy-unit">°</span></span>
          </div>
          <svg class="buoy-arrow" width="16" height="16" viewBox="0 0 24 24" style="transform:rotate(${dir+180}deg)"><path d="M12 2l-5 18h10z" fill="#007aff"/></svg>
        </div>
      `
      el.addEventListener('click', (e) => { e.stopPropagation(); onBuoyClick(b) })
      const marker = new mapboxgl.Marker({ element: el, anchor: 'center' }).setLngLat([b.lon, b.lat]).addTo(map)
      marker.getElement().style.zIndex = '10'
      markersRef.current.set(`buoy-${b.id}`, marker)
    }
  }, [buoys, layers.buoys, onBuoyClick, clearMarkers])

  // Webcams — Windy-style thumbnail markers with freshness
  useEffect(() => {
    const map = mapRef.current
    if (!map || !layers.webcams) { clearMarkers('cam-'); return }
    clearMarkers('cam-')
    const bounds = map.getBounds()
    if (!bounds) return
    const validWebcams = webcams.filter(w => isFinite(w.latitude) && isFinite(w.longitude) && Math.abs(w.latitude) <= 90 && Math.abs(w.longitude) <= 180)
    const visibleWithCounts = filterByDensityWithCounts(validWebcams, bounds, 50)
    const now = Date.now()
    for (const { item: w, count } of visibleWithCounts) {
      const el = document.createElement('div')
      el.className = 'webcam-card'

      // Freshness calculation
      let overlayText = ''
      let dotColor = '#34c759' // green by default
      if (w.lastCapture) {
        const diffMs = now - w.lastCapture
        const diffMin = Math.floor(diffMs / 60000)
        const diffH = Math.floor(diffMin / 60)
        if (diffMin < 60) overlayText = `il y a ${diffMin} min`
        else if (diffH < 24) overlayText = `il y a ${diffH}h`
        else overlayText = `il y a ${Math.floor(diffH / 24)}j`
        if (diffH >= 3) dotColor = '#ff3b30' // red > 3h
        else if (diffH >= 1) dotColor = '#ff9500' // orange > 1h
      } else {
        // Fallback: show webcam name when no freshness data
        overlayText = w.name.length > 16 ? w.name.slice(0, 16) + '…' : w.name
      }

      // Low-res: use webcam-image proxy with redirect for blob-cached images (smaller), fallback to imageUrl
      const thumbUrl = `${API}/webcam-image?id=${encodeURIComponent(w.id)}&redirect=true&t=${webcamTick}`

      el.innerHTML = `
        <div class="webcam-card-img">
          <img src="${thumbUrl}" alt="" loading="lazy" data-webcam-id="${w.id}" data-fallback="${w.imageUrl}" onerror="this.src='${w.imageUrl}'" />
          <div class="webcam-card-overlay">
            <span class="webcam-card-freshness"><span class="webcam-dot-status" style="background:${dotColor}"></span>${overlayText}</span>
          </div>
          ${count > 1 ? `<div class="webcam-cluster-badge">${count}</div>` : ''}
        </div>
      `
      el.addEventListener('click', (e) => { e.stopPropagation(); onWebcamClick(w) })
      const marker = new mapboxgl.Marker({ element: el, anchor: 'bottom' }).setLngLat([w.longitude, w.latitude]).addTo(map)
      marker.getElement().style.zIndex = '1'
      markersRef.current.set(`cam-${w.id}`, marker)
    }
  }, [webcams, layers.webcams, onWebcamClick, clearMarkers, mapBounds])

  // Refresh webcam images in-place without recreating markers (no flash)
  useEffect(() => {
    if (webcamTick === 0) return
    markersRef.current.forEach((marker, key) => {
      if (!key.startsWith('cam-')) return
      const img = marker.getElement().querySelector('img[data-webcam-id]') as HTMLImageElement | null
      if (!img) return
      const id = img.dataset.webcamId
      const fallback = img.dataset.fallback || ''
      const newUrl = `${API}/webcam-image?id=${encodeURIComponent(id!)}&redirect=true&t=${webcamTick}`
      // Double-buffer: load new image off-screen, swap only when loaded
      const cardImg = img.closest('.webcam-card-img') as HTMLElement | null
      img.style.opacity = '0.5'
      const preload = new Image()
      preload.onload = () => { img.src = newUrl; img.style.opacity = '1' }
      preload.onerror = () => { img.src = fallback; img.style.opacity = '1' }
      preload.src = newUrl
    })
  }, [webcamTick])

  // Spots
  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    clearMarkers('spot-')
    const zoom = map.getZoom()
    if (zoom < 8) return
    const bounds = map.getBounds()
    if (!bounds) return
    const types: (keyof LayerVisibility)[] = ['kiteSpots', 'surfSpots', 'paraglidingSpots']
    const typeMap: Record<string, string> = { kiteSpots: 'kite', surfSpots: 'surf', paraglidingSpots: 'paragliding' }
    for (const type of types) {
      if (!layers[type]) continue
      const typeSpots = spots.filter(s => s.spotType === typeMap[type] && isFinite(s.lat) && isFinite(s.lon) && Math.abs(s.lat) <= 90 && Math.abs(s.lon) <= 180)
      const visible = filterByDensity(typeSpots, bounds, 80)
      for (const s of visible) {
        const color = SPOT_COLORS[s.spotType] || '#8e8e93'
        const el = document.createElement('div')
        el.className = 'spot-dot'
        el.style.background = color + '18'
        el.style.borderColor = color
        el.addEventListener('click', (e) => { e.stopPropagation(); onSpotClick(s) })
        const marker = new mapboxgl.Marker({ element: el, anchor: 'center' }).setLngLat([s.lon, s.lat]).addTo(map)
        markersRef.current.set(`spot-${s.id}`, marker)
      }
    }
  }, [spots, layers, onSpotClick, clearMarkers, mapBounds])


  return <div ref={containerRef} className="w-full h-full" />
}
