'use client'

import { useState } from 'react'
import { createPortal } from 'react-dom'

const STYLES = [
  { id: 'card', label: 'Carte', desc: 'Style glass complet', w: 320, h: 200 },
  { id: 'dark', label: 'Sombre', desc: 'Fond noir, pro', w: 320, h: 200 },
  { id: 'pill', label: 'Pilule', desc: 'Compact inline', w: 220, h: 50 },
  { id: 'minimal', label: 'Minimal', desc: 'Chiffres seuls', w: 280, h: 140 },
] as const

interface Props {
  type: 'station' | 'buoy' | 'webcam'
  id: string
}

export function EmbedPicker({ type, id }: Props) {
  const [open, setOpen] = useState(false)
  const [style, setStyle] = useState<string>('card')
  const [copied, setCopied] = useState(false)

  const s = STYLES.find(s => s.id === style) || STYLES[0]
  const base = typeof window !== 'undefined' ? window.location.origin : ''
  const embedUrl = `${base}/embed?${type}=${encodeURIComponent(id)}&style=${style}&refresh=60`
  const iframeCode = `<iframe src="${embedUrl}" width="${s.w}" height="${type === 'webcam' ? 240 : s.h}" style="border:none;border-radius:16px;overflow:hidden" loading="lazy"></iframe>`

  const handleCopy = () => {
    navigator.clipboard.writeText(iframeCode)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <>
      <button onClick={() => setOpen(true)}
        className="text-[11px] font-semibold text-[#8e8e93] px-2 py-0.5 rounded-full glass-btn flex items-center gap-1">
        <svg className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        Embed
      </button>

      {open && typeof document !== 'undefined' && createPortal(
        <div className="fixed inset-0 z-[2500] flex items-end md:items-center justify-center">
          {/* Backdrop */}
          <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" onClick={() => setOpen(false)} />

          {/* Popup */}
          <div className="relative w-full max-w-md mx-4 mb-4 md:mb-0 glass-card rounded-2xl p-4 shadow-2xl animate-in slide-in-from-bottom-4"
            style={{ background: 'rgba(255,255,255,0.92)', backdropFilter: 'blur(40px) saturate(1.8)' }}>

            {/* Header */}
            <div className="flex items-center justify-between mb-3">
              <span className="text-[13px] font-bold text-[#1c1c1e]">Widget embed</span>
              <button onClick={() => setOpen(false)} className="text-[#8e8e93] p-1 hover:bg-[#f2f2f7] rounded-lg transition">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24"><path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>

            {/* Style picker */}
            <div className="flex gap-1.5 mb-3">
              {STYLES.map(s => (
                <button key={s.id} onClick={() => setStyle(s.id)}
                  className={`flex-1 py-2 rounded-xl text-center transition ${style === s.id
                    ? 'bg-[#007aff] text-white shadow-sm'
                    : 'bg-[#f2f2f7] text-[#8e8e93] hover:bg-[#e5e5ea]'
                  }`}>
                  <div className="text-[11px] font-bold">{s.label}</div>
                  <div className="text-[9px] opacity-60 mt-0.5">{s.desc}</div>
                </button>
              ))}
            </div>

            {/* Live preview */}
            <div className="rounded-xl border border-[#e5e5ea] bg-[#f2f2f7] overflow-hidden mb-3" style={{ height: type === 'webcam' ? 200 : 140 }}>
              <iframe
                src={embedUrl}
                className="w-full h-full border-0"
                style={{ transform: 'scale(0.85)', transformOrigin: 'top left', width: '118%', height: '118%' }}
              />
            </div>

            {/* Code + copy */}
            <div className="flex gap-2">
              <div className="flex-1 bg-[#f2f2f7] rounded-lg px-2.5 py-2.5 text-[10px] font-mono text-[#636366] overflow-hidden whitespace-nowrap text-ellipsis">
                {iframeCode}
              </div>
              <button onClick={handleCopy}
                className={`px-4 py-2.5 rounded-lg text-[12px] font-bold transition active:scale-95 ${copied
                  ? 'bg-[#34c759] text-white'
                  : 'bg-[#007aff] text-white'
                }`}>
                {copied ? 'Copie !' : 'Copier'}
              </button>
            </div>

            <div className="text-[10px] text-[#c7c7cc] text-center mt-2">Auto-refresh toutes les 60s</div>
          </div>
        </div>,
        document.body
      )}
    </>
  )
}
