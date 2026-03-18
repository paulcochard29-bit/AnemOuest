'use client'

import Link from 'next/link'
import { useState, useEffect, useRef, useCallback, ReactNode, Children } from 'react'
import { getWindColor } from '@/lib/utils'
import { API, apiFetch } from '@/lib/api'
const SOURCES = ['windcornouaille', 'pioupiou', 'gowind', 'meteofrance', 'diabox']

interface Station {
  wind: number
  gust?: number
  direction?: number
  name?: string
  isOnline?: boolean
}

function useLiveStats() {
  const [stats, setStats] = useState<{
    stations: number
    maxWind: number
    maxGust: number
    maxStation: string
    webcams: number
    buoys: number
    topStations: { name: string; wind: number; gust: number }[]
  } | null>(null)

  useEffect(() => {
    (async () => {
      try {
        const [webcamsRes, buoysRes, ...stationRes] = await Promise.all([
          apiFetch(`${API}/webcams`).then(r => r.ok ? r.json() : null).catch(() => null),
          apiFetch(`${API}/candhis`).then(r => r.ok ? r.json() : null).catch(() => null),
          ...SOURCES.map(s => apiFetch(`${API}/${s}`, { cache: 'no-store' }).then(r => r.ok ? r.json() : null).catch(() => null)),
        ])
        const all: Station[] = []
        stationRes.forEach((d: any) => { if (d?.stations) all.push(...d.stations) })
        const online = all.filter((s: any) => s.isOnline !== false)
        const sorted = [...online].sort((a, b) => (b.wind || 0) - (a.wind || 0))
        const top = sorted.slice(0, 5).map(s => ({
          name: (s as any).name || 'Station',
          wind: Math.round(s.wind || 0),
          gust: Math.round((s as any).gust || s.wind || 0),
        }))
        const max = sorted[0]

        setStats({
          stations: online.length,
          maxWind: max ? Math.round(max.wind) : 0,
          maxGust: max ? Math.round((max as any).gust || max.wind) : 0,
          maxStation: max ? (max as any).name || '' : '',
          webcams: Array.isArray(webcamsRes) ? webcamsRes.length : webcamsRes?.webcams?.length || 0,
          buoys: Array.isArray(buoysRes) ? buoysRes.length : buoysRes?.buoys?.length || 0,
          topStations: top,
        })
      } catch {}
    })()
  }, [])
  return stats
}

function AnimatedCounter({ value, suffix = '' }: { value: number; suffix?: string }) {
  const [display, setDisplay] = useState(0)

  useEffect(() => {
    if (!value) return
    const duration = 1200
    const start = performance.now()
    const animate = (now: number) => {
      const progress = Math.min((now - start) / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      setDisplay(Math.round(eased * value))
      if (progress < 1) requestAnimationFrame(animate)
    }
    requestAnimationFrame(animate)
  }, [value])

  return <span>{display}{suffix}</span>
}

function MeshBackground() {
  return (
    <div className="fixed inset-0 -z-10 overflow-hidden" style={{ background: 'var(--bg-primary)' }}>
      <div
        className="absolute w-[600px] h-[600px] rounded-full -top-[10%] -left-[5%] animate-drift1"
        style={{ background: 'radial-gradient(circle, var(--mesh-1), transparent 70%)', filter: 'blur(80px)' }}
      />
      <div
        className="absolute w-[500px] h-[500px] rounded-full top-[20%] -right-[10%] animate-drift2"
        style={{ background: 'radial-gradient(circle, var(--mesh-2), transparent 70%)', filter: 'blur(80px)' }}
      />
      <div
        className="absolute w-[400px] h-[400px] rounded-full bottom-[10%] left-[30%] animate-drift3"
        style={{ background: 'radial-gradient(circle, var(--mesh-3), transparent 70%)', filter: 'blur(80px)' }}
      />
      <div
        className="absolute w-[350px] h-[350px] rounded-full bottom-[30%] right-[20%] animate-drift4"
        style={{ background: 'radial-gradient(circle, var(--mesh-4), transparent 70%)', filter: 'blur(80px)' }}
      />
    </div>
  )
}

function WindParticles() {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    let animId: number
    const particles: { x: number; y: number; vx: number; vy: number; size: number; alpha: number; life: number; hue: number }[] = []
    const NUM = 40

    const resize = () => {
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight * 0.85
    }
    resize()
    window.addEventListener('resize', resize)

    const isDark = document.documentElement.getAttribute('data-theme') === 'dark'

    for (let i = 0; i < NUM; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        vx: 0.2 + Math.random() * 0.8,
        vy: -0.15 + Math.random() * 0.3,
        size: 1 + Math.random() * 2.5,
        alpha: 0.08 + Math.random() * 0.2,
        life: Math.random(),
        hue: 200 + Math.random() * 60,
      })
    }

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      for (const p of particles) {
        p.x += p.vx
        p.y += p.vy
        p.life += 0.002
        if (p.x > canvas.width + 10) { p.x = -10; p.y = Math.random() * canvas.height }
        const a = p.alpha * (0.5 + 0.5 * Math.sin(p.life * Math.PI * 2))
        ctx.beginPath()
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2)
        if (isDark) {
          ctx.fillStyle = `rgba(255,255,255,${a})`
        } else {
          ctx.fillStyle = `hsla(${p.hue},60%,70%,${a})`
        }
        ctx.fill()
      }
      animId = requestAnimationFrame(draw)
    }
    draw()

    return () => {
      cancelAnimationFrame(animId)
      window.removeEventListener('resize', resize)
    }
  }, [])

  return <canvas ref={canvasRef} className="absolute inset-0 pointer-events-none" />
}

function RevealGroup({ children, className }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [revealed, setRevealed] = useState(false)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([e]) => { if (e.isIntersecting) { setRevealed(true); obs.disconnect() } },
      { threshold: 0.1 }
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [])

  return (
    <div ref={ref} className={className}>
      {Children.map(children, (child, i) => (
        <div
          className={revealed ? 'glass-reveal' : 'opacity-0'}
          style={{ animationDelay: `${i * 80}ms` }}
        >
          {child}
        </div>
      ))}
    </div>
  )
}

const FEATURES = [
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M9.5 4C7.57 4 6 5.57 6 7.5h2c0-.83.67-1.5 1.5-1.5S11 6.67 11 7.5 10.33 8.5 9.5 8.5H2v2h7.5C11.43 10.5 13 8.93 13 7" />
        <path d="M18.5 11H2" />
        <path d="M14.5 17c0 1.65-1.35 3-3 3s-3-1.35-3-3h2c0 .55.45 1 1 1s1-.45 1-1-.45-1-1-1H2" />
      </svg>
    ),
    title: 'Vent temps reel',
    desc: '1 000+ stations, 6 sources',
    color: '#007aff',
  },
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 12c2-3 4-4 6-4s4 1 6 4 4 4 6 4" />
        <path d="M2 17c2-3 4-4 6-4s4 1 6 4 4 4 6 4" opacity="0.4" />
        <path d="M2 7c2-3 4-4 6-4s4 1 6 4 4 4 6 4" opacity="0.4" />
      </svg>
    ),
    title: 'Houle & marees',
    desc: 'Bouees CANDHIS, predictions',
    color: '#34c759',
  },
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="4" width="20" height="14" rx="3" />
        <circle cx="12" cy="11" r="3" />
        <path d="M12 21l-4-3h8l-4 3z" />
      </svg>
    ),
    title: 'Webcams live',
    desc: 'HLS streaming, timeline 48h',
    color: '#af52de',
  },
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
        <circle cx="12" cy="10" r="3" />
      </svg>
    ),
    title: '500+ spots',
    desc: 'Kite, surf, wing, parapente',
    color: '#ff9500',
  },
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
        <circle cx="12" cy="12" r="4" />
      </svg>
    ),
    title: 'Previsions',
    desc: 'AROME, ECMWF, GFS',
    color: '#ff3b30',
  },
  {
    icon: (
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z" />
      </svg>
    ),
    title: 'Radar pluie',
    desc: 'Animation temps reel',
    color: '#5ac8fa',
  },
]

export default function Home() {
  const stats = useLiveStats()
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const timer = setTimeout(() => setVisible(true), 100)
    return () => clearTimeout(timer)
  }, [])

  return (
    <div className="min-h-screen overflow-hidden relative" style={{ color: 'var(--text-primary)' }}>
      <MeshBackground />

      {/* Hero */}
      <section className="relative min-h-[85vh] flex flex-col items-center justify-center px-5">
        <WindParticles />

        <div className={`relative z-10 text-center max-w-2xl mx-auto transition-all duration-1000 ${visible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-6'}`}>
          {/* Status pill */}
          <div className="glass-status-pill inline-flex items-center gap-2 px-4 py-2 mb-8">
            <span className="w-2 h-2 rounded-full bg-[#34c759] animate-pulse" />
            <span className="text-[13px] font-medium" style={{ color: 'var(--text-secondary)' }}>
              {stats ? <><AnimatedCounter value={stats.stations} /> stations en ligne</> : 'Chargement...'}
            </span>
          </div>

          <h1 className="text-[clamp(2.5rem,8vw,4.5rem)] font-bold tracking-tight leading-[1.05] mb-4">
            Le Vent
          </h1>
          <p className="text-[clamp(1rem,3vw,1.25rem)] font-normal max-w-md mx-auto mb-10 leading-relaxed" style={{ color: 'var(--text-secondary)' }}>
            Vent, houle, webcams et spots.<br />Temps reel, partout en France.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <Link
              href="/map"
              className="glass-cta w-full sm:w-auto px-8 py-3.5 text-white font-semibold text-[17px]"
            >
              Ouvrir la carte
            </Link>
            <a
              href="https://apps.apple.com/app/le-vent/id6740806498"
              className="glass-cta-secondary w-full sm:w-auto flex items-center justify-center gap-2 px-8 py-3.5 font-semibold text-[17px]"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
              </svg>
              App iOS
            </a>
          </div>
        </div>

        {/* Scroll indicator */}
        <div className={`absolute bottom-8 left-1/2 -translate-x-1/2 transition-all duration-1000 delay-700 ${visible ? 'opacity-100' : 'opacity-0'}`}>
          <div className="w-6 h-10 rounded-full border-2 flex items-start justify-center pt-2" style={{ borderColor: 'var(--border)' }}>
            <div className="w-1 h-2.5 rounded-full animate-bounce" style={{ background: 'var(--text-tertiary)' }} />
          </div>
        </div>
      </section>

      {/* Live stats */}
      {stats && (
        <section className="relative px-5 py-20">
          <div className="max-w-5xl mx-auto">
            <RevealGroup className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Stations" value={<AnimatedCounter value={stats.stations} />} color="#007aff" />
              <StatCard
                label="Vent max"
                value={<><AnimatedCounter value={stats.maxWind} /> <span className="text-base font-medium" style={{ color: 'var(--text-tertiary)' }}>nds</span></>}
                sub={stats.maxStation}
                color={getWindColor(stats.maxWind)}
              />
              <StatCard label="Webcams" value={<AnimatedCounter value={stats.webcams} />} color="#af52de" />
              <StatCard label="Bouees" value={<AnimatedCounter value={stats.buoys} />} color="#34c759" />
            </RevealGroup>

            {/* Top wind stations */}
            {stats.topStations.length > 0 && (
              <div className="mt-8 glass-landing-card overflow-hidden">
                <div className="px-5 py-3 border-b" style={{ borderColor: 'var(--separator)' }}>
                  <span className="text-[13px] font-semibold uppercase tracking-wider" style={{ color: 'var(--text-tertiary)' }}>Top vent maintenant</span>
                </div>
                {stats.topStations.map((s, i) => (
                  <div key={i} className="glass-list-row flex items-center justify-between px-5 py-3">
                    <div className="flex items-center gap-3">
                      <span
                        className="w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold"
                        style={{ background: 'var(--separator)', color: 'var(--text-tertiary)' }}
                      >
                        {i + 1}
                      </span>
                      <span className="text-[15px]" style={{ color: 'var(--text-primary)' }}>{s.name}</span>
                    </div>
                    <div className="flex items-center gap-3">
                      <span className="text-[15px] font-bold tabular-nums" style={{ color: getWindColor(s.wind) }}>{s.wind}</span>
                      <span className="text-[13px] tabular-nums" style={{ color: 'var(--text-tertiary)' }}>G{s.gust}</span>
                      <span className="text-[11px]" style={{ color: 'var(--text-tertiary)' }}>nds</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </section>
      )}

      {/* Features */}
      <section className="px-5 py-20">
        <div className="max-w-5xl mx-auto">
          <h2 className="text-[clamp(1.5rem,5vw,2.25rem)] font-bold tracking-tight text-center mb-3">
            Tout ce qu&apos;il faut
          </h2>
          <p className="text-center text-[15px] mb-12 max-w-md mx-auto" style={{ color: 'var(--text-secondary)' }}>
            Donnees meteo marine en temps reel, previsions multi-modeles et couverture webcam complete.
          </p>

          <RevealGroup className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {FEATURES.map((f) => (
              <div key={f.title} className="glass-landing-card p-5">
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center mb-4"
                  style={{ background: `${f.color}15`, color: f.color }}
                >
                  {f.icon}
                </div>
                <h3 className="text-[17px] font-semibold mb-1">{f.title}</h3>
                <p className="text-[14px] leading-relaxed" style={{ color: 'var(--text-secondary)' }}>{f.desc}</p>
              </div>
            ))}
          </RevealGroup>
        </div>
      </section>

      {/* CTA */}
      <section className="px-5 py-24">
        <div className="max-w-lg mx-auto text-center">
          <h2 className="text-[clamp(1.5rem,5vw,2rem)] font-bold tracking-tight mb-3">Pret a naviguer ?</h2>
          <p className="text-[15px] mb-8" style={{ color: 'var(--text-secondary)' }}>Gratuit, sans inscription.</p>
          <Link
            href="/map"
            className="glass-cta inline-flex px-10 py-4 text-white font-semibold text-[17px]"
          >
            Ouvrir la carte
          </Link>
        </div>
      </section>

      {/* Footer */}
      <footer className="glass-footer px-5 py-8">
        <div className="max-w-5xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <span className="text-[13px]" style={{ color: 'var(--text-tertiary)' }}>Le Vent {new Date().getFullYear()}</span>
          <div className="flex items-center gap-6">
            <Link href="/privacy" className="text-[13px] transition" style={{ color: 'var(--text-tertiary)' }}>Confidentialite</Link>
            <a href="https://apps.apple.com/app/le-vent/id6740806498" className="text-[13px] transition" style={{ color: 'var(--text-tertiary)' }}>App iOS</a>
          </div>
        </div>
      </footer>
    </div>
  )
}

function StatCard({ label, value, sub, color }: { label: string; value: ReactNode; sub?: string; color: string }) {
  return (
    <div className="glass-landing-card p-5">
      <div className="text-[11px] font-semibold uppercase tracking-wider mb-2" style={{ color: 'var(--text-tertiary)' }}>{label}</div>
      <div className="text-[28px] font-bold tabular-nums tracking-tight" style={{ color }}>{value}</div>
      {sub && <div className="text-[12px] mt-1 truncate" style={{ color: 'var(--text-tertiary)' }}>{sub}</div>}
    </div>
  )
}
