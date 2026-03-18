'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { useSearchParams } from 'next/navigation'
import { Suspense } from 'react'
import { WindChart } from '@/components/WindChart'
import { API as API_BASE, apiFetch } from '@/lib/api'

// Wind color scale (same as main app)
function getWindColor(knots: number): string {
  if (knots < 7) return '#B3EDFF'
  if (knots < 11) return '#54D9EB'
  if (knots < 17) return '#59E385'
  if (knots < 22) return '#F8E654'
  if (knots < 28) return '#FAAB3A'
  if (knots < 34) return '#F23842'
  if (knots < 41) return '#D433AB'
  if (knots < 48) return '#8C3EC8'
  return '#6440A0'
}

function getDirectionText(degrees: number): string {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO']
  return directions[Math.round(degrees / 45) % 8]
}

interface Station {
  id: string
  stableId?: string
  name: string
  wind: number
  gust: number
  direction: number
  isOnline: boolean
  source: string
}

// Main display content (wrapped in Suspense for useSearchParams)
function DisplayContent() {
  const searchParams = useSearchParams()

  // URL params: ?stations=6,7,10&source=windcornouaille&cols=3&chart=true&hours=6&title=Mon+Shop
  const stationIds = useMemo(() => searchParams.get('stations')?.split(',').map(s => s.trim()) || [], [searchParams])
  const source = searchParams.get('source') || 'windcornouaille'
  const cols = parseInt(searchParams.get('cols') || '0') || 0 // 0 = auto
  const showChart = searchParams.get('chart') !== 'false'
  const chartHours = parseInt(searchParams.get('hours') || '6')
  const customTitle = searchParams.get('title')
  const refreshInterval = parseInt(searchParams.get('refresh') || '30') * 1000

  const [stations, setStations] = useState<Station[]>([])
  const [allStations, setAllStations] = useState<Station[]>([])
  const [loading, setLoading] = useState(true)
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date())
  const [showConfig, setShowConfig] = useState(false)

  // Fetch all stations from the source
  const fetchStations = useCallback(async () => {
    try {
      const sources = source.includes(',') ? source.split(',') : [source]
      const all: Station[] = []

      await Promise.all(sources.map(async (src) => {
        const res = await apiFetch(`${API_BASE}/${src.trim()}`, { cache: 'no-store' })
        if (!res.ok) return
        const data = await res.json()
        const stationList = data.stations || []
        stationList.forEach((s: any) => {
          all.push({
            id: s.id,
            stableId: s.stableId,
            name: s.name,
            wind: s.wind || 0,
            gust: s.gust || 0,
            direction: s.direction || 0,
            isOnline: s.isOnline !== false,
            source: s.source || src.trim(),
          })
        })
      }))

      setAllStations(all)

      // Filter to requested stations if specified
      if (stationIds.length > 0) {
        const filtered = stationIds
          .map(id => all.find(s => s.id === id || s.stableId === id))
          .filter((s): s is Station => s !== undefined)
        setStations(filtered)
      } else {
        // No stations specified: show all online stations sorted by wind
        setStations(all.filter(s => s.isOnline).sort((a, b) => b.wind - a.wind).slice(0, 12))
      }

      setLastUpdate(new Date())
    } catch (err) {
      console.error('Fetch error:', err)
    } finally {
      setLoading(false)
    }
  }, [source, stationIds])

  // Auto-refresh
  useEffect(() => {
    fetchStations()
    const interval = setInterval(fetchStations, refreshInterval)
    return () => clearInterval(interval)
  }, [fetchStations, refreshInterval])

  // Auto-calculate grid columns
  const gridCols = cols > 0 ? cols : stations.length <= 1 ? 1 : stations.length <= 2 ? 2 : stations.length <= 4 ? 2 : stations.length <= 6 ? 3 : 4

  // Show configuration helper if no stations param
  if (!loading && stationIds.length === 0 && allStations.length > 0 && !showConfig) {
    setShowConfig(true)
  }

  if (loading && stations.length === 0) {
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <svg className="w-12 h-12 animate-spin text-cyan-400" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4"/>
          </svg>
          <p className="text-gray-400 text-lg">Chargement des stations...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white p-4 sm:p-6 lg:p-8 flex flex-col">
      {/* Header */}
      <header className="flex items-center justify-between mb-6 flex-shrink-0">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-3">
            <svg className="w-8 h-8 text-cyan-400" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" opacity="0"/>
              <path d="M14.5 17c0 1.65-1.35 3-3 3s-3-1.35-3-3h2c0 .55.45 1 1 1s1-.45 1-1-.45-1-1-1H2v-2h9.5c1.65 0 3 1.35 3 3zM19 6.5C19 4.57 17.43 3 15.5 3S12 4.57 12 6.5h2c0-.83.67-1.5 1.5-1.5s1.5.67 1.5 1.5S16.33 8 15.5 8H2v2h13.5C17.43 10 19 8.43 19 6.5zM18.5 11H2v2h16.5c.83 0 1.5.67 1.5 1.5s-.67 1.5-1.5 1.5v2c1.93 0 3.5-1.57 3.5-3.5S20.43 11 18.5 11z"/>
            </svg>
            <h1 className="text-2xl font-bold tracking-tight">
              {customTitle || 'Le Vent'}
            </h1>
          </div>
          {customTitle && (
            <span className="text-sm text-gray-500 font-medium">Le Vent</span>
          )}
        </div>

        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2 text-sm text-gray-500">
            <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
            <span className="tabular-nums">
              {lastUpdate.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
            </span>
          </div>
        </div>
      </header>

      {/* Configuration helper */}
      {showConfig && stationIds.length === 0 && (
        <div className="mb-6 p-5 rounded-2xl bg-gray-800/50 border border-gray-700/50 flex-shrink-0">
          <div className="flex items-start justify-between">
            <div>
              <h2 className="font-semibold text-lg mb-2">Configuration</h2>
              <p className="text-gray-400 text-sm mb-3">
                Ajoutez les IDs des stations dans l&apos;URL pour personnaliser l&apos;affichage :
              </p>
              <code className="text-xs bg-gray-900 px-3 py-2 rounded-lg text-cyan-400 block mb-3">
                /display?stations=6,7,10&source=windcornouaille&title=Mon+Spot
              </code>
              <div className="text-xs text-gray-500 space-y-1">
                <p><strong>stations</strong> : IDs des stations (separes par virgules)</p>
                <p><strong>source</strong> : windcornouaille, pioupiou, ffvl, holfuy, gowind, meteofrance</p>
                <p><strong>cols</strong> : nombre de colonnes (auto par defaut)</p>
                <p><strong>chart</strong> : true/false (graphique d&apos;historique)</p>
                <p><strong>hours</strong> : heures d&apos;historique (2, 6, 12, 24)</p>
                <p><strong>title</strong> : titre personnalise</p>
                <p><strong>refresh</strong> : intervalle en secondes (30 par defaut)</p>
              </div>
            </div>
            <button
              onClick={() => setShowConfig(false)}
              className="p-2 rounded-lg text-gray-500 hover:text-white hover:bg-gray-700 transition-colors"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* Available stations list */}
          <details className="mt-4">
            <summary className="text-sm text-cyan-400 cursor-pointer hover:text-cyan-300">
              Stations disponibles ({allStations.length})
            </summary>
            <div className="mt-3 max-h-60 overflow-auto grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
              {allStations
                .filter(s => s.isOnline)
                .sort((a, b) => a.name.localeCompare(b.name))
                .map(s => (
                  <div key={s.id} className="text-xs bg-gray-900 px-3 py-2 rounded-lg flex justify-between items-center">
                    <span className="text-gray-300 truncate">{s.name}</span>
                    <span className="text-gray-600 ml-2 flex-shrink-0">{s.id}</span>
                  </div>
                ))
              }
            </div>
          </details>
        </div>
      )}

      {/* Station cards grid */}
      <div
        className="grid gap-4 sm:gap-6 flex-1"
        style={{
          gridTemplateColumns: `repeat(${gridCols}, minmax(0, 1fr))`,
          gridAutoRows: 'minmax(0, 1fr)',
        }}
      >
        {stations.map((station) => (
          <StationCard
            key={station.id}
            station={station}
            showChart={showChart}
            chartHours={chartHours}
            compact={stations.length > 4}
          />
        ))}
      </div>

      {/* Empty state */}
      {stations.length === 0 && !loading && stationIds.length > 0 && (
        <div className="flex-1 flex items-center justify-center">
          <div className="text-center">
            <svg className="w-16 h-16 text-gray-700 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
            <p className="text-gray-500 text-lg">Aucune station trouvee</p>
            <p className="text-gray-600 text-sm mt-2">Verifiez les IDs : {stationIds.join(', ')}</p>
          </div>
        </div>
      )}
    </div>
  )
}

// Station card component
function StationCard({ station, showChart, chartHours, compact }: {
  station: Station
  showChart: boolean
  chartHours: number
  compact: boolean
}) {
  const windColor = getWindColor(station.wind)
  const gustColor = getWindColor(station.gust)

  return (
    <div className="rounded-2xl bg-gray-900/80 border border-gray-800/50 p-4 sm:p-6 flex flex-col overflow-hidden">
      {/* Station name + status */}
      <div className="flex items-center justify-between mb-4 flex-shrink-0">
        <div className="flex items-center gap-3 min-w-0">
          <h2 className={`font-bold truncate ${compact ? 'text-lg' : 'text-xl lg:text-2xl'}`}>
            {station.name}
          </h2>
          {station.isOnline ? (
            <span className="flex items-center gap-1.5 flex-shrink-0">
              <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
            </span>
          ) : (
            <span className="text-xs text-gray-600 bg-gray-800 px-2 py-0.5 rounded-full flex-shrink-0">
              Hors ligne
            </span>
          )}
        </div>

        {/* Direction indicator */}
        <div className="flex items-center gap-2 flex-shrink-0">
          <div
            className="w-10 h-10 sm:w-12 sm:h-12 rounded-xl bg-gray-800/80 flex items-center justify-center transition-transform"
            style={{ transform: `rotate(${station.direction + 180}deg)` }}
          >
            <svg className="w-5 h-5 sm:w-6 sm:h-6 text-cyan-400" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 2l-5 9h3v11h4V11h3z"/>
            </svg>
          </div>
          <div className="text-center">
            <div className="text-sm sm:text-base font-semibold text-gray-300">
              {getDirectionText(station.direction)}
            </div>
            <div className="text-xs text-gray-600">{Math.round(station.direction)}°</div>
          </div>
        </div>
      </div>

      {/* Wind data - big numbers */}
      <div className="flex items-end gap-3 mb-4 flex-shrink-0">
        <div className="flex items-baseline gap-2">
          <span
            className={`font-bold tabular-nums tracking-tight ${compact ? 'text-5xl' : 'text-6xl lg:text-7xl'}`}
            style={{ color: windColor }}
          >
            {Math.round(station.wind)}
          </span>
          <span className="text-gray-700 text-3xl font-light">/</span>
          <span
            className={`font-semibold tabular-nums ${compact ? 'text-3xl' : 'text-4xl lg:text-5xl'}`}
            style={{ color: gustColor }}
          >
            {Math.round(station.gust)}
          </span>
          <span className="text-gray-600 text-lg ml-1">nds</span>
        </div>
      </div>

      {/* Labels */}
      <div className="flex gap-4 text-xs text-gray-600 mb-4 flex-shrink-0">
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-0.5 rounded-full" style={{ background: windColor }} />
          <span>Moyen</span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-0.5 rounded-full" style={{ background: gustColor }} />
          <span>Rafales</span>
        </div>
      </div>

      {/* Chart */}
      {showChart && (
        <div className="flex-1 min-h-0">
          <WindChart
            stationId={station.stableId || station.id}
            source={station.source}
            hours={chartHours}
          />
        </div>
      )}
    </div>
  )
}

// Export with Suspense boundary for useSearchParams
export default function DisplayPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <svg className="w-12 h-12 animate-spin text-cyan-400" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4"/>
          </svg>
          <p className="text-gray-400 text-lg">Chargement...</p>
        </div>
      </div>
    }>
      <DisplayContent />
    </Suspense>
  )
}
