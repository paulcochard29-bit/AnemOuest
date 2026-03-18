'use client'
import { useState, useEffect, useRef, useMemo, useCallback } from 'react'
import { fetchRadarFrames, getRadarTileUrl } from '@/lib/radar-api'
import type { RadarData } from '@/lib/types'

export function useRadar() {
  const [radarEnabled, setRadarEnabled] = useState(false)
  const [radarData, setRadarData] = useState<RadarData | null>(null)
  const [radarFrameIndex, setRadarFrameIndex] = useState(0)
  const [radarPlaying, setRadarPlaying] = useState(false)
  const radarIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    if (!radarEnabled) {
      setRadarData(null)
      setRadarPlaying(false)
      return
    }
    const load = async () => {
      try {
        const data = await fetchRadarFrames()
        setRadarData(data)
        setRadarFrameIndex(data.past.length - 1)
      } catch (err) { console.error('Radar error:', err) }
    }
    load()
    const interval = setInterval(load, 5 * 60 * 1000)
    return () => clearInterval(interval)
  }, [radarEnabled])

  useEffect(() => {
    if (!radarPlaying || !radarData) {
      if (radarIntervalRef.current) clearInterval(radarIntervalRef.current)
      radarIntervalRef.current = null
      return
    }
    const totalFrames = radarData.past.length + radarData.nowcast.length
    radarIntervalRef.current = setInterval(() => {
      setRadarFrameIndex(prev => (prev + 1) % totalFrames)
    }, 500)
    return () => { if (radarIntervalRef.current) clearInterval(radarIntervalRef.current) }
  }, [radarPlaying, radarData])

  const radarTileUrl = useMemo(() => {
    if (!radarEnabled || !radarData) return null
    const allFrames = [...radarData.past, ...radarData.nowcast]
    const frame = allFrames[radarFrameIndex]
    if (!frame) return null
    return getRadarTileUrl(radarData.host, frame)
  }, [radarEnabled, radarData, radarFrameIndex])

  const radarTimeLabel = useMemo(() => {
    if (!radarData) return ''
    const allFrames = [...radarData.past, ...radarData.nowcast]
    const frame = allFrames[radarFrameIndex]
    if (!frame) return ''
    const d = new Date(frame.time * 1000)
    const isNowcast = radarFrameIndex >= radarData.past.length
    return `${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}${isNowcast ? ' (prev.)' : ''}`
  }, [radarData, radarFrameIndex])

  const totalFrames = radarData ? radarData.past.length + radarData.nowcast.length : 0

  const toggleRadar = useCallback(() => setRadarEnabled(prev => !prev), [])
  const togglePlay = useCallback(() => setRadarPlaying(prev => !prev), [])

  return {
    radarEnabled, radarTileUrl, radarTimeLabel,
    radarPlaying, radarFrameIndex, totalFrames, radarData,
    toggleRadar, togglePlay, setRadarFrameIndex, setRadarPlaying,
  }
}
