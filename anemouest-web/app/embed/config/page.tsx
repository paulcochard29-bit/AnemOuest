'use client'

import { useState, useEffect, useCallback } from 'react'
import { API, apiFetch } from '@/lib/api'
const BASE_URL = typeof window !== 'undefined' ? window.location.origin : 'https://anemouest.app'

type WidgetType = 'station' | 'buoy' | 'webcam'
type WidgetStyle = 'card' | 'pill' | 'minimal' | 'dark'

interface StationItem { id: string; stableId?: string; name: string; source: string }
interface BuoyItem { id: string; name: string }
interface WebcamItem { id: string; name: string; location: string }

export default function EmbedConfigPage() {
  const [type, setType] = useState<WidgetType>('station')
  const [style, setStyle] = useState<WidgetStyle>('card')
  const [refresh, setRefresh] = useState(60)
  const [width, setWidth] = useState(320)
  const [height, setHeight] = useState(200)
  const [selectedId, setSelectedId] = useState('')
  const [copied, setCopied] = useState(false)

  // Data lists
  const [stations, setStations] = useState<StationItem[]>([])
  const [buoys, setBuoys] = useState<BuoyItem[]>([])
  const [webcams, setWebcams] = useState<WebcamItem[]>([])
  const [search, setSearch] = useState('')

  useEffect(() => {
    // Fetch stations from multiple sources
    const sources = ['pioupiou', 'gowind', 'meteofrance', 'windcornouaille']
    Promise.all(
      sources.map(src => apiFetch(`${API}/${src}`).then(r => r.ok ? r.json() : { stations: [] }).catch(() => ({ stations: [] })))
    ).then(results => {
      const all: StationItem[] = []
      for (const data of results) {
        for (const s of (data.stations || [])) {
          if (s.name && s.id) all.push({ id: s.id, stableId: s.stableId, name: s.name, source: s.source || '' })
        }
      }
      all.sort((a, b) => a.name.localeCompare(b.name))
      setStations(all)
    })

    apiFetch(`${API}/candhis`).then(r => r.json()).then(data => {
      const b = (data.buoys || data || []).map((b: any) => ({ id: b.id, name: b.name }))
      setBuoys(b)
    }).catch(() => {})

    apiFetch(`${API}/webcams`).then(r => r.json()).then(data => {
      setWebcams((data || []).map((w: any) => ({ id: w.id, name: w.name, location: w.location || '' })))
    }).catch(() => {})
  }, [])

  const items = type === 'station' ? stations : type === 'buoy' ? buoys : webcams
  const filtered = search
    ? items.filter((i: any) => (i.name + (i.location || '') + (i.source || '')).toLowerCase().includes(search.toLowerCase()))
    : items

  const embedUrl = selectedId
    ? `${BASE_URL}/embed?${type}=${encodeURIComponent(selectedId)}&style=${style}&refresh=${refresh}`
    : ''

  const iframeCode = selectedId
    ? `<iframe src="${embedUrl}" width="${width}" height="${height}" frameborder="0" style="border-radius:16px;overflow:hidden;" loading="lazy"></iframe>`
    : ''

  const copyCode = useCallback(() => {
    if (!iframeCode) return
    navigator.clipboard.writeText(iframeCode).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }, [iframeCode])

  // Auto-adjust height based on style
  useEffect(() => {
    if (style === 'pill') setHeight(60)
    else if (style === 'minimal') setHeight(180)
    else setHeight(200)
  }, [style])

  return (
    <div className="min-h-screen p-4 md:p-8" style={{
      fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
      background: 'linear-gradient(135deg, #f0f0f5 0%, #e8eaf0 50%, #f0f0f5 100%)',
    }}>
      <div className="max-w-5xl mx-auto">
        {/* Header */}
        <div className="mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl flex items-center justify-center" style={{
              background: 'color-mix(in srgb, #007aff 12%, transparent)',
              backdropFilter: 'blur(12px) saturate(1.5)',
              boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #007aff 20%, transparent), inset 0 1px 0 rgba(255,255,255,0.3), 0 2px 8px rgba(0,122,255,0.12)',
            }}>
              <svg className="w-5 h-5 text-[#007aff]" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" />
              </svg>
            </div>
            <div>
              <h1 className="text-[24px] font-bold text-[#1c1c1e]">Widget Embed</h1>
              <p className="text-[14px] text-[#8e8e93] mt-0.5">Configurez et integrez un widget sur votre site.</p>
            </div>
          </div>
        </div>

        <div className="flex flex-col lg:flex-row gap-6">
          {/* Config panel */}
          <div className="flex-1 rounded-2xl p-5" style={{
            background: 'rgba(255,255,255,0.65)',
            backdropFilter: 'blur(40px) saturate(1.8)',
            WebkitBackdropFilter: 'blur(40px) saturate(1.8)',
            border: '0.5px solid rgba(255,255,255,0.6)',
            boxShadow: '0 4px 24px rgba(0,0,0,0.06), inset 0 1px 0 rgba(255,255,255,0.8), inset 0 0 0 0.5px rgba(255,255,255,0.4)',
          }}>
            {/* Type selector */}
            <div className="mb-4">
              <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Type</label>
              <div className="flex rounded-full p-0.5" style={{
                background: 'color-mix(in srgb, #007aff 6%, transparent)',
                backdropFilter: 'blur(12px) saturate(150%)',
                WebkitBackdropFilter: 'blur(12px) saturate(150%)',
                boxShadow: 'inset 0 0 0 1px color-mix(in srgb, #007aff 12%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15)',
              }}>
                {(['station', 'buoy', 'webcam'] as WidgetType[]).map(t => (
                  <button key={t} onClick={() => { setType(t); setSelectedId(''); setSearch('') }}
                    className="flex-1 py-2 rounded-full text-[13px] font-bold transition-all duration-200"
                    style={type === t ? {
                      background: '#007aff', color: '#fff',
                      boxShadow: '0 2px 8px rgba(0,122,255,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
                    } : { color: '#8e8e93' }}>
                    {t === 'station' ? 'Station vent' : t === 'buoy' ? 'Bouee houle' : 'Webcam'}
                  </button>
                ))}
              </div>
            </div>

            {/* Search + select */}
            <div className="mb-4">
              <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">
                {type === 'station' ? 'Station' : type === 'buoy' ? 'Bouee' : 'Webcam'}
              </label>
              <input
                type="text"
                value={search}
                onChange={e => setSearch(e.target.value)}
                placeholder="Rechercher..."
                className="w-full px-3 py-2 rounded-xl text-[14px] text-[#1c1c1e] placeholder-[#c7c7cc] glass-input mb-2"
              />
              <div className="max-h-40 overflow-y-auto rounded-xl" style={{
                border: '0.5px solid rgba(255,255,255,0.4)',
                background: 'color-mix(in srgb, var(--text-primary) 2%, transparent)',
                boxShadow: 'inset 0 1px 3px rgba(0,0,0,0.04)',
              }}>
                {filtered.slice(0, 50).map((item: any) => (
                  <button
                    key={item.id}
                    onClick={() => setSelectedId(item.id)}
                    className="w-full text-left px-3 py-2 text-[13px] glass-list-row transition-all"
                    style={selectedId === item.id ? {
                      background: 'color-mix(in srgb, #007aff 8%, transparent)',
                      color: '#007aff',
                      fontWeight: 700,
                      boxShadow: 'inset 3px 0 0 #007aff',
                    } : { color: '#1c1c1e' }}
                  >
                    {item.name}
                    {item.source && <span className="text-[10px] text-[#8e8e93] ml-2">{item.source}</span>}
                    {item.location && <span className="text-[10px] text-[#8e8e93] ml-2">{item.location}</span>}
                  </button>
                ))}
                {filtered.length === 0 && (
                  <div className="px-3 py-4 text-center text-[12px] text-[#c7c7cc]">Aucun resultat</div>
                )}
              </div>
            </div>

            {/* Style */}
            <div className="mb-4">
              <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Style</label>
              <div className="flex rounded-full p-0.5" style={{
                background: 'color-mix(in srgb, #af52de 6%, transparent)',
                backdropFilter: 'blur(12px) saturate(150%)',
                WebkitBackdropFilter: 'blur(12px) saturate(150%)',
                boxShadow: 'inset 0 0 0 1px color-mix(in srgb, #af52de 12%, transparent), inset 0 1px 0 0 rgba(255,255,255,0.15)',
              }}>
                {(['card', 'dark', 'pill', 'minimal'] as WidgetStyle[]).map(s => (
                  <button key={s} onClick={() => setStyle(s)}
                    className="flex-1 py-1.5 rounded-full text-[12px] font-bold transition-all duration-200"
                    style={style === s ? {
                      background: '#af52de', color: '#fff',
                      boxShadow: '0 2px 8px rgba(175,82,222,0.35), inset 0 1px 0 rgba(255,255,255,0.25)',
                    } : { color: '#8e8e93' }}>
                    {s === 'card' ? 'Carte' : s === 'dark' ? 'Sombre' : s === 'pill' ? 'Pilule' : 'Minimal'}
                  </button>
                ))}
              </div>
            </div>

            {/* Dimensions */}
            <div className="flex gap-3 mb-4">
              <div className="flex-1">
                <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Largeur (px)</label>
                <input type="number" value={width} onChange={e => setWidth(Number(e.target.value))}
                  className="w-full px-3 py-2 rounded-xl text-[14px] text-[#1c1c1e] tabular-nums glass-input" />
              </div>
              <div className="flex-1">
                <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Hauteur (px)</label>
                <input type="number" value={height} onChange={e => setHeight(Number(e.target.value))}
                  className="w-full px-3 py-2 rounded-xl text-[14px] text-[#1c1c1e] tabular-nums glass-input" />
              </div>
              <div className="flex-1">
                <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Refresh (s)</label>
                <input type="number" value={refresh} onChange={e => setRefresh(Number(e.target.value))} min={30}
                  className="w-full px-3 py-2 rounded-xl text-[14px] text-[#1c1c1e] tabular-nums glass-input" />
              </div>
            </div>

            {/* Code output */}
            {selectedId && (
              <div>
                <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Code iframe</label>
                <div className="relative">
                  <pre className="text-[#34c759] text-[12px] p-3 rounded-xl overflow-x-auto font-mono leading-relaxed" style={{
                    background: 'rgba(28,28,30,0.9)',
                    backdropFilter: 'blur(16px) saturate(1.5)',
                    WebkitBackdropFilter: 'blur(16px) saturate(1.5)',
                    boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.08), inset 0 1px 0 rgba(255,255,255,0.04), 0 4px 16px rgba(0,0,0,0.12)',
                  }}>
                    {iframeCode}
                  </pre>
                  <button onClick={copyCode}
                    className="absolute top-2 right-2 px-3 py-1 rounded-full text-[11px] font-bold transition-all duration-200 active:scale-95"
                    style={{
                      color: copied ? '#fff' : '#34c759',
                      background: copied ? '#34c759' : 'color-mix(in srgb, #34c759 15%, transparent)',
                      backdropFilter: 'blur(12px) saturate(150%)',
                      WebkitBackdropFilter: 'blur(12px) saturate(150%)',
                      boxShadow: copied
                        ? '0 2px 8px rgba(52,199,89,0.4), inset 0 1px 0 rgba(255,255,255,0.25)'
                        : 'inset 0 0 0 1px color-mix(in srgb, #34c759 25%, transparent), inset 0 1px 0 rgba(255,255,255,0.1)',
                    }}>
                    {copied ? 'Copie !' : 'Copier'}
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Preview panel */}
          <div className="lg:w-96">
            <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Apercu</label>
            <div className="rounded-2xl p-4 flex items-center justify-center min-h-[250px]" style={{
              background: 'rgba(255,255,255,0.55)',
              backdropFilter: 'blur(40px) saturate(1.8)',
              WebkitBackdropFilter: 'blur(40px) saturate(1.8)',
              border: '0.5px solid rgba(255,255,255,0.6)',
              boxShadow: '0 4px 24px rgba(0,0,0,0.06), inset 0 1px 0 rgba(255,255,255,0.8), inset 0 0 0 0.5px rgba(255,255,255,0.4)',
            }}>
              {selectedId ? (
                <iframe
                  src={embedUrl}
                  width={Math.min(width, 350)}
                  height={height}
                  style={{ border: 'none', borderRadius: 16, overflow: 'hidden' }}
                  loading="lazy"
                />
              ) : (
                <div className="text-center py-8">
                  <div className="w-14 h-14 mx-auto mb-3 rounded-2xl flex items-center justify-center" style={{
                    background: 'color-mix(in srgb, #c7c7cc 10%, transparent)',
                    boxShadow: 'inset 0 0 0 0.5px rgba(199,199,204,0.2), inset 0 1px 0 rgba(255,255,255,0.3)',
                  }}>
                    <svg className="w-7 h-7 text-[#c7c7cc]" fill="none" stroke="currentColor" strokeWidth="1.5" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" />
                    </svg>
                  </div>
                  <p className="text-[14px] text-[#8e8e93]">Selectionnez un element<br />pour voir l&apos;apercu</p>
                </div>
              )}
            </div>

            {/* Quick presets */}
            {selectedId && (
              <div className="mt-3">
                <label className="text-[11px] font-bold text-[#8e8e93] uppercase tracking-wider mb-1.5 block">Presets taille</label>
                <div className="flex gap-1.5">
                  {[
                    { label: 'Sidebar', w: 280, h: 200 },
                    { label: 'Banner', w: 600, h: 80 },
                    { label: 'Carre', w: 300, h: 300 },
                    { label: 'Mobile', w: 350, h: 200 },
                  ].map(p => (
                    <button key={p.label} onClick={() => { setWidth(p.w); setHeight(p.h) }}
                      className="flex-1 py-1.5 rounded-full text-[11px] font-bold transition-all duration-200 active:scale-95"
                      style={{
                        color: '#007aff',
                        background: 'color-mix(in srgb, #007aff 8%, transparent)',
                        backdropFilter: 'blur(8px) saturate(150%)',
                        WebkitBackdropFilter: 'blur(8px) saturate(150%)',
                        boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #007aff 18%, transparent), inset 0 1px 0 rgba(255,255,255,0.15)',
                      }}>
                      {p.label}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Back to map */}
            <div className="mt-4">
              <a href="/map"
                className="flex items-center justify-center gap-2 py-2.5 rounded-full text-[13px] font-bold transition-all duration-200 active:scale-[0.98]"
                style={{
                  color: '#007aff',
                  background: 'color-mix(in srgb, #007aff 6%, transparent)',
                  backdropFilter: 'blur(12px) saturate(150%)',
                  WebkitBackdropFilter: 'blur(12px) saturate(150%)',
                  boxShadow: 'inset 0 0 0 0.5px color-mix(in srgb, #007aff 15%, transparent), inset 0 1px 0 rgba(255,255,255,0.2)',
                }}>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M15 19l-7-7 7-7" /></svg>
                Retour a la carte
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
