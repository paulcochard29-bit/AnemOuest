'use client'

import { useState, useCallback, useMemo, useEffect, useRef } from 'react'
import dynamic from 'next/dynamic'
import type mapboxgl from 'mapbox-gl'
import { useAppStore } from '@/store/appStore'
import type { WindStation, WaveBuoy, Webcam, Spot, TidePort, MapStyle } from '@/store/appStore'
import { ALL_SOURCES, LAYER_TOGGLES } from '@/store/appStore'
import { useStations, useBuoys, useWebcams, useSpots, useRadar } from '@/hooks'
import { useTides, useTideForLocation } from '@/hooks/useTides'
import { MapPopup } from '@/components/MapPopup'
import { StationPopupContent } from '@/components/popups/StationPopupContent'
import { BuoyPopupContent } from '@/components/popups/BuoyPopupContent'
import { WebcamPopupContent } from '@/components/popups/WebcamPopupContent'
import { SpotPopupContent } from '@/components/popups/SpotPopupContent'
import { TidePopupContent } from '@/components/popups/TidePopupContent'
import { TideWidget } from '@/components/TideWidget'
import { TidePanel } from '@/components/TidePanel'
import { WindsUpLogin } from '@/components/WindsUpLogin'
import { ToastContainer } from '@/components/Toast'
const WindOverlay = dynamic(() => import('@/components/WindOverlay'), { ssr: false })
const WindTimeline = dynamic(() => import('@/components/WindTimeline'), { ssr: false })
const WindLegend = dynamic(() => import('@/components/WindLegend'), { ssr: false })
const WindTuner = dynamic(() => import('@/components/WindTuner'), { ssr: false })
const WindTooltip = dynamic(() => import('@/components/WindTooltip'), { ssr: false })
const IsobarOverlay = dynamic(() => import('@/components/IsobarOverlay'), { ssr: false })
const ForecastPanel = dynamic(() => import('@/components/ForecastPanel'), { ssr: false })
const MapView = dynamic(() => import('@/components/MapView').then(m => ({ default: m.MapView })), {
  ssr: false,
  loading: () => (
    <div className="w-full h-full flex items-center justify-center bg-[#f2f2f7]">
      <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
    </div>
  ),
})

const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN || 'pk.eyJ1IjoicGF1bDI5OTAwIiwiYSI6ImNta2Nvc3R6YjAzYjczZXM2Y2g3YmZkcTQifQ.CNTSppufgvTp0wQu9gKsgw'

export default function MapPage() {
  useStations()
  useBuoys()
  useWebcams()
  useSpots()
  const { tidePorts } = useTides()

  const stations = useAppStore(s => s.stations)
  const buoys = useAppStore(s => s.buoys)
  const webcams = useAppStore(s => s.webcams)
  const spots = useAppStore(s => s.spots)
  const spotScores = useAppStore(s => s.spotScores)
  const mapStyle = useAppStore(s => s.mapStyle)
  const setMapStyle = useAppStore(s => s.setMapStyle)
  const layers = useAppStore(s => s.layers)
  const toggleLayer = useAppStore(s => s.toggleLayer)
  const enabledSources = useAppStore(s => s.enabledSources)
  const toggleSource = useAppStore(s => s.toggleSource)

  const windForecastHour = useAppStore(s => s.windForecastHour)
  const setWindForecastHour = useAppStore(s => s.setWindForecastHour)
  const refreshInterval = useAppStore(s => s.refreshInterval)
  const setRefreshInterval = useAppStore(s => s.setRefreshInterval)
  const isDarkMode = useAppStore(s => s.isDarkMode)
  const toggleDarkMode = useAppStore(s => s.toggleDarkMode)

  const { radarEnabled, radarTileUrl, radarTimeLabel, radarPlaying, radarFrameIndex, totalFrames, toggleRadar, togglePlay, setRadarFrameIndex } = useRadar()

  const [popupData, setPopupData] = useState<{
    type: 'station' | 'buoy' | 'webcam' | 'spot' | 'tide'
    data: WindStation | WaveBuoy | Webcam | Spot | TidePort
    lngLat: [number, number]
  } | null>(null)
  const [popupExpanded, setPopupExpanded] = useState(false)
  const [flyTo, setFlyTo] = useState<{ lon: number; lat: number; zoom?: number; offset?: [number, number] } | null>(null)
  const [showLayers, setShowLayers] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [showSearch, setShowSearch] = useState(false)
  const geolocatedRef = useRef(false)
  const [windGLInstance, setWindGLInstance] = useState<any>(null)
  const [windData, setWindData] = useState<any>(null)
  const [showIsobars, setShowIsobars] = useState(true)
  const [showWindsUpLogin, setShowWindsUpLogin] = useState(false)
  const [windsupConnected, setWindsupConnected] = useState(false)
  const [forecastTarget, setForecastTarget] = useState<{ lat: number; lon: number; name?: string } | null>(null)

  // Check WindsUp token on mount + sync across tabs
  useEffect(() => {
    setWindsupConnected(!!localStorage.getItem('windsupToken'))
    const handler = (e: StorageEvent) => {
      if (e.key === 'windsupToken') {
        setWindsupConnected(!!e.newValue)
      }
    }
    window.addEventListener('storage', handler)
    return () => window.removeEventListener('storage', handler)
  }, [])

  // Auto-geolocate on first load
  useEffect(() => {
    if (geolocatedRef.current || !navigator.geolocation) return
    geolocatedRef.current = true
    navigator.geolocation.getCurrentPosition(
      (pos) => setFlyTo({ lon: pos.coords.longitude, lat: pos.coords.latitude, zoom: 9 }),
      () => {},
      { enableHighAccuracy: false, timeout: 5000 }
    )
  }, [])


  const handleGeolocate = useCallback(() => {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (pos) => setFlyTo({ lon: pos.coords.longitude, lat: pos.coords.latitude, zoom: 12 }),
      () => {},
      { enableHighAccuracy: true, timeout: 10000 }
    )
  }, [])

  const [mapInstance, setMapInstance] = useState<mapboxgl.Map | null>(null)

  // Track map center for tide widget
  const [mapCenter, setMapCenter] = useState<{ lat: number; lon: number }>({ lat: 47.5, lon: -3.5 })
  useEffect(() => {
    if (!mapInstance) return
    const handler = () => {
      const c = mapInstance.getCenter()
      setMapCenter({ lat: c.lat, lon: c.lng })
    }
    mapInstance.on('moveend', handler)
    handler() // initial
    return () => { mapInstance.off('moveend', handler) }
  }, [mapInstance])

  const { tideData, tidePortName, nextTideEvents, nearestPort } = useTideForLocation(
    layers.tides ? mapCenter.lat : null,
    layers.tides ? mapCenter.lon : null,
    tidePorts
  )

  const popupId = popupData ? ((popupData.data as any).cst || (popupData.data as any).id) : null

  const closePopup = useCallback(() => {
    setPopupData(null)
    setPopupExpanded(false)
  }, [])

  // Marker click → open popup with chart
  const handleStationClick = useCallback((s: WindStation) => {
    setPopupData({ type: 'station', data: s, lngLat: [s.lon, s.lat] })
    setPopupExpanded(false)
    setFlyTo({ lon: s.lon, lat: s.lat, zoom: 10, offset: [0, 100] })
  }, [])
  const handleBuoyClick = useCallback((b: WaveBuoy) => {
    setPopupData({ type: 'buoy', data: b, lngLat: [b.lon, b.lat] })
    setPopupExpanded(false)
    setFlyTo({ lon: b.lon, lat: b.lat, zoom: 10, offset: [0, 100] })
  }, [])
  const handleWebcamClick = useCallback((w: Webcam) => {
    setPopupData({ type: 'webcam', data: w, lngLat: [w.longitude, w.latitude] })
    setPopupExpanded(false)
    setFlyTo({ lon: w.longitude, lat: w.latitude, zoom: 11, offset: [0, 100] })
  }, [])
  const handleSpotClick = useCallback((s: Spot) => {
    setPopupData({ type: 'spot', data: s, lngLat: [s.lon, s.lat] })
    setPopupExpanded(false)
    setFlyTo({ lon: s.lon, lat: s.lat, zoom: 11, offset: [0, 100] })
  }, [])
  const handleTideClick = useCallback((p: TidePort) => {
    setPopupData({ type: 'tide', data: p, lngLat: [p.lon, p.lat] })
    setPopupExpanded(false)
    setFlyTo({ lon: p.lon, lat: p.lat, zoom: 10, offset: [0, 100] })
  }, [])

  const [showTidePanel, setShowTidePanel] = useState(false)
  const handleTideWidgetClick = useCallback(() => {
    if (!nearestPort) return
    setShowTidePanel(prev => !prev)
  }, [nearestPort])

  // "Voir plus" / "Réduire" toggles expansion within the popup
  const handleToggleExpand = useCallback(() => {
    setPopupExpanded(prev => !prev)
  }, [])

  const searchResults = useMemo(() => {
    if (!searchQuery.trim()) return []
    const q = searchQuery.toLowerCase()
    const r: { id: string; name: string; type: string; color: string; icon: string; action: () => void }[] = []
    stations.filter(s => s.isOnline && s.name.toLowerCase().includes(q)).slice(0, 5).forEach(s => r.push({ id: s.id, name: s.name, type: 'Station', color: '#007aff', icon: 'station', action: () => handleStationClick(s) }))
    buoys.filter(b => b.name.toLowerCase().includes(q)).slice(0, 3).forEach(b => r.push({ id: b.id, name: b.name, type: 'Bouée', color: '#06b6d4', icon: 'buoy', action: () => handleBuoyClick(b) }))
    webcams.filter(w => (w.name + w.location).toLowerCase().includes(q)).slice(0, 3).forEach(w => r.push({ id: w.id, name: w.name, type: 'Webcam', color: '#a855f7', icon: 'webcam', action: () => handleWebcamClick(w) }))
    spots.filter(s => s.name.toLowerCase().includes(q)).slice(0, 5).forEach(s => {
      const label = s.spotType === 'kite' ? 'Kite' : s.spotType === 'surf' ? 'Surf' : 'Parapente'
      const color = s.spotType === 'kite' ? '#34c759' : s.spotType === 'surf' ? '#007aff' : '#ff9500'
      const icon = s.spotType === 'kite' ? 'kite' : s.spotType === 'surf' ? 'surf' : 'paragliding'
      r.push({ id: s.id, name: s.name, type: label, color, icon, action: () => handleSpotClick(s) })
    })
    tidePorts.filter(p => p.name.toLowerCase().includes(q)).slice(0, 3).forEach(p => {
      r.push({ id: p.cst, name: p.name, type: 'Marée', color: '#14b8a6', icon: 'tide', action: () => handleTideClick(p) })
    })
    return r
  }, [searchQuery, stations, buoys, webcams, spots, tidePorts, handleStationClick, handleBuoyClick, handleWebcamClick, handleSpotClick, handleTideClick])

  const onlineCount = stations.filter(s => s.isOnline).length

  return (
    <div className="fixed inset-0 overflow-hidden">
      <ToastContainer />
      <MapView
        stations={stations.filter(s => enabledSources.includes(s.source) || (enabledSources.includes('gowind') && (s.source === 'holfuy' || s.source === 'windguru')))}
        buoys={buoys} webcams={webcams} spots={spots} spotScores={spotScores}
        mapStyle={mapStyle} layers={layers} selectedId={popupId}
        radarTileUrl={radarTileUrl} flyTo={flyTo}
        onStationClick={handleStationClick} onBuoyClick={handleBuoyClick}
        onWebcamClick={handleWebcamClick} onSpotClick={handleSpotClick}
        onMapReady={setMapInstance} onMapClick={closePopup}
        mapboxToken={MAPBOX_TOKEN}
      />

      {/* === TOP: Search bar + tide widget === */}
      <div className="absolute top-2.5 left-2.5 right-14 z-10 flex gap-2">
        {/* Tide widget (left of search) */}
        {layers.tides && tideData && (
          <TideWidget
            portName={tidePortName}
            tideData={tideData}
            nextTideEvents={nextTideEvents}
            onClick={handleTideWidgetClick}
          />
        )}
        <div className="flex-1 relative">
          <div className="glass-bar rounded-2xl flex items-center overflow-hidden">
            <svg className="w-4 h-4 ml-3 text-[#8e8e93] flex-shrink-0" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <input type="text" value={searchQuery}
              onChange={e => { setSearchQuery(e.target.value); setShowSearch(true) }}
              onFocus={() => setShowSearch(true)}
              placeholder="Rechercher"
              className="w-full px-2.5 py-2 bg-transparent text-[15px] text-[#1c1c1e] placeholder-[#8e8e93] focus:outline-none"
            />
            {searchQuery && (
              <button onClick={() => { setSearchQuery(''); setShowSearch(false) }} className="p-2 text-[#8e8e93]">
                <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            )}
          </div>

          {showSearch && searchResults.length > 0 && (
            <div className="absolute top-full mt-1 left-0 right-0 glass-bar rounded-2xl overflow-hidden z-20">
              {searchResults.map(r => (
                <button key={`${r.type}-${r.id}`}
                  className="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-white/30 text-left border-b border-white/10 last:border-0"
                  onClick={() => { r.action(); setSearchQuery(''); setShowSearch(false) }}
                >
                  <div className="w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: `${r.color}18` }}>
                    {r.icon === 'station' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M3 17l4-9 4 5 4-7 6 11" /></svg>}
                    {r.icon === 'buoy' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" /><path d="M12 4v16M4 12h16" /></svg>}
                    {r.icon === 'webcam' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" /></svg>}
                    {r.icon === 'kite' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M3.5 3.5L12 21l8.5-17.5L12 8z" /></svg>}
                    {r.icon === 'surf' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M2 12c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /><path strokeLinecap="round" d="M2 18c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /></svg>}
                    {r.icon === 'paragliding' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M12 3C6 3 2 7 2 7l10 5 10-5s-4-4-10-4zM12 12v9" /></svg>}
                    {r.icon === 'tide' && <svg className="w-3.5 h-3.5" fill="none" stroke={r.color} strokeWidth={2} viewBox="0 0 24 24" strokeLinecap="round"><path d="M2 10c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /><path d="M2 16c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /></svg>}
                  </div>
                  <span className="text-[14px] font-medium text-[#1c1c1e] truncate flex-1">{r.name}</span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0 text-white glass-tag" style={{ background: r.color }}>
                    {r.type}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Station count pill */}
        <div className="glass-bar rounded-2xl px-3 flex items-center gap-1.5 flex-shrink-0">
          <span className="w-[6px] h-[6px] rounded-full bg-[#34c759]" />
          <span className="text-[15px] font-semibold text-[#1c1c1e] tabular-nums">{onlineCount}</span>
        </div>
      </div>

      {/* === TIDE PANEL (opens from widget) === */}
      {showTidePanel && nearestPort && (
        <div className="absolute top-[60px] left-2.5 z-20 w-80 glass-bar rounded-2xl overflow-hidden max-h-[calc(100vh-80px)] overflow-y-auto">
          <TidePanel port={nearestPort} onClose={() => setShowTidePanel(false)} />
        </div>
      )}

      {/* === RIGHT TOP TOOLBAR (settings + radar) === */}
      <div className="absolute right-2.5 top-2.5 z-10 flex flex-col glass-bar rounded-2xl overflow-hidden">
        <button onClick={() => setShowLayers(!showLayers)}
          className="w-10 h-10 flex items-center justify-center border-b border-white/20 transition-all duration-200"
          style={showLayers ? { color: '#007aff', background: 'color-mix(in srgb, #007aff 10%, transparent)' } : { color: 'var(--text-tertiary)' }}>
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75" /></svg>
        </button>
        <button onClick={toggleRadar}
          className="w-10 h-10 flex items-center justify-center border-b border-white/20 transition-all duration-200"
          style={radarEnabled ? { color: '#007aff', background: 'color-mix(in srgb, #007aff 10%, transparent)' } : { color: 'var(--text-tertiary)' }}>
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15a4.5 4.5 0 004.5 4.5H18a3.75 3.75 0 001.332-7.257 3 3 0 00-3.758-3.848 5.25 5.25 0 00-10.233 2.33A4.502 4.502 0 002.25 15z" /></svg>
        </button>
        <button onClick={handleGeolocate}
          className="w-10 h-10 flex items-center justify-center transition-all duration-200 border-b border-white/20"
          style={{ color: 'var(--text-tertiary)' }}>
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z" /><path strokeLinecap="round" strokeLinejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z" /></svg>
        </button>
        <button onClick={() => {
            const c = mapInstance?.getCenter()
            if (c) setForecastTarget({ lat: c.lat, lon: c.lng })
          }}
          className="w-10 h-10 flex items-center justify-center transition-all duration-200 border-b border-white/20"
          style={forecastTarget ? { color: '#007aff', background: 'color-mix(in srgb, #007aff 10%, transparent)' } : { color: 'var(--text-tertiary)' }}
          title="Previsions">
          <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 17l4-9 4 5 4-7 6 11" />
            <circle cx="7" cy="8" r="1.5" fill="currentColor" />
          </svg>
        </button>
        <button onClick={() => { toggleDarkMode(); if (!isDarkMode) setMapStyle('dark'); else if (mapStyle === 'dark') setMapStyle('streets'); }}
          className="w-10 h-10 flex items-center justify-center transition-all duration-200"
          style={isDarkMode ? { color: '#ffd60a', background: 'color-mix(in srgb, #ffd60a 10%, transparent)' } : { color: 'var(--text-tertiary)' }}>
          {isDarkMode ? (
            <svg className="w-[20px] h-[20px]" fill="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5" /><path d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72l1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
          ) : (
            <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z" /></svg>
          )}
        </button>
      </div>

      {/* === RIGHT CENTER: Layer toggles === */}
      <div className="absolute right-2.5 top-1/2 -translate-y-1/2 z-10 flex flex-col glass-bar rounded-2xl overflow-hidden">
        {LAYER_TOGGLES.map((l, i) => (
          <button key={l.id} onClick={() => {
              if (l.id === 'windAnimation') {
                const willEnable = !layers.windAnimation
                // Toggle site dark mode to match wind overlay aesthetic
                if (willEnable && !isDarkMode) {
                  toggleDarkMode()
                } else if (!willEnable && isDarkMode) {
                  toggleDarkMode()
                }
              }
              toggleLayer(l.id)
            }}
            className={`w-10 h-10 flex items-center justify-center transition-all duration-200 ${i < LAYER_TOGGLES.length - 1 ? 'border-b border-white/20' : ''}`}
            style={layers[l.id] ? { color: '#007aff', background: 'color-mix(in srgb, #007aff 10%, transparent)' } : { color: 'var(--text-tertiary)' }}
            title={l.name}>
            {l.id === 'buoys' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M12 21a9 9 0 100-18 9 9 0 000 18zM12 3v18M3 12h18" /></svg>
            )}
            {l.id === 'webcams' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" /></svg>
            )}
            {l.id === 'kiteSpots' && (
              <svg className="w-[20px] h-[20px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5}><path strokeLinecap="round" strokeLinejoin="round" d="M3.5 3.5L12 21l8.5-17.5L12 8z" /></svg>
            )}
            {l.id === 'surfSpots' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M2 12c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /><path strokeLinecap="round" d="M2 18c2-3 4-4 6-4s4 1 6 4 4 4 6 4" /></svg>
            )}
            {l.id === 'paraglidingSpots' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M12 3C6 3 2 7 2 7l10 5 10-5s-4-4-10-4zM12 12v9" /></svg>
            )}
            {l.id === 'tides' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" strokeLinecap="round"><path d="M2 10c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /><path d="M2 16c2-3 4-3 6 0s4 3 6 0 4-3 6 0" /></svg>
            )}
            {l.id === 'windAnimation' && (
              <svg className="w-[20px] h-[20px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" strokeLinecap="round" strokeLinejoin="round"><path d="M9.59 4.59A2 2 0 1111 8H2m10.59 11.41A2 2 0 1014 16H2m15.73-8.27A2.5 2.5 0 1119.5 12H2" /></svg>
            )}
          </button>
        ))}
      </div>

      {/* === SETTINGS PANEL === */}
      {showLayers && (
        <div className="absolute right-14 top-2.5 z-10 glass-bar rounded-2xl w-64 overflow-hidden max-h-[calc(100vh-80px)] overflow-y-auto">
          {/* Sources */}
          <div className="px-4 pt-3 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider">Sources vent</div>
          <div className="px-3 pb-2 pt-1 flex flex-wrap gap-1.5">
            {ALL_SOURCES.map(s => {
              const active = enabledSources.includes(s.id)
              const isWindsup = s.id === 'windsup'
              return (
                <button key={s.id} onClick={() => {
                    if (isWindsup && !windsupConnected) {
                      setShowWindsUpLogin(true)
                      return
                    }
                    toggleSource(s.id)
                  }}
                  className="px-2.5 py-1 rounded-full text-[12px] font-bold transition-all duration-200 flex-shrink-0 flex items-center gap-1"
                  style={active ? {
                    background: s.color,
                    color: '#fff',
                    boxShadow: `0 2px 8px ${s.color}50, inset 0 1px 0 rgba(255,255,255,0.25)`,
                  } : {
                    color: '#8e8e93',
                    background: 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
                    boxShadow: 'inset 0 0 0 1px color-mix(in srgb, var(--text-primary) 8%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.12)',
                  }}>
                  {s.name}
                  {isWindsup && !windsupConnected && (
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"><rect x="3" y="11" width="18" height="11" rx="2" /><path d="M7 11V7a5 5 0 0110 0v4" /></svg>
                  )}
                  {isWindsup && windsupConnected && active && (
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"><path d="M20 6L9 17l-5-5" /></svg>
                  )}
                </button>
              )
            })}
          </div>

          {/* Layers */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider" style={{ borderTop: '0.5px solid var(--separator)' }}>Couches</div>
          {LAYER_TOGGLES.map((l, i) => (
            <div key={l.id} className={`flex items-center justify-between px-4 py-2 glass-list-row`}>
              <span className="text-[14px] text-[#1c1c1e]">{l.name}</span>
              <div className={`w-[44px] h-[26px] rounded-full transition-colors relative cursor-pointer ${layers[l.id] ? 'bg-[#34c759]' : 'bg-[#e5e5ea]'}`}
                onClick={() => toggleLayer(l.id)}>
                <div className={`absolute top-[2px] w-[22px] h-[22px] bg-white rounded-full shadow transition-transform ${layers[l.id] ? 'translate-x-[20px]' : 'translate-x-[2px]'}`} />
              </div>
            </div>
          ))}

          {/* Map style */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider" style={{ borderTop: '0.5px solid var(--separator)' }}>Carte</div>
          <div className="px-3 pb-2 pt-1 flex rounded-full mx-3 p-0.5" style={{
            background: 'color-mix(in srgb, #007aff 6%, transparent)',
            backdropFilter: 'blur(12px) saturate(150%)',
            WebkitBackdropFilter: 'blur(12px) saturate(150%)',
            boxShadow: 'inset 0 0 0 1px color-mix(in srgb, #007aff 12%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15)',
          }}>
            {(['streets', 'satellite', 'outdoors', 'dark'] as MapStyle[]).map(s => (
              <button key={s} onClick={() => setMapStyle(s)}
                className="flex-1 py-1.5 rounded-full text-[12px] font-bold transition-all duration-200"
                style={mapStyle === s ? {
                  background: '#007aff',
                  color: '#fff',
                  boxShadow: '0 2px 8px rgba(0,122,255,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
                } : { color: '#8e8e93' }}>
                {s === 'streets' ? 'Plan' : s === 'satellite' ? 'Sat' : s === 'outdoors' ? 'Terrain' : 'Sombre'}
              </button>
            ))}
          </div>

          {/* Refresh interval */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider" style={{ borderTop: '0.5px solid var(--separator)' }}>Rafraichissement</div>
          <div className="px-3 pb-2 pt-1 flex rounded-full mx-3 p-0.5" style={{
            background: 'color-mix(in srgb, #007aff 6%, transparent)',
            backdropFilter: 'blur(12px) saturate(150%)',
            WebkitBackdropFilter: 'blur(12px) saturate(150%)',
            boxShadow: 'inset 0 0 0 1px color-mix(in srgb, #007aff 12%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15)',
          }}>
            {[{ label: '30s', value: 30 }, { label: '1 min', value: 60 }, { label: '2 min', value: 120 }, { label: '5 min', value: 300 }].map(opt => (
              <button key={opt.value} onClick={() => setRefreshInterval(opt.value)}
                className="flex-1 py-1.5 rounded-full text-[12px] font-bold transition-all duration-200"
                style={refreshInterval === opt.value ? {
                  background: '#007aff',
                  color: '#fff',
                  boxShadow: '0 2px 8px rgba(0,122,255,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
                } : { color: '#8e8e93' }}>
                {opt.label}
              </button>
            ))}
          </div>

          {/* WindsUp account */}
          {windsupConnected && (
            <div style={{ borderTop: '0.5px solid var(--separator)' }}>
              <div className="flex items-center justify-between px-4 py-2.5">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-[#06b6d4]" style={{ boxShadow: '0 0 6px rgba(6,182,212,0.5)' }} />
                  <span className="text-[13px] font-medium" style={{ color: 'var(--text-primary)' }}>WindsUp connecte</span>
                </div>
                <button
                  onClick={() => {
                    localStorage.removeItem('windsupToken')
                    setWindsupConnected(false)
                    if (enabledSources.includes('windsup')) toggleSource('windsup')
                  }}
                  className="text-[12px] font-bold px-2.5 py-1 rounded-full glass-action-btn"
                  style={{
                    color: '#ff3b30',
                    background: 'color-mix(in srgb, #ff3b30 8%, transparent)',
                    boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #ff3b30 20%, transparent), inset 0 1px 0 rgba(255,255,255,0.1)',
                  }}
                >
                  Deconnecter
                </button>
              </div>
            </div>
          )}

          {/* Dashboard link */}
          <div style={{ borderTop: '0.5px solid var(--separator)' }}>
            <a href="/dashboard"
              className="flex items-center gap-2.5 px-4 py-3 glass-list-row transition" style={{ borderBottom: 'none' }}>
              <div className="w-7 h-7 rounded-xl flex items-center justify-center" style={{
                background: 'color-mix(in srgb, #007aff 10%, transparent)',
                backdropFilter: 'blur(8px)',
                WebkitBackdropFilter: 'blur(8px)',
                boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #007aff 15%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)',
              }}>
                <svg className="w-4 h-4 text-[#007aff]" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="4" rx="1.5" /><rect x="14" y="10" width="7" height="11" rx="1.5" /><rect x="3" y="13" width="7" height="8" rx="1.5" /></svg>
              </div>
              <div>
                <div className="text-[14px] font-semibold text-[#1c1c1e]">Dashboard TV</div>
                <div className="text-[11px] text-[#8e8e93]">Ecran personnalise pour shop</div>
              </div>
              <svg className="w-4 h-4 text-[#c7c7cc] ml-auto" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
            </a>
          </div>

          {/* Embed link */}
          <div>
            <a href="/embed/config"
              className="flex items-center gap-2.5 px-4 py-3 glass-list-row transition" style={{ borderBottom: 'none' }}>
              <div className="w-7 h-7 rounded-xl flex items-center justify-center" style={{
                background: 'color-mix(in srgb, #af52de 10%, transparent)',
                backdropFilter: 'blur(8px)',
                WebkitBackdropFilter: 'blur(8px)',
                boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #af52de 15%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)',
              }}>
                <svg className="w-4 h-4 text-[#af52de]" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" /></svg>
              </div>
              <div>
                <div className="text-[14px] font-semibold text-[#1c1c1e]">Widget Embed</div>
                <div className="text-[11px] text-[#8e8e93]">Integrer un widget sur votre site</div>
              </div>
              <svg className="w-4 h-4 text-[#c7c7cc] ml-auto" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
            </a>
          </div>
        </div>
      )}

      {/* === RADAR CONTROLS === */}
      {radarEnabled && (
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-10 rounded-full px-4 py-2.5 flex items-center gap-3" style={{
          background: 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
          backdropFilter: 'blur(24px) saturate(160%)',
          WebkitBackdropFilter: 'blur(24px) saturate(160%)',
          boxShadow: 'inset 0 0 0 1px color-mix(in srgb, var(--text-primary) 8%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15), 0 4px 16px rgba(0,0,0,0.1)',
        }}>
          <button onClick={togglePlay}
            className="w-8 h-8 rounded-full text-white flex items-center justify-center transition-all duration-200"
            style={{
              background: '#007aff',
              boxShadow: '0 2px 8px rgba(0,122,255,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
            }}>
            {radarPlaying
              ? <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" /></svg>
              : <svg className="w-3.5 h-3.5 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
            }
          </button>
          <input type="range" min={0} max={Math.max(0, totalFrames - 1)} value={radarFrameIndex}
            onChange={e => setRadarFrameIndex(Number(e.target.value))}
            className="w-28 accent-[#007aff]"
          />
          <span className="text-[13px] font-bold text-[#1c1c1e] tabular-nums min-w-[60px]">{radarTimeLabel}</span>
        </div>
      )}

      {/* === WIND OVERLAY === */}
      {mapInstance && layers.windAnimation && (
        <WindOverlay map={mapInstance} visible={layers.windAnimation} forecastHour={windForecastHour} onWindGLChange={setWindGLInstance} onWindDataChange={setWindData} />
      )}
      {layers.windAnimation && (
        <>
          <WindTimeline forecastHour={windForecastHour} onChange={setWindForecastHour} />
          <WindLegend />
          <WindTuner windGL={windGLInstance} map={mapInstance} />
          {mapInstance && <WindTooltip map={mapInstance} windGL={windGLInstance} visible={layers.windAnimation} />}
          {mapInstance && (
            <IsobarOverlay map={mapInstance} windData={windData} visible={showIsobars && layers.windAnimation} forecastHour={windForecastHour} />
          )}
          {/* Isobar toggle */}
          <button
            onClick={() => setShowIsobars(prev => !prev)}
            className="absolute top-16 right-14 z-10 flex items-center gap-1.5 px-2.5 py-1.5 rounded-xl transition-all"
            style={{
              background: showIsobars
                ? 'color-mix(in srgb, #6366f1 15%, transparent)'
                : 'color-mix(in srgb, var(--text-primary) 6%, transparent)',
              backdropFilter: 'blur(20px) saturate(1.6)',
              WebkitBackdropFilter: 'blur(20px) saturate(1.6)',
              boxShadow: showIsobars
                ? 'inset 0 0 0 1px color-mix(in srgb, #6366f1 30%, transparent), 0 2px 8px rgba(99,102,241,0.2)'
                : 'inset 0 0 0 0.5px rgba(255,255,255,0.3), 0 1px 4px rgba(0,0,0,0.08)',
              color: showIsobars ? '#6366f1' : 'var(--text-tertiary)',
            }}
            title="Isobares de pression"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.8" viewBox="0 0 24 24" strokeLinecap="round">
              <path d="M3 8c3-2 6 2 9 0s6-2 9 0" />
              <path d="M3 14c3-2 6 2 9 0s6-2 9 0" />
              <path d="M3 20c3-2 6 2 9 0s6-2 9 0" />
            </svg>
            <span className="text-[11px] font-bold">hPa</span>
          </button>
        </>
      )}


      {/* === FLOATING POPUP === */}
      {popupData && mapInstance && (
        <MapPopup map={mapInstance} lngLat={popupData.lngLat} onClose={closePopup} expanded={popupExpanded} anchorBottom={popupData.type === 'webcam'} markerHeight={76}>
          {popupData.type === 'station' && <StationPopupContent station={popupData.data as WindStation} expanded={popupExpanded} onExpand={handleToggleExpand} onForecast={(lat, lon, name) => { closePopup(); setForecastTarget({ lat, lon, name }) }} />}
          {popupData.type === 'buoy' && <BuoyPopupContent buoy={popupData.data as WaveBuoy} expanded={popupExpanded} onExpand={handleToggleExpand} onForecast={(lat, lon, name) => { closePopup(); setForecastTarget({ lat, lon, name }) }} />}
          {popupData.type === 'webcam' && <WebcamPopupContent webcam={popupData.data as Webcam} expanded={popupExpanded} onExpand={handleToggleExpand} onForecast={(lat, lon, name) => { closePopup(); setForecastTarget({ lat, lon, name }) }} />}
          {popupData.type === 'spot' && <SpotPopupContent spot={popupData.data as Spot} expanded={popupExpanded} onExpand={handleToggleExpand} onForecast={(lat, lon, name) => { closePopup(); setForecastTarget({ lat, lon, name }) }} />}
          {popupData.type === 'tide' && <TidePopupContent port={popupData.data as TidePort} expanded={popupExpanded} onExpand={handleToggleExpand} />}
        </MapPopup>
      )}

      {/* WindsUp Login Modal */}
      {showWindsUpLogin && (
        <WindsUpLogin
          onClose={() => setShowWindsUpLogin(false)}
          onSuccess={() => {
            setShowWindsUpLogin(false)
            setWindsupConnected(true)
            // Enable windsup source if not already
            if (!enabledSources.includes('windsup')) toggleSource('windsup')
          }}
        />
      )}

      {/* Forecast Panel (Windguru-style) */}
      {forecastTarget && (
        <ForecastPanel
          lat={forecastTarget.lat}
          lon={forecastTarget.lon}
          name={forecastTarget.name}
          onClose={() => setForecastTarget(null)}
        />
      )}
    </div>
  )
}
