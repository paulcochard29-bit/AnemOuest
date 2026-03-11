'use client'

import { useState, useCallback, useMemo, useEffect, useRef } from 'react'
import dynamic from 'next/dynamic'
import type mapboxgl from 'mapbox-gl'
import { useAppStore } from '@/store/appStore'
import type { WindStation, WaveBuoy, Webcam, Spot, MapStyle } from '@/store/appStore'
import { ALL_SOURCES, LAYER_TOGGLES } from '@/store/appStore'
import { useStations, useBuoys, useWebcams, useSpots, useRadar } from '@/hooks'
import { MapPopup } from '@/components/MapPopup'
import { StationPopupContent } from '@/components/popups/StationPopupContent'
import { BuoyPopupContent } from '@/components/popups/BuoyPopupContent'
import { WebcamPopupContent } from '@/components/popups/WebcamPopupContent'
import { SpotPopupContent } from '@/components/popups/SpotPopupContent'

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

  const refreshInterval = useAppStore(s => s.refreshInterval)
  const setRefreshInterval = useAppStore(s => s.setRefreshInterval)

  const { radarEnabled, radarTileUrl, radarTimeLabel, radarPlaying, radarFrameIndex, totalFrames, toggleRadar, togglePlay, setRadarFrameIndex } = useRadar()

  const [popupData, setPopupData] = useState<{
    type: 'station' | 'buoy' | 'webcam' | 'spot'
    data: WindStation | WaveBuoy | Webcam | Spot
    lngLat: [number, number]
  } | null>(null)
  const [popupExpanded, setPopupExpanded] = useState(false)
  const [flyTo, setFlyTo] = useState<{ lon: number; lat: number; zoom?: number } | null>(null)
  const [showLayers, setShowLayers] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [showSearch, setShowSearch] = useState(false)
  const geolocatedRef = useRef(false)

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

  const popupId = popupData ? (popupData.data as any).id : null

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

  // "Voir plus" / "Réduire" toggles expansion within the popup
  const handleToggleExpand = useCallback(() => {
    setPopupExpanded(prev => !prev)
  }, [])

  const searchResults = useMemo(() => {
    if (!searchQuery.trim()) return []
    const q = searchQuery.toLowerCase()
    const r: { id: string; name: string; type: string; action: () => void }[] = []
    stations.filter(s => s.isOnline && s.name.toLowerCase().includes(q)).slice(0, 5).forEach(s => r.push({ id: s.id, name: s.name, type: 'Station', action: () => handleStationClick(s) }))
    buoys.filter(b => b.name.toLowerCase().includes(q)).slice(0, 3).forEach(b => r.push({ id: b.id, name: b.name, type: 'Bouee', action: () => handleBuoyClick(b) }))
    webcams.filter(w => (w.name + w.location).toLowerCase().includes(q)).slice(0, 3).forEach(w => r.push({ id: w.id, name: w.name, type: 'Webcam', action: () => handleWebcamClick(w) }))
    spots.filter(s => s.name.toLowerCase().includes(q)).slice(0, 5).forEach(s => {
      const label = s.spotType === 'kite' ? 'Spot kite' : s.spotType === 'surf' ? 'Spot surf' : 'Parapente'
      r.push({ id: s.id, name: s.name, type: label, action: () => handleSpotClick(s) })
    })
    return r
  }, [searchQuery, stations, buoys, webcams, spots, handleStationClick, handleBuoyClick, handleWebcamClick, handleSpotClick])

  const onlineCount = stations.filter(s => s.isOnline).length

  return (
    <div className="fixed inset-0 overflow-hidden">
      <MapView
        stations={stations.filter(s => enabledSources.includes(s.source))}
        buoys={buoys} webcams={webcams} spots={spots} spotScores={spotScores}
        mapStyle={mapStyle} layers={layers} selectedId={popupId}
        radarTileUrl={radarTileUrl} flyTo={flyTo}
        onStationClick={handleStationClick} onBuoyClick={handleBuoyClick}
        onWebcamClick={handleWebcamClick} onSpotClick={handleSpotClick}
        onMapReady={setMapInstance} onMapClick={closePopup}
        mapboxToken={MAPBOX_TOKEN}
      />

      {/* === TOP: Search bar === */}
      <div className="absolute top-2.5 left-2.5 right-14 z-10 flex gap-2">
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
                  className="w-full flex items-center justify-between px-4 py-2.5 hover:bg-white/30 text-left border-b border-white/20 last:border-0"
                  onClick={() => { r.action(); setSearchQuery(''); setShowSearch(false) }}
                >
                  <span className="text-[15px] text-[#1c1c1e] truncate">{r.name}</span>
                  <span className="text-[13px] text-[#8e8e93] ml-2 flex-shrink-0">{r.type}</span>
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

      {/* === RIGHT TOP TOOLBAR (settings + radar) === */}
      <div className="absolute right-2.5 top-2.5 z-10 flex flex-col glass-bar rounded-2xl overflow-hidden">
        <button onClick={() => setShowLayers(!showLayers)}
          className={`w-10 h-10 flex items-center justify-center border-b border-white/20 ${showLayers ? 'text-[#007aff]' : 'text-[#3c3c43]/60'}`}>
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75" /></svg>
        </button>
        <button onClick={toggleRadar}
          className={`w-10 h-10 flex items-center justify-center border-b border-white/20 ${radarEnabled ? 'text-[#007aff]' : 'text-[#3c3c43]/60'}`}>
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15a4.5 4.5 0 004.5 4.5H18a3.75 3.75 0 001.332-7.257 3 3 0 00-3.758-3.848 5.25 5.25 0 00-10.233 2.33A4.502 4.502 0 002.25 15z" /></svg>
        </button>
        <button onClick={handleGeolocate}
          className="w-10 h-10 flex items-center justify-center text-[#3c3c43]/60 hover:text-[#007aff] transition">
          <svg className="w-[22px] h-[22px]" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z" /><path strokeLinecap="round" strokeLinejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z" /></svg>
        </button>
      </div>

      {/* === RIGHT CENTER: Layer toggles === */}
      <div className="absolute right-2.5 top-1/2 -translate-y-1/2 z-10 flex flex-col glass-bar rounded-2xl overflow-hidden">
        {LAYER_TOGGLES.map((l, i) => (
          <button key={l.id} onClick={() => toggleLayer(l.id)}
            className={`w-10 h-10 flex items-center justify-center ${i < LAYER_TOGGLES.length - 1 ? 'border-b border-white/20' : ''} ${layers[l.id] ? 'text-[#007aff]' : 'text-[#3c3c43]/60'}`}
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
              return (
                <button key={s.id} onClick={() => toggleSource(s.id)}
                  className="px-2.5 py-1 rounded-full text-[12px] font-semibold transition flex-shrink-0"
                  style={{
                    background: active ? s.color : '#f2f2f7',
                    color: active ? '#fff' : '#8e8e93',
                  }}>
                  {s.name}
                </button>
              )
            })}
          </div>

          {/* Layers */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider border-t border-[#e5e5ea]">Couches</div>
          {LAYER_TOGGLES.map((l, i) => (
            <div key={l.id} className={`flex items-center justify-between px-4 py-2 ${i < LAYER_TOGGLES.length - 1 ? 'border-b border-[#f2f2f7]' : ''}`}>
              <span className="text-[14px] text-[#1c1c1e]">{l.name}</span>
              <div className={`w-[44px] h-[26px] rounded-full transition-colors relative cursor-pointer ${layers[l.id] ? 'bg-[#34c759]' : 'bg-[#e5e5ea]'}`}
                onClick={() => toggleLayer(l.id)}>
                <div className={`absolute top-[2px] w-[22px] h-[22px] bg-white rounded-full shadow transition-transform ${layers[l.id] ? 'translate-x-[20px]' : 'translate-x-[2px]'}`} />
              </div>
            </div>
          ))}

          {/* Map style */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider border-t border-[#e5e5ea]">Carte</div>
          <div className="px-3 pb-2 pt-1 flex gap-1.5">
            {(['streets', 'satellite', 'outdoors', 'dark'] as MapStyle[]).map(s => (
              <button key={s} onClick={() => setMapStyle(s)}
                className={`flex-1 py-1.5 rounded-lg text-[12px] font-semibold transition ${mapStyle === s ? 'bg-[#007aff] text-white' : 'bg-[#f2f2f7] text-[#8e8e93]'}`}>
                {s === 'streets' ? 'Plan' : s === 'satellite' ? 'Sat' : s === 'outdoors' ? 'Terrain' : 'Sombre'}
              </button>
            ))}
          </div>

          {/* Refresh interval */}
          <div className="px-4 pt-2 pb-1 text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider border-t border-[#e5e5ea]">Rafraichissement</div>
          <div className="px-3 pb-2 pt-1 flex gap-1.5">
            {[{ label: '30s', value: 30 }, { label: '1 min', value: 60 }, { label: '2 min', value: 120 }, { label: '5 min', value: 300 }].map(opt => (
              <button key={opt.value} onClick={() => setRefreshInterval(opt.value)}
                className={`flex-1 py-1.5 rounded-lg text-[12px] font-semibold transition ${refreshInterval === opt.value ? 'bg-[#007aff] text-white' : 'bg-[#f2f2f7] text-[#8e8e93]'}`}>
                {opt.label}
              </button>
            ))}
          </div>

          {/* Dashboard link */}
          <div className="border-t border-[#e5e5ea]">
            <a href="/dashboard"
              className="flex items-center gap-2.5 px-4 py-3 hover:bg-[#f2f2f7] transition">
              <div className="w-7 h-7 rounded-lg bg-[#007aff]/10 flex items-center justify-center">
                <svg className="w-4 h-4 text-[#007aff]" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="4" rx="1.5" /><rect x="14" y="10" width="7" height="11" rx="1.5" /><rect x="3" y="13" width="7" height="8" rx="1.5" /></svg>
              </div>
              <div>
                <div className="text-[14px] font-semibold text-[#1c1c1e]">Dashboard TV</div>
                <div className="text-[11px] text-[#8e8e93]">Ecran personnalise pour shop</div>
              </div>
              <svg className="w-4 h-4 text-[#c7c7cc] ml-auto" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
            </a>
          </div>
        </div>
      )}

      {/* === RADAR CONTROLS === */}
      {radarEnabled && (
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-10 bg-white rounded-xl px-4 py-2.5 flex items-center gap-3" style={{ boxShadow: '0 2px 16px rgba(0,0,0,0.12)' }}>
          <button onClick={togglePlay} className="w-8 h-8 rounded-full bg-[#007aff] text-white flex items-center justify-center">
            {radarPlaying
              ? <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" /></svg>
              : <svg className="w-3.5 h-3.5 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
            }
          </button>
          <input type="range" min={0} max={Math.max(0, totalFrames - 1)} value={radarFrameIndex}
            onChange={e => setRadarFrameIndex(Number(e.target.value))}
            className="w-28 accent-[#007aff]"
          />
          <span className="text-[13px] font-medium text-[#1c1c1e] tabular-nums min-w-[60px]">{radarTimeLabel}</span>
        </div>
      )}

      {/* === FLOATING POPUP === */}
      {popupData && mapInstance && (
        <MapPopup map={mapInstance} lngLat={popupData.lngLat} onClose={closePopup} expanded={popupExpanded} anchorBottom={popupData.type === 'webcam'} markerHeight={76}>
          {popupData.type === 'station' && <StationPopupContent station={popupData.data as WindStation} expanded={popupExpanded} onExpand={handleToggleExpand} />}
          {popupData.type === 'buoy' && <BuoyPopupContent buoy={popupData.data as WaveBuoy} expanded={popupExpanded} onExpand={handleToggleExpand} />}
          {popupData.type === 'webcam' && <WebcamPopupContent webcam={popupData.data as Webcam} expanded={popupExpanded} onExpand={handleToggleExpand} />}
          {popupData.type === 'spot' && <SpotPopupContent spot={popupData.data as Spot} expanded={popupExpanded} onExpand={handleToggleExpand} />}
        </MapPopup>
      )}
    </div>
  )
}
