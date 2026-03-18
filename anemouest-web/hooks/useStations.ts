'use client'
import { useEffect, useCallback, useRef } from 'react'
import { useAppStore } from '@/store/appStore'
import type { WindStation } from '@/store/appStore'
import { API as API_BASE, apiFetch } from '@/lib/api'

export function useStations() {
  const { enabledSources, refreshInterval, setStations, addToast } = useAppStore()
  const windsupToken = useRef<string | null>(null)
  const windsupExpiredNotified = useRef(false)

  // Load windsup token from localStorage
  useEffect(() => {
    windsupToken.current = localStorage.getItem('windsupToken')
  }, [])

  const fetchStations = useCallback(async () => {
    const allStations: WindStation[] = []
    await Promise.all(
      enabledSources.map(async (source) => {
        try {
          if (source === 'windsup' && !windsupToken.current) return
          const base = API_BASE
          let url = `${base}/${source}`
          if (source === 'windsup' && windsupToken.current) {
            url += `?token=${encodeURIComponent(windsupToken.current)}`
          }
          const res = await apiFetch(url)

          if (source === 'windsup') {
            if (res.status === 401) {
              windsupToken.current = null
              localStorage.removeItem('windsupToken')
              if (!windsupExpiredNotified.current) {
                windsupExpiredNotified.current = true
                addToast({
                  message: 'Session WindsUp expirée — reconnectez-vous',
                  type: 'warning',
                })
              }
              return
            }
          }

          if (!res.ok) return
          const data = await res.json()

          // Handle WindsUp token refresh (auto-relogin succeeded server-side)
          if (source === 'windsup' && data.newToken) {
            windsupToken.current = data.newToken
            localStorage.setItem('windsupToken', data.newToken)
          }

          // Warn if WindsUp data is subscription-gated (cookies not authenticating)
          if (source === 'windsup' && data.hasGatedData && !windsupExpiredNotified.current) {
            windsupExpiredNotified.current = true
            addToast({
              message: data.warning || 'WindsUp : données partielles, abonnement non reconnu',
              type: 'warning',
            })
          }

          const stations = data.stations || []
          stations.forEach((s: any) => {
            allStations.push({
              id: s.id, stableId: s.stableId, name: s.name,
              lat: s.lat, lon: s.lon,
              wind: s.wind || 0, gust: s.gust || 0, direction: s.direction || 0,
              isOnline: s.isOnline !== false, source: s.source || source,
              altitude: s.altitude, pressure: s.pressure,
              temperature: s.temperature, humidity: s.humidity,
              ts: s.ts || s.lastUpdate,
            })
          })
        } catch (err) { console.error(`Error fetching ${source}:`, err) }
      })
    )
    return allStations
  }, [enabledSources, addToast])

  useEffect(() => {
    let mounted = true
    const load = async () => {
      const data = await fetchStations()
      if (mounted) setStations(data)
    }
    load()
    const interval = setInterval(load, refreshInterval * 1000)
    return () => { mounted = false; clearInterval(interval) }
  }, [fetchStations, refreshInterval, setStations])
}
