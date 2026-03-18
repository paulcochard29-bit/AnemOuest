'use client'
import { useState, useCallback } from 'react'

interface FlyTo {
  lon: number
  lat: number
  zoom?: number
}

export function useGeolocation() {
  const [flyTo, setFlyTo] = useState<FlyTo | null>(null)

  const geolocate = useCallback(() => {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setFlyTo({ lon: pos.coords.longitude, lat: pos.coords.latitude, zoom: 12 })
        setTimeout(() => setFlyTo(null), 2000)
      },
      (err) => console.warn('Geolocation error:', err),
      { enableHighAccuracy: true, timeout: 10000 }
    )
  }, [])

  const flyToLocation = useCallback((lon: number, lat: number, zoom = 13) => {
    setFlyTo({ lon, lat, zoom })
    setTimeout(() => setFlyTo(null), 2000)
  }, [])

  return { flyTo, geolocate, flyToLocation }
}
