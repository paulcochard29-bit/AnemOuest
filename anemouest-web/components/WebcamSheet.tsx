'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import type { Webcam } from '@/store/appStore'
import { useSwipe } from '@/hooks/useSwipe'
import { EmbedPicker } from './EmbedPicker'
import { API, apiFetch } from '@/lib/api'

interface TimelineEntry { timestamp: number; url?: string; estimated?: boolean }
interface Props { webcam: Webcam; onClose: () => void; onSwipe?: (dir: 'left' | 'right') => void }

function relativeTime(ts: number): string {
  const diff = Math.floor((Date.now() - ts * 1000) / 60000)
  if (diff < 1) return "à l'instant"
  if (diff < 60) return `il y a ${diff} min`
  if (diff < 1440) return `il y a ${Math.floor(diff / 60)}h`
  return `il y a ${Math.floor(diff / 1440)}j`
}

export function WebcamSheet({ webcam, onClose, onSwipe }: Props) {
  const [imgTs, setImgTs] = useState(Date.now())
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [hlsLoaded, setHlsLoaded] = useState(false)
  const [showLive, setShowLive] = useState(true)
  const [timeline, setTimeline] = useState<TimelineEntry[]>([])
  const [timelineIdx, setTimelineIdx] = useState(0)
  const [loadingTimeline, setLoadingTimeline] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState(1)
  const [zoom, setZoom] = useState(1)
  const [imgLoading, setImgLoading] = useState(true)
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<any>(null)
  const playTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const hasStream = !!webcam.streamUrl

  useEffect(() => {
    if (!hasStream || !showLive || !videoRef.current) return
    let hls: any = null
    const setupHls = async () => {
      const Hls = (await import('hls.js')).default
      if (!Hls.isSupported() || !videoRef.current) return
      hls = new Hls({ enableWorker: true, lowLatencyMode: true })
      hls.loadSource(webcam.streamUrl!)
      hls.attachMedia(videoRef.current)
      hls.on(Hls.Events.MANIFEST_PARSED, () => { videoRef.current?.play().catch(() => {}); setHlsLoaded(true) })
      hlsRef.current = hls
    }
    if (videoRef.current.canPlayType('application/vnd.apple.mpegurl')) {
      videoRef.current.src = webcam.streamUrl!
      videoRef.current.play().catch(() => {})
      setHlsLoaded(true)
    } else { setupHls() }
    return () => { hls?.destroy(); hlsRef.current = null }
  }, [webcam.streamUrl, hasStream, showLive])

  useEffect(() => {
    if (!showLive || hasStream) return
    refreshTimerRef.current = setInterval(() => setImgTs(Date.now()), 30000)
    return () => { if (refreshTimerRef.current) clearInterval(refreshTimerRef.current) }
  }, [showLive, hasStream])

  const fetchTimeline = useCallback(async () => {
    setLoadingTimeline(true)
    try {
      const src = webcam.source.toLowerCase().replace(/[-\s]/g, '')
      const params = new URLSearchParams({ source: src, id: webcam.id })
      const res = await apiFetch(`${API}/webcam-timeline?${params}`)
      if (!res.ok) throw new Error('Timeline fetch failed')
      const data = await res.json()
      const entries = (data.timestamps || []).sort((a: TimelineEntry, b: TimelineEntry) => b.timestamp - a.timestamp)
      setTimeline(entries)
      setTimelineIdx(0)
    } catch { setTimeline([]) }
    setLoadingTimeline(false)
  }, [webcam.id, webcam.source])

  const goToHistory = useCallback((hoursAgo: number) => {
    setShowLive(false)
    setPlaying(false)
    setImgLoading(true)
    if (timeline.length === 0) { fetchTimeline() }
    if (timeline.length > 0 && hoursAgo > 0) {
      const target = Date.now() / 1000 - hoursAgo * 3600
      const idx = timeline.findIndex(t => t.timestamp <= target)
      setTimelineIdx(idx >= 0 ? idx : timeline.length - 1)
    }
  }, [timeline, fetchTimeline])

  useEffect(() => {
    if (timeline.length > 0 && !showLive) setTimelineIdx(0)
  }, [timeline.length, showLive])

  useEffect(() => {
    if (!playing || timeline.length === 0) {
      if (playTimerRef.current) clearInterval(playTimerRef.current)
      return
    }
    const ms = 1000 / speed
    playTimerRef.current = setInterval(() => {
      setTimelineIdx(prev => {
        if (prev >= timeline.length - 1) { setPlaying(false); return prev }
        return prev + 1
      })
    }, ms)
    return () => { if (playTimerRef.current) clearInterval(playTimerRef.current) }
  }, [playing, speed, timeline.length])

  const goLive = () => { setShowLive(true); setPlaying(false); setImgTs(Date.now()); setZoom(1); setImgLoading(true) }
  const cycleSpeed = () => { const speeds = [0.5, 1, 2, 4]; setSpeed(speeds[(speeds.indexOf(speed) + 1) % speeds.length]) }

  const currentEntry = timeline[timelineIdx]
  const historyImgUrl = currentEntry?.url
    ? `${currentEntry.url}${currentEntry.url.includes('?') ? '&' : '?'}_=${Date.now()}`
    : null
  const liveImgUrl = `${webcam.imageUrl}${webcam.imageUrl.includes('?') ? '&' : '?'}t=${imgTs}`

  // Fullscreen
  if (isFullscreen) {
    return (
      <div className="fixed inset-0 z-[2000] bg-black flex flex-col" onClick={e => { if (e.target === e.currentTarget) setIsFullscreen(false) }}>
        <div className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between px-4 py-3 bg-gradient-to-b from-black/60 to-transparent">
          <div className="text-white">
            <div className="text-[15px] font-semibold">{webcam.name}</div>
            <div className="text-[12px] text-white/60">{webcam.location}</div>
          </div>
          <button className="p-2 rounded-full bg-white/15 backdrop-blur-md text-white" onClick={() => setIsFullscreen(false)}>
            <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>

        <div className="flex-1 flex items-center justify-center overflow-hidden">
          {showLive && hasStream && hlsLoaded ? (
            <video ref={videoRef} className="max-w-full max-h-full" autoPlay muted playsInline />
          ) : (
            <img
              src={showLive ? liveImgUrl : (historyImgUrl || liveImgUrl)}
              alt={webcam.name}
              className="max-w-full max-h-full object-contain transition-transform"
              style={{ transform: `scale(${zoom})` }}
              onDoubleClick={() => setZoom(z => z > 1 ? 1 : 2.5)}
            />
          )}
        </div>

        <div className="absolute bottom-0 left-0 right-0 z-10 px-4 py-3 bg-gradient-to-t from-black/60 to-transparent">
          {!showLive && timeline.length > 0 && currentEntry && (
            <div className="text-[12px] text-white/80 text-center mb-2">
              {new Date(currentEntry.timestamp * 1000).toLocaleString('fr-FR', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' })}
              {' · '}{relativeTime(currentEntry.timestamp)}
            </div>
          )}
          <div className="flex items-center gap-2">
            <button onClick={() => setZoom(z => Math.max(1, z - 0.5))} className="px-2 py-1 rounded-lg bg-white/15 backdrop-blur-md text-white text-[13px]">-</button>
            <span className="text-white text-[12px] tabular-nums w-8 text-center">{zoom.toFixed(1)}x</span>
            <button onClick={() => setZoom(z => Math.min(5, z + 0.5))} className="px-2 py-1 rounded-lg bg-white/15 backdrop-blur-md text-white text-[13px]">+</button>
            <div className="flex-1" />
            <button onClick={() => { setImgTs(Date.now()) }} className="px-3 py-1 rounded-lg bg-white/15 backdrop-blur-md text-white text-[13px]">
              Rafraichir
            </button>
          </div>
        </div>
      </div>
    )
  }

  const swipe = useSwipe(onSwipe)

  return (
    <>
      <div className="sheet-backdrop" onClick={onClose} />
      <div className="sheet" {...swipe}>
        <div className="flex justify-center pt-1.5 pb-1 md:hidden">
          <div className="w-9 h-[5px] rounded-full bg-white/30" />
        </div>
        <div className="overflow-auto max-h-[calc(50vh-20px)] md:max-h-screen">
          {/* Header */}
          <div className="flex items-start justify-between px-4 pt-3 pb-1">
            <div>
              <h2 className="text-[18px] font-bold text-[#1c1c1e] tracking-tight">{webcam.name}</h2>
              <div className="flex items-center gap-1.5 mt-0.5">
                <span className="text-[12px] font-bold px-2 py-0.5 rounded-full bg-[#af52de]/10 text-[#af52de]">{webcam.source}</span>
                <span className="text-[13px] text-[#8e8e93]">{webcam.location}</span>
              </div>
            </div>
            <button onClick={onClose} className="px-3 py-1 rounded-full text-[13px] font-medium text-[#007aff] glass-btn">Fermer</button>
          </div>

          {/* Image / Video */}
          <div className="mx-4 mt-2 mb-2 relative rounded-2xl overflow-hidden bg-black/5 cursor-pointer shadow-sm" onClick={() => setIsFullscreen(true)}>
            {imgLoading && !(showLive && hasStream) && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/5 z-[1]">
                <div className="w-7 h-7 border-[2.5px] border-white/30 border-t-[#af52de] rounded-full animate-spin" />
              </div>
            )}
            {showLive && hasStream ? (
              <video ref={videoRef} className="w-full aspect-video object-cover" autoPlay muted playsInline />
            ) : (
              <img
                src={showLive ? liveImgUrl : (historyImgUrl || liveImgUrl)}
                alt={webcam.name}
                className="w-full aspect-video object-cover"
                onLoad={() => setImgLoading(false)}
                onError={() => setImgLoading(false)}
              />
            )}
            {/* Overlay badges */}
            {showLive && hasStream && (
              <div className="absolute top-2.5 left-2.5 flex items-center gap-1.5 px-2 py-1 rounded-full bg-[#ff3b30]/90 backdrop-blur-sm shadow-sm">
                <span className="w-2 h-2 rounded-full bg-white animate-pulse" />
                <span className="text-[11px] font-bold text-white tracking-wide">LIVE</span>
              </div>
            )}
            {!showLive && currentEntry && (
              <div className="absolute bottom-2.5 left-2.5 px-2.5 py-1 rounded-full bg-black/50 backdrop-blur-md text-[11px] font-semibold text-white shadow-sm">
                {new Date(currentEntry.timestamp * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                {' · '}{relativeTime(currentEntry.timestamp)}
              </div>
            )}
            {showLive && !hasStream && (
              <div className="absolute bottom-2.5 right-2.5 px-2.5 py-1 rounded-full bg-black/50 backdrop-blur-md text-[11px] font-semibold text-white flex items-center gap-1.5 shadow-sm">
                <span className="w-2 h-2 rounded-full bg-[#34c759]" />
                Auto-refresh 30s
              </div>
            )}
            {/* Expand icon */}
            <div className="absolute top-2.5 right-2.5 p-1.5 rounded-lg bg-black/30 backdrop-blur-sm">
              <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M4 8V4h4M20 8V4h-4M4 16v4h4M20 16v4h-4" /></svg>
            </div>
          </div>

          {/* Mode toggle */}
          <div className="mx-4 mb-2 flex glass-card rounded-xl p-0.5">
            <button onClick={goLive}
              className={`flex-1 py-2 text-[13px] font-bold rounded-lg transition ${showLive ? 'bg-white/80 text-[#1c1c1e] shadow-sm' : 'text-[#8e8e93]'}`}>
              Live
            </button>
            <button onClick={() => { setShowLive(false); if (timeline.length === 0) fetchTimeline() }}
              className={`flex-1 py-2 text-[13px] font-bold rounded-lg transition ${!showLive ? 'bg-white/80 text-[#1c1c1e] shadow-sm' : 'text-[#8e8e93]'}`}>
              Historique
            </button>
          </div>

          {/* Timeline controls */}
          {!showLive && (
            <div className="mx-4 mb-3">
              {loadingTimeline ? (
                <div className="flex items-center justify-center py-6">
                  <div className="w-6 h-6 border-2 border-white/30 border-t-[#af52de] rounded-full animate-spin" />
                </div>
              ) : timeline.length > 0 ? (
                <>
                  {/* Jump buttons */}
                  <div className="flex gap-1.5 mb-2">
                    {[1, 6, 24, 48].map(h => (
                      <button key={h} onClick={() => goToHistory(h)}
                        className="flex-1 py-2 glass-btn rounded-xl text-[13px] font-bold text-[#af52de] active:scale-95 transition">
                        -{h}h
                      </button>
                    ))}
                  </div>

                  {/* Player */}
                  <div className="glass-card rounded-2xl p-3">
                    <div className="flex items-center gap-3 mb-3">
                      <button onClick={() => setPlaying(!playing)}
                        className="w-9 h-9 rounded-full bg-[#af52de] text-white flex items-center justify-center flex-shrink-0 shadow-md active:scale-90 transition">
                        {playing
                          ? <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" /></svg>
                          : <svg className="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
                        }
                      </button>
                      <button onClick={cycleSpeed}
                        className="px-2.5 py-1.5 rounded-lg glass-btn text-[12px] font-bold text-[#1c1c1e] tabular-nums min-w-[38px] text-center">
                        {speed}x
                      </button>
                      <div className="flex-1 text-center">
                        <span className="text-[13px] font-bold text-[#1c1c1e] tabular-nums">
                          {timelineIdx + 1}
                        </span>
                        <span className="text-[13px] text-[#8e8e93]"> / {timeline.length}</span>
                      </div>
                      <button onClick={goLive}
                        className="px-3 py-1.5 rounded-full text-[12px] font-bold bg-[#34c759] text-white shadow-sm active:scale-95 transition">
                        Live
                      </button>
                    </div>
                    <input
                      type="range" min={0} max={Math.max(0, timeline.length - 1)} value={timelineIdx}
                      onChange={e => { setTimelineIdx(Number(e.target.value)); setPlaying(false) }}
                      className="w-full accent-[#af52de]"
                    />
                    {currentEntry && (
                      <div className="text-center mt-1.5 text-[12px] font-semibold text-[#8e8e93] tabular-nums">
                        {new Date(currentEntry.timestamp * 1000).toLocaleString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                      </div>
                    )}
                  </div>
                </>
              ) : (
                <div className="py-6 text-center text-[#8e8e93] text-[15px]">Historique indisponible</div>
              )}
            </div>
          )}

          {/* Actions */}
          <div className="mx-4 mb-2 flex gap-2">
            <button onClick={() => { setImgTs(Date.now()); setImgLoading(true) }}
              className="flex-1 py-2.5 glass-btn rounded-2xl text-[15px] text-[#007aff] font-semibold text-center active:scale-95 transition">
              Rafraichir
            </button>
            <button onClick={() => setIsFullscreen(true)}
              className="flex-1 py-2.5 bg-[#007aff] rounded-2xl text-[15px] text-white font-semibold text-center shadow-sm active:scale-95 transition">
              Plein ecran
            </button>
          </div>
          <div className="flex justify-end px-4 pb-4">
            <EmbedPicker type="webcam" id={webcam.id} />
          </div>
        </div>
      </div>
    </>
  )
}
