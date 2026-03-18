'use client'
import { useEffect, useMemo } from 'react'
import { useAppStore } from '@/store/appStore'
import type { Spot } from '@/store/appStore'
import kiteSpots from '@/data/kite-spots.json'
import surfSpots from '@/data/surf-spots.json'
import { API as API_BASE, apiFetch } from '@/lib/api'

export function useSpots() {
  const setSpots = useAppStore(s => s.setSpots)
  const spots = useAppStore(s => s.spots)

  // Fetch paragliding spots from API
  useEffect(() => {
    let mounted = true
    const fetchParagliding = async () => {
      try {
        const res = await apiFetch(`${API_BASE}/paragliding-spots`)
        if (!res.ok) return
        const data = await res.json()
        const paraSpots: Spot[] = (data.spots || []).map((s: any) => ({
          id: s.id, name: s.name, lat: s.latitude, lon: s.longitude,
          spotType: 'paragliding' as const,
          level: s.level ? String(s.level) : null,
          orientation: s.orientations || [],
          altitude: s.altitude, description: s.description,
        }))

        // Combine with local kite + surf spots
        const kite: Spot[] = (kiteSpots as any[]).map(s => ({
          id: s.id, name: s.name, lat: s.lat, lon: s.lon,
          spotType: 'kite' as const, level: s.level,
          orientation: s.orientation, kiteType: s.kiteType,
        }))
        const surf: Spot[] = (surfSpots as any[]).map(s => ({
          id: s.id, name: s.name, lat: s.lat, lon: s.lon,
          spotType: 'surf' as const, level: s.level,
          orientation: s.orientation, surfType: s.surfType,
        }))

        if (mounted) setSpots([...kite, ...surf, ...paraSpots])
      } catch (err) { console.error('Error fetching paragliding:', err) }
    }
    fetchParagliding()
    return () => { mounted = false }
  }, [setSpots])

  return spots
}
