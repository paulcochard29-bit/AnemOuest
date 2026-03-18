'use client'
import { useState, useEffect, useMemo } from 'react'
import { haversineDistance } from '@/lib/utils'
import { API as API_BASE, apiFetch } from '@/lib/api'

interface TidePort {
  cst: string
  name: string
  lat: number
  lon: number
  region: string
}

interface TideEvent {
  type: string
  time: string
  height: number
  coeff?: number
}

export function useTides() {
  const [tidePorts, setTidePorts] = useState<TidePort[]>([])

  useEffect(() => {
    const fetchTidePorts = async () => {
      try {
        const res = await apiFetch(`${API_BASE}/tide?list=true`)
        if (!res.ok) return
        const data = await res.json()
        setTidePorts(data.ports || [])
      } catch (err) { console.error('Error fetching tide ports:', err) }
    }
    fetchTidePorts()
  }, [])

  return { tidePorts }
}

export function useTideForLocation(lat: number | null, lon: number | null, tidePorts: TidePort[]) {
  const [tideData, setTideData] = useState<TideEvent[] | null>(null)
  const [tidePortName, setTidePortName] = useState('')
  const [nearestPort, setNearestPort] = useState<TidePort | null>(null)

  useEffect(() => {
    if (lat === null || lon === null || tidePorts.length === 0) {
      setTideData(null)
      return
    }

    let nearest = tidePorts[0]
    let minDist = haversineDistance(lat, lon, nearest.lat, nearest.lon)
    for (const port of tidePorts) {
      const d = haversineDistance(lat, lon, port.lat, port.lon)
      if (d < minDist) { nearest = port; minDist = d }
    }

    if (minDist > 100) { setTideData(null); setNearestPort(null); return }
    setTidePortName(nearest.name)
    setNearestPort(nearest)

    const fetchTide = async () => {
      try {
        const res = await apiFetch(`${API_BASE}/tide?port=${encodeURIComponent(nearest.cst)}`)
        if (!res.ok) return
        const data = await res.json()
        // Map API fields: datetime→time, coefficient→coeff, type high/low→PM/BM
        const events: TideEvent[] = (data.tides || []).map((t: any) => ({
          type: t.type === 'high' ? 'PM' : t.type === 'low' ? 'BM' : t.type,
          time: t.datetime || t.time,
          height: t.height,
          coeff: t.coefficient ?? t.coeff,
        }))
        setTideData(events)
      } catch { setTideData(null) }
    }
    fetchTide()
  }, [lat, lon, tidePorts])

  const nextTideEvents = useMemo(() => {
    if (!tideData) return null
    const now = new Date()
    const upcoming = tideData
      .filter(e => new Date(e.time) > now)
      .slice(0, 2)
    return upcoming.length > 0 ? upcoming : null
  }, [tideData])

  return { tideData, tidePortName, nextTideEvents, nearestPort }
}
