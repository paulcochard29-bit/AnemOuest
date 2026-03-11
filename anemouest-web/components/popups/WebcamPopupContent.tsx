'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import type { Webcam } from '@/store/appStore'

const API = 'https://anemouest-api.vercel.app/api'

interface TimelineEntry { timestamp: number; url?: string; estimated?: boolean }

interface Props {
  webcam: Webcam
  expanded: boolean
  onExpand: () => void
}

function relativeTime(ts: number): string {
  const diff = Math.floor((Date.now() - ts * 1000) / 60000)
  if (diff < 1) return "à l'instant"
  if (diff < 60) return `il y a ${diff} min`
  if (diff < 1440) return `il y a ${Math.floor(diff / 60)}h`
  return `il y a ${Math.floor(diff / 1440)}j`
}

export function WebcamPopupContent({ webcam, expanded, onExpand }: Props) {
  const thumbUrl = `${API}/webcam-image?id=${encodeURIComponent(webcam.id)}&redirect=true&t=${Math.floor(Date.now() / 60000)}`
  const hasStream = !!webcam.streamUrl

  // Live/stream state
  const [imgTs, setImgTs] = useState(Date.now())
  const [hlsLoaded, setHlsLoaded] = useState(false)
  const [showLive, setShowLive] = useState(true)
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<any>(null)
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Timeline state
  const [timeline, setTimeline] = useState<TimelineEntry[]>([])
  const [timelineIdx, setTimelineIdx] = useState(0)
  const [loadingTimeline, setLoadingTimeline] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState(1)
  const playTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Fullscreen
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [zoom, setZoom] = useState(1)

  // Freshness for compact view
  let freshness = ''
  let dotColor = '#34c759'
  if (webcam.lastCapture) {
    const diffMs = Date.now() - webcam.lastCapture
    const diffMin = Math.floor(diffMs / 60000)
    const diffH = Math.floor(diffMin / 60)
    if (diffMin < 60) freshness = `il y a ${diffMin} min`
    else if (diffH < 24) freshness = `il y a ${diffH}h`
    else freshness = `il y a ${Math.floor(diffH / 24)}j`
    if (diffH >= 3) dotColor = '#ff3b30'
    else if (diffH >= 1) dotColor = '#ff9500'
  }

  // HLS setup (only when expanded + live)
  useEffect(() => {
    if (!expanded || !hasStream || !showLive || !videoRef.current) return
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
    return () => { hls?.destroy(); hlsRef.current = null; setHlsLoaded(false) }
  }, [webcam.streamUrl, hasStream, showLive, expanded])

  // Auto-refresh static images when live
  useEffect(() => {
    if (!expanded || !showLive || hasStream) return
    refreshTimerRef.current = setInterval(() => setImgTs(Date.now()), 30000)
    return () => { if (refreshTimerRef.current) clearInterval(refreshTimerRef.current) }
  }, [expanded, showLive, hasStream])

  // Fetch timeline
  const fetchTimeline = useCallback(async () => {
    setLoadingTimeline(true)
    try {
      const src = webcam.source.toLowerCase().replace(/[-\s]/g, '')
      const params = new URLSearchParams({ source: src, id: webcam.id })
      const res = await fetch(`${API}/webcam-timeline?${params}`)
      if (!res.ok) throw new Error('Timeline fetch failed')
      const data = await res.json()
      const entries = (data.timestamps || []).sort((a: TimelineEntry, b: TimelineEntry) => b.timestamp - a.timestamp)
      setTimeline(entries)
      setTimelineIdx(0)
    } catch { setTimeline([]) }
    setLoadingTimeline(false)
  }, [webcam.id, webcam.source])

  // Timeline playback
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

  const goToHistory = useCallback((hoursAgo: number) => {
    setShowLive(false)
    setPlaying(false)
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

  const goLive = () => { setShowLive(true); setPlaying(false); setImgTs(Date.now()); setZoom(1) }
  const cycleSpeed = () => { const speeds = [0.5, 1, 2, 4]; setSpeed(speeds[(speeds.indexOf(speed) + 1) % speeds.length]) }

  const currentEntry = timeline[timelineIdx]
  const historyImgUrl = currentEntry?.url
    ? `${currentEntry.url}${currentEntry.url.includes('?') ? '&' : '?'}_=${Date.now()}`
    : null
  const liveImgUrl = `${webcam.imageUrl}${webcam.imageUrl.includes('?') ? '&' : '?'}t=${imgTs}`

  // Fullscreen overlay
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
            <button onClick={() => setImgTs(Date.now())} className="px-3 py-1 rounded-lg bg-white/15 backdrop-blur-md text-white text-[13px]">Rafraichir</button>
          </div>
        </div>
      </div>
    )
  }

  // === COMPACT VIEW (not expanded) ===
  if (!expanded) {
    return (
      <div>
        <div className="relative bg-[#1c1c1e]">
          <img src={thumbUrl} alt={webcam.name} className="w-full object-cover h-[160px]" loading="eager"
            onError={(e) => { (e.target as HTMLImageElement).src = webcam.imageUrl }} />
          {freshness && (
            <div className="absolute bottom-2 left-2 flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-black/50 backdrop-blur-sm">
              <span className="w-[6px] h-[6px] rounded-full flex-shrink-0" style={{ background: dotColor }} />
              <span className="text-[10px] font-bold text-white">{freshness}</span>
            </div>
          )}
        </div>
        <div className="px-3 py-2">
          <div className="text-[14px] font-bold text-[#1c1c1e] truncate">{webcam.name}</div>
          <div className="text-[11px] text-[#8e8e93] truncate mt-0.5">{webcam.location}</div>
          <div className="flex items-center justify-between mt-2">
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#af52de] text-white">{webcam.source}</span>
            <button onClick={onExpand}
              className="text-[12px] font-semibold text-[#007aff] hover:text-[#0056b3] transition flex items-center gap-0.5">
              Voir en direct
              <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M9 5l7 7-7 7" /></svg>
            </button>
          </div>
        </div>
      </div>
    )
  }

  // === EXPANDED VIEW — full player ===
  return (
    <div>
      {/* Video / Image */}
      <div className="relative bg-[#1c1c1e] cursor-pointer" onClick={() => setIsFullscreen(true)}>
        {showLive && hasStream ? (
          <video ref={videoRef} className="w-full aspect-video object-cover" autoPlay muted playsInline />
        ) : (
          <img
            src={showLive ? liveImgUrl : (historyImgUrl || liveImgUrl)}
            alt={webcam.name}
            className="w-full aspect-video object-cover"
            onError={(e) => { (e.target as HTMLImageElement).src = webcam.imageUrl }}
          />
        )}
        {/* Overlay badges */}
        {showLive && hasStream && hlsLoaded && (
          <div className="absolute top-2 left-2 flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-[#ff3b30]/90 backdrop-blur-sm">
            <span className="w-1.5 h-1.5 rounded-full bg-white animate-pulse" />
            <span className="text-[10px] font-bold text-white">LIVE</span>
          </div>
        )}
        {showLive && !hasStream && (
          <div className="absolute bottom-2 right-2 px-2 py-0.5 rounded-full bg-black/50 backdrop-blur-sm text-[10px] font-bold text-white flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-[#34c759]" />
            Auto-refresh 30s
          </div>
        )}
        {!showLive && currentEntry && (
          <div className="absolute bottom-2 left-2 px-2 py-0.5 rounded-full bg-black/50 backdrop-blur-sm text-[10px] font-bold text-white">
            {new Date(currentEntry.timestamp * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
            {' · '}{relativeTime(currentEntry.timestamp)}
          </div>
        )}
        {/* Fullscreen icon */}
        <div className="absolute top-2 right-2 p-1 rounded-md bg-black/30 backdrop-blur-sm">
          <svg className="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path strokeLinecap="round" d="M4 8V4h4M20 8V4h-4M4 16v4h4M20 16v4h-4" /></svg>
        </div>
      </div>

      {/* Info */}
      <div className="px-3 pt-2 pb-1">
        <div className="text-[14px] font-bold text-[#1c1c1e] truncate">{webcam.name}</div>
        <div className="flex items-center gap-1.5 mt-0.5">
          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#af52de]/10 text-[#af52de]">{webcam.source}</span>
          <span className="text-[11px] text-[#8e8e93] truncate">{webcam.location}</span>
        </div>
      </div>

      {/* Live / Historique toggle */}
      <div className="mx-3 mt-1.5 mb-1.5 flex rounded-lg bg-black/5 p-0.5">
        <button onClick={goLive}
          className={`flex-1 py-1.5 text-[12px] font-bold rounded-md transition ${showLive ? 'bg-white shadow-sm text-[#1c1c1e]' : 'text-[#8e8e93]'}`}>
          Live
        </button>
        <button onClick={() => { setShowLive(false); if (timeline.length === 0) fetchTimeline() }}
          className={`flex-1 py-1.5 text-[12px] font-bold rounded-md transition ${!showLive ? 'bg-white shadow-sm text-[#1c1c1e]' : 'text-[#8e8e93]'}`}>
          Historique
        </button>
      </div>

      {/* Timeline controls */}
      {!showLive && (
        <div className="mx-3 mb-2">
          {loadingTimeline ? (
            <div className="flex items-center justify-center py-4">
              <div className="w-5 h-5 border-2 border-white/30 border-t-[#af52de] rounded-full animate-spin" />
            </div>
          ) : timeline.length > 0 ? (
            <>
              {/* Jump buttons */}
              <div className="flex gap-1 mb-1.5">
                {[1, 6, 24, 48].map(h => (
                  <button key={h} onClick={() => goToHistory(h)}
                    className="flex-1 py-1.5 rounded-lg bg-black/5 text-[11px] font-bold text-[#af52de] active:scale-95 transition">
                    -{h}h
                  </button>
                ))}
              </div>
              {/* Player controls */}
              <div className="rounded-xl bg-black/5 p-2">
                <div className="flex items-center gap-2 mb-2">
                  <button onClick={() => setPlaying(!playing)}
                    className="w-7 h-7 rounded-full bg-[#af52de] text-white flex items-center justify-center flex-shrink-0 active:scale-90 transition">
                    {playing
                      ? <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" /></svg>
                      : <svg className="w-3 h-3 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
                    }
                  </button>
                  <button onClick={cycleSpeed}
                    className="px-2 py-1 rounded-md bg-white/60 text-[11px] font-bold text-[#1c1c1e] tabular-nums min-w-[32px] text-center">
                    {speed}x
                  </button>
                  <div className="flex-1 text-center">
                    <span className="text-[12px] font-bold text-[#1c1c1e] tabular-nums">{timelineIdx + 1}</span>
                    <span className="text-[12px] text-[#8e8e93]"> / {timeline.length}</span>
                  </div>
                  <button onClick={goLive}
                    className="px-2 py-1 rounded-full text-[10px] font-bold bg-[#34c759] text-white active:scale-95 transition">
                    Live
                  </button>
                </div>
                <input
                  type="range" min={0} max={Math.max(0, timeline.length - 1)} value={timelineIdx}
                  onChange={e => { setTimelineIdx(Number(e.target.value)); setPlaying(false) }}
                  className="w-full accent-[#af52de]"
                />
                {currentEntry && (
                  <div className="text-center mt-1 text-[11px] font-semibold text-[#8e8e93] tabular-nums">
                    {new Date(currentEntry.timestamp * 1000).toLocaleString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="py-4 text-center text-[#8e8e93] text-[12px]">Historique indisponible</div>
          )}
        </div>
      )}

      {/* Actions */}
      <div className="mx-3 mb-2 flex gap-1.5">
        <button onClick={() => setImgTs(Date.now())}
          className="flex-1 py-2 rounded-xl bg-black/5 text-[12px] text-[#007aff] font-semibold text-center active:scale-95 transition">
          Rafraichir
        </button>
        <button onClick={() => setIsFullscreen(true)}
          className="flex-1 py-2 bg-[#007aff] rounded-xl text-[12px] text-white font-semibold text-center active:scale-95 transition">
          Plein écran
        </button>
      </div>

      {/* Réduire */}
      <div className="px-3 pb-2 flex justify-end">
        <button onClick={onExpand}
          className="text-[12px] font-semibold text-[#8e8e93] hover:text-[#1c1c1e] transition flex items-center gap-0.5">
          Réduire
          <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2.5} viewBox="0 0 24 24"><path strokeLinecap="round" d="M6 9l6 6 6-6" /></svg>
        </button>
      </div>
    </div>
  )
}
