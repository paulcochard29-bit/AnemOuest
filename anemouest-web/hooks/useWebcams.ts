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
        // Fetch webcams + health data in parallel
        const [webcamsRes, healthRes] = await Promise.all([
          apiFetch(`${API_BASE}/webcams`),
          apiFetch(`${API_BASE}/webcam-health`).catch(() => null),
        ])
        if (!webcamsRes.ok) return
        const data = await webcamsRes.json()
        const healthData = healthRes?.ok ? await healthRes.json() : { webcams: {} }
        const healthMap = healthData.webcams || {}

        if (mounted) setWebcams(data.map((w: any) => ({
          id: w.id, name: w.name, location: w.location, latitude: w.latitude,
          longitude: w.longitude, imageUrl: w.imageUrl, source: w.source,
          region: w.region, refreshInterval: w.refreshInterval, streamUrl: w.streamUrl,
          lastCapture: w.lastCapture || healthMap[w.id]?.lastSuccess || null,
        })))
      } catch (err) { console.error('Error fetching webcams:', err) }
    }
    fetchWebcams()
    const interval = setInterval(fetchWebcams, 120000) // refresh every 2min
    return () => { mounted = false; clearInterval(interval) }
  }, [setWebcams])
}
