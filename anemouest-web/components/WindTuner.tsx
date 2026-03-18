'use client'

import { useState, useEffect } from 'react'
import type { WindGL, WindGLParams } from '@/lib/wind-gl'
import { DEFAULT_PARAMS } from '@/lib/wind-gl'

interface WindTunerProps {
  windGL: WindGL | null
  map?: any
}

export default function WindTuner({ windGL, map }: WindTunerProps) {
  const [params, setParams] = useState<WindGLParams>({ ...DEFAULT_PARAMS })
  const [collapsed, setCollapsed] = useState(false)
  const [visible, setVisible] = useState(false)

  // Only show tuner if ?tuner=1 in URL
  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search)
    setVisible(urlParams.get('tuner') === '1')
  }, [])

  // Sync params to WindGL instance + coastline layer
  useEffect(() => {
    if (windGL) {
      windGL.params = { ...params }
    }
    if (map && map.getLayer('wind-coastline')) {
      try {
        map.setPaintProperty('wind-coastline', 'line-width', params.coastlineWidth)
        map.setPaintProperty('wind-coastline', 'line-opacity', params.coastlineOpacity)
      } catch {}
    }
  }, [windGL, map, params])

  const update = (key: keyof WindGLParams, value: number | boolean) => {
    setParams(prev => ({ ...prev, [key]: value }))
  }

  const exportParams = () => {
    const txt = JSON.stringify(params, null, 2)
    navigator.clipboard.writeText(txt)
    alert('Parametres copies dans le presse-papier !\n\n' + txt)
  }

  if (!visible || !windGL) return null

  if (collapsed) {
    return (
      <button
        onClick={() => setCollapsed(false)}
        className="fixed top-20 right-4 z-50 bg-black/80 text-white px-3 py-1.5 rounded-lg text-xs backdrop-blur"
      >
        Tuner
      </button>
    )
  }

  return (
    <div className="fixed top-20 right-4 z-50 bg-black/90 text-white p-4 rounded-xl backdrop-blur w-72 text-xs space-y-3 max-h-[80vh] overflow-y-auto">
      <div className="flex justify-between items-center">
        <span className="font-bold text-sm">Wind Tuner</span>
        <button onClick={() => setCollapsed(true)} className="text-white/60 hover:text-white">_</button>
      </div>

      <div className="text-white/40 text-[10px] uppercase tracking-wider pt-1">Particules</div>
      <Slider label="Nombre" value={params.numParticles} min={500} max={30000} step={500}
        onChange={v => update('numParticles', v)} />
      <Slider label="Vitesse" value={params.speedFactor} min={0.00001} max={0.0003} step={0.00001}
        display={v => (v * 100000).toFixed(0)}
        onChange={v => update('speedFactor', v)} />
      <Slider label="Respawn" value={params.respawnRate} min={0.001} max={0.05} step={0.001}
        display={v => (v * 1000).toFixed(0)}
        onChange={v => update('respawnRate', v)} />

      <div className="text-white/40 text-[10px] uppercase tracking-wider pt-1">Trainees</div>
      <Slider label="Fondu" value={params.fadeOpacity} min={0.8} max={0.995} step={0.005}
        display={v => (v * 100).toFixed(1) + '%'}
        onChange={v => update('fadeOpacity', v)} />
      <Slider label="Taille" value={params.pointSize} min={0.5} max={6} step={0.25}
        onChange={v => update('pointSize', v)} />
      <Slider label="Opacite" value={params.particleAlpha} min={0.1} max={1} step={0.05}
        onChange={v => update('particleAlpha', v)} />

      <div className="text-white/40 text-[10px] uppercase tracking-wider pt-1">Couleur</div>
      <Toggle label="Couleur par vitesse" value={params.colorBySpeed}
        onChange={v => update('colorBySpeed', v)} />
      <Toggle label="Zoom adaptatif" value={params.zoomAdaptive}
        onChange={v => update('zoomAdaptive', v)} />

      <div className="text-white/40 text-[10px] uppercase tracking-wider pt-1">Heatmap</div>
      <Slider label="Opacite" value={params.heatmapOpacity} min={0} max={1} step={0.05}
        onChange={v => update('heatmapOpacity', v)} />

      <div className="text-white/40 text-[10px] uppercase tracking-wider pt-1">Cote</div>
      <Slider label="Epaisseur" value={params.coastlineWidth} min={0} max={3} step={0.25}
        onChange={v => update('coastlineWidth', v)} />
      <Slider label="Opacite" value={params.coastlineOpacity} min={0} max={1} step={0.05}
        onChange={v => update('coastlineOpacity', v)} />

      <button
        onClick={exportParams}
        className="w-full bg-blue-600 hover:bg-blue-500 text-white py-1.5 rounded-lg text-xs font-medium"
      >
        Copier les parametres
      </button>
    </div>
  )
}

function Slider({ label, value, min, max, step, onChange, display }: {
  label: string, value: number, min: number, max: number, step: number,
  onChange: (v: number) => void, display?: (v: number) => string
}) {
  return (
    <div>
      <div className="flex justify-between mb-1">
        <span className="text-white/70">{label}</span>
        <span className="text-white/90 font-mono">{display ? display(value) : value}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={e => onChange(parseFloat(e.target.value))}
        className="w-full h-1.5 rounded-full appearance-none bg-white/20 accent-blue-500" />
    </div>
  )
}

function Toggle({ label, value, onChange }: {
  label: string, value: boolean, onChange: (v: boolean) => void
}) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-white/70">{label}</span>
      <button
        onClick={() => onChange(!value)}
        className={`w-8 h-4 rounded-full transition-colors ${value ? 'bg-blue-500' : 'bg-white/20'}`}
      >
        <div className={`w-3 h-3 rounded-full bg-white transition-transform mx-0.5 ${value ? 'translate-x-3.5' : ''}`} />
      </button>
    </div>
  )
}
