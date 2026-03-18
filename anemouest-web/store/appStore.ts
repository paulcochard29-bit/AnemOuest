import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { TabId, FavoriteSpot, AlertConfig, RadarFrame } from '@/lib/types'

// ===== Map Types =====

export interface WindStation {
  id: string
  stableId: string
  name: string
  lat: number
  lon: number
  wind: number
  gust: number
  direction: number
  isOnline: boolean
  source: string
  altitude?: number
  pressure?: number
  temperature?: number
  humidity?: number
  ts?: string
}

export interface WaveBuoy {
  id: string
  name: string
  lat: number
  lon: number
  hm0: number
  hmax: number
  tp: number
  direction: number
  seaTemp: number
  status: string
  depth?: number
  region?: string
  spread?: number
  lastUpdate?: string
}

export interface Webcam {
  id: string
  name: string
  location: string
  latitude: number
  longitude: number
  imageUrl: string
  source: string
  region?: string
  refreshInterval?: number
  streamUrl?: string
  lastCapture?: number | null
}

export interface Spot {
  id: string
  name: string
  lat: number
  lon: number
  spotType: 'kite' | 'surf' | 'paragliding'
  level?: string | null
  orientation?: string[]
  altitude?: number
  description?: string
  surfType?: string
  kiteType?: string
}

export type MapStyle = 'satellite' | 'streets' | 'outdoors' | 'dark'

export interface TidePort {
  cst: string
  name: string
  lat: number
  lon: number
  region: string
}

export interface LayerVisibility {
  buoys: boolean
  webcams: boolean
  kiteSpots: boolean
  surfSpots: boolean
  paraglidingSpots: boolean
  tides: boolean
  windAnimation: boolean
}

export type SpotScoreColor = '#22c55e' | '#f59e0b' | '#ef4444' | '#6b7280'

// ===== Source Config =====

export interface SourceConfig {
  id: string
  name: string
  count: string
  color: string
}

export const ALL_SOURCES: SourceConfig[] = [
  { id: 'meteofrance', name: 'Météo France', count: '~90', color: '#3b82f6' },
  { id: 'gowind', name: 'Holfuy/Windguru', count: '~2900', color: '#22c55e' },
  { id: 'pioupiou', name: 'Pioupiou', count: '~800', color: '#f97316' },
  { id: 'netatmo', name: 'Netatmo', count: '~3000', color: '#f43f5e' },
  { id: 'ffvl', name: 'FFVL', count: '~200', color: '#eab308' },
  { id: 'windcornouaille', name: 'WindCornouaille', count: '14', color: '#6366f1' },
  { id: 'ndbc', name: 'NDBC', count: '7', color: '#0ea5e9' },
  { id: 'diabox', name: 'Diabox', count: '9', color: '#ec4899' },
  { id: 'windsup', name: 'WindsUp', count: '~150', color: '#06b6d4' },
]

export const SOURCE_COLORS: Record<string, string> = {
  pioupiou: '#f97316',
  ffvl: '#eab308',
  holfuy: '#22c55e',
  gowind: '#22c55e',
  windguru: '#a855f7',
  windcornouaille: '#6366f1',
  meteofrance: '#3b82f6',
  diabox: '#ec4899',
  windsup: '#06b6d4',
  netatmo: '#f43f5e',
  ndbc: '#0ea5e9',
}

export const LAYER_TOGGLES: { id: keyof LayerVisibility; name: string; color: string; count: string }[] = [
  { id: 'buoys', name: 'Bouées houle', color: 'bg-cyan-500', count: '22' },
  { id: 'webcams', name: 'Webcams', color: 'bg-purple-500', count: '248' },
  { id: 'kiteSpots', name: 'Spots kite', color: 'bg-green-500', count: '425' },
  { id: 'surfSpots', name: 'Spots surf', color: 'bg-blue-500', count: '67' },
  { id: 'paraglidingSpots', name: 'Spots parapente', color: 'bg-orange-500', count: '400+' },
  { id: 'tides', name: 'Marées', color: 'bg-teal-500', count: '35' },
  { id: 'windAnimation', name: 'Vent animé', color: 'bg-sky-500', count: '' },
]

// ===== Store State =====

interface MapSlice {
  stations: WindStation[]
  buoys: WaveBuoy[]
  webcams: Webcam[]
  spots: Spot[]
  spotScores: Record<string, SpotScoreColor>
  selectedStation: WindStation | null
  selectedBuoy: WaveBuoy | null
  selectedWebcam: Webcam | null
  selectedSpot: Spot | null
  selectedTidePort: TidePort | null
  mapStyle: MapStyle
  layers: LayerVisibility
  enabledSources: string[]
  mapCenter: [number, number]
  mapZoom: number
  setStations: (stations: WindStation[]) => void
  setBuoys: (buoys: WaveBuoy[]) => void
  setWebcams: (webcams: Webcam[]) => void
  setSpots: (spots: Spot[]) => void
  setSpotScores: (scores: Record<string, SpotScoreColor>) => void
  selectStation: (station: WindStation | null) => void
  selectBuoy: (buoy: WaveBuoy | null) => void
  selectWebcam: (webcam: Webcam | null) => void
  selectSpot: (spot: Spot | null) => void
  selectTidePort: (port: TidePort | null) => void
  setMapStyle: (style: MapStyle) => void
  windForecastHour: number
  setWindForecastHour: (hour: number) => void
  toggleLayer: (layer: keyof LayerVisibility) => void
  toggleSource: (source: string) => void
  setMapView: (center: [number, number], zoom: number) => void
}

interface UISlice {
  activeTab: TabId
  showSearch: boolean
  showSettings: boolean
  showSourceFilter: boolean
  showLayerFilter: boolean
  showShare: boolean
  showForecastComparison: boolean
  isLoading: boolean
  setActiveTab: (tab: TabId) => void
  setShowSearch: (show: boolean) => void
  setShowSettings: (show: boolean) => void
  setShowSourceFilter: (show: boolean) => void
  setShowLayerFilter: (show: boolean) => void
  setShowShare: (show: boolean) => void
  setShowForecastComparison: (show: boolean) => void
  setIsLoading: (loading: boolean) => void
  closeAllPanels: () => void
}

interface FavoritesSlice {
  favorites: FavoriteSpot[]
  addFavorite: (spot: FavoriteSpot) => void
  removeFavorite: (id: string) => void
  updateAlert: (id: string, alert: AlertConfig) => void
  isFavorite: (id: string) => boolean
}

interface SettingsSlice {
  refreshInterval: number
  windUnit: 'knots' | 'ms' | 'kmh'
  isDarkMode: boolean
  preWindMapStyle: MapStyle | null
  setRefreshInterval: (interval: number) => void
  setWindUnit: (unit: 'knots' | 'ms' | 'kmh') => void
  toggleDarkMode: () => void
  setPreWindMapStyle: (style: MapStyle | null) => void
}

export interface Toast {
  id: string
  message: string
  type: 'error' | 'warning' | 'info' | 'success'
  action?: { label: string; onClick: () => void }
}

interface ToastSlice {
  toasts: Toast[]
  addToast: (toast: Omit<Toast, 'id'>) => void
  removeToast: (id: string) => void
}

export type AppStore = MapSlice & UISlice & FavoritesSlice & SettingsSlice & ToastSlice

export const useAppStore = create<AppStore>()(
  persist(
    (set, get) => ({
      // ===== Map Slice =====
      stations: [],
      buoys: [],
      webcams: [],
      spots: [],
      spotScores: {},
      selectedStation: null,
      selectedBuoy: null,
      selectedWebcam: null,
      selectedSpot: null,
      selectedTidePort: null,
      mapStyle: 'streets' as MapStyle,
      layers: {
        buoys: true,
        webcams: true,
        kiteSpots: false,
        surfSpots: false,
        paraglidingSpots: false,
        tides: true,
        windAnimation: false,
      },
      windForecastHour: 0,
      setWindForecastHour: (hour) => set({ windForecastHour: hour }),
      enabledSources: ALL_SOURCES.map(s => s.id),
      mapCenter: [-3.5, 47.5] as [number, number],
      mapZoom: 7,

      setStations: (stations) => set({ stations }),
      setBuoys: (buoys) => set({ buoys }),
      setWebcams: (webcams) => set({ webcams }),
      setSpots: (spots) => set({ spots }),
      setSpotScores: (spotScores) => set({ spotScores }),
      selectStation: (station) => set({ selectedStation: station, selectedBuoy: null, selectedWebcam: null, selectedSpot: null, selectedTidePort: null }),
      selectBuoy: (buoy) => set({ selectedBuoy: buoy, selectedStation: null, selectedWebcam: null, selectedSpot: null, selectedTidePort: null }),
      selectWebcam: (webcam) => set({ selectedWebcam: webcam, selectedStation: null, selectedBuoy: null, selectedSpot: null, selectedTidePort: null }),
      selectSpot: (spot) => set({ selectedSpot: spot, selectedStation: null, selectedBuoy: null, selectedWebcam: null, selectedTidePort: null }),
      selectTidePort: (port) => set({ selectedTidePort: port, selectedStation: null, selectedBuoy: null, selectedWebcam: null, selectedSpot: null }),
      setMapStyle: (style) => set({ mapStyle: style }),
      toggleLayer: (layer) => set((state) => ({
        layers: { ...state.layers, [layer]: !state.layers[layer] }
      })),
      toggleSource: (source) => set((state) => {
        const enabled = state.enabledSources.includes(source)
        return {
          enabledSources: enabled
            ? state.enabledSources.filter(s => s !== source)
            : [...state.enabledSources, source]
        }
      }),
      setMapView: (center, zoom) => set({ mapCenter: center, mapZoom: zoom }),

      // ===== UI Slice =====
      activeTab: 'map' as TabId,
      showSearch: false,
      showSettings: false,
      showSourceFilter: false,
      showLayerFilter: false,
      showShare: false,
      showForecastComparison: false,
      isLoading: true,

      setActiveTab: (tab) => set({ activeTab: tab }),
      setShowSearch: (show) => set({ showSearch: show }),
      setShowSettings: (show) => set({ showSettings: show }),
      setShowSourceFilter: (show) => set({ showSourceFilter: show }),
      setShowLayerFilter: (show) => set({ showLayerFilter: show }),
      setShowShare: (show) => set({ showShare: show }),
      setShowForecastComparison: (show) => set({ showForecastComparison: show }),
      setIsLoading: (loading) => set({ isLoading: loading }),
      closeAllPanels: () => set({
        selectedStation: null,
        selectedBuoy: null,
        selectedWebcam: null,
        selectedSpot: null,
        selectedTidePort: null,
        showSearch: false,
        showSettings: false,
        showSourceFilter: false,
        showLayerFilter: false,
        showShare: false,
        showForecastComparison: false,
      }),

      // ===== Favorites Slice =====
      favorites: [],
      addFavorite: (spot) => set((state) => ({
        favorites: [...state.favorites, spot]
      })),
      removeFavorite: (id) => set((state) => ({
        favorites: state.favorites.filter(f => f.id !== id)
      })),
      updateAlert: (id, alert) => set((state) => ({
        favorites: state.favorites.map(f =>
          f.id === id ? { ...f, alert } : f
        )
      })),
      isFavorite: (id) => get().favorites.some(f => f.id === id),

      // ===== Settings Slice =====
      refreshInterval: 60,
      windUnit: 'knots' as const,
      isDarkMode: false,
      preWindMapStyle: null,
      setRefreshInterval: (interval) => set({ refreshInterval: interval }),
      setWindUnit: (unit) => set({ windUnit: unit }),
      toggleDarkMode: () => set((state) => ({ isDarkMode: !state.isDarkMode })),
      setPreWindMapStyle: (style) => set({ preWindMapStyle: style }),

      // ===== Toast Slice =====
      toasts: [],
      addToast: (toast) => set((state) => ({
        toasts: [...state.toasts, { ...toast, id: `${Date.now()}-${Math.random().toString(36).slice(2)}` }]
      })),
      removeToast: (id) => set((state) => ({
        toasts: state.toasts.filter(t => t.id !== id)
      })),
    }),
    {
      name: 'anemouest-store',
      partialize: (state) => ({
        favorites: state.favorites,
        mapStyle: state.mapStyle,
        layers: state.layers,
        enabledSources: state.enabledSources,
        refreshInterval: state.refreshInterval,
        windUnit: state.windUnit,
        isDarkMode: state.isDarkMode,
      }),
      merge: (persisted, current) => {
        const p = persisted as Partial<AppStore> | undefined
        const merged = { ...current, ...p }
        // Deep-merge layers so new keys get defaults
        merged.layers = { ...current.layers, ...(p?.layers || {}) }
        return merged as AppStore
      },
    }
  )
)
