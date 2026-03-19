'use client'
import { useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { API as API_BASE, apiFetch } from '@/lib/api'

export function useWebcams() {
  const setWebcams = useAppStore(s => s.setWebcams)

  useEffect(() => {
    let mounted = true
    const fetchWebcams = async () => {
      try {
        const webcamsRes = await apiFetch(`${API_BASE}/webcams`)
        if (!webcamsRes.ok) return
        const data = await webcamsRes.json()

        if (mounted) setWebcams(data.map((w: any) => ({
          id: w.id, name: w.name, location: w.location, latitude: w.latitude,
          longitude: w.longitude, imageUrl: w.imageUrl, source: w.source,
          region: w.region, refreshInterval: w.refreshInterval, streamUrl: w.streamUrl,
          lastCapture: w.lastCapture || null,
        })))
      } catch (err) { console.error('Error fetching webcams:', err) }
    }
    fetchWebcams()
    const interval = setInterval(fetchWebcams, 120000) // refresh every 2min
    return () => { mounted = false; clearInterval(interval) }
  }, [setWebcams])
}
