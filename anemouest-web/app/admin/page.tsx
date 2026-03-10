'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';

const API_BASE = 'https://anemouest-api.vercel.app/api';
const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN || 'pk.eyJ1IjoicGF1bDI5OTAwIiwiYSI6ImNta2Nvc3R6YjAzYjczZXM2Y2g3YmZkcTQifQ.CNTSppufgvTp0wQu9gKsgw';

// ============================================================
// TYPES
// ============================================================

type AdminTab = 'webcams' | 'kite' | 'surf' | 'stations' | 'config' | 'ai';

interface Webcam {
  id: string;
  name: string;
  location: string;
  region: string;
  latitude: number;
  longitude: number;
  imageUrl: string;
  streamUrl: string | null;
  source: string;
  refreshInterval: number;
  _hasOverride?: boolean;
  _isAddition?: boolean;
  _verified?: boolean;
  _verifiedAt?: string;
}

interface KiteSpot {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  orientation: string;
  level: string;
  type: string;
  waveType: string;
  supportsKite: boolean;
  supportsWindsurf: boolean;
  supportsWing: boolean;
  supportsSurf: boolean;
  tidePreference: string;
}

interface SurfSpot {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  level: string;
  waveType: string;
  bottomType: string;
  orientation: string;
  idealSwellDirMin: number;
  idealSwellDirMax: number;
  idealSwellSizeMin: number;
  idealSwellSizeMax: number;
  idealPeriodMin: number;
  idealPeriodMax: number;
  idealTide: string;
  description: string;
  hazards: string;
  crowd: string;
  consistency: number;
}

interface AppConfig {
  // Wind sources
  sourceWindCornouaille: boolean;
  sourceFFVL: boolean;
  sourcePioupiou: boolean;
  sourceHolfuy: boolean;
  sourceWindguru: boolean;
  sourceWindsUp: boolean;
  sourceMeteoFrance: boolean;
  sourceDiabox: boolean;
  sourceNDBC: boolean;
  sourceNetatmo: boolean;
  // Display
  showKiteSpots: boolean;
  showSurfSpots: boolean;
  showParaglidingSpots: boolean;
  showTideWidget: boolean;
  defaultWindUnit: string;
  defaultRefreshInterval: number;
  // Kite thresholds
  kiteMinWind: number;
  kiteMaxWind: number;
  kiteMaxGust: number;
  // Notifications
  quietHoursEnabled: boolean;
  quietHoursStart: number;
  quietHoursEnd: number;
  // Map
  defaultMapLat: number;
  defaultMapLon: number;
  defaultMapZoom: number;
  // Maintenance
  maintenanceMode: boolean;
  maintenanceMessage: string;
  // Feature flags
  enableFishing: boolean;
  enableForecasts: boolean;
  enableWebcams: boolean;
  enableWaveBuoys: boolean;
  enableRadar: boolean;
  [key: string]: unknown;
}

interface HealthStatus {
  [id: string]: {
    online: boolean;
    lastSuccess?: number;
    lastCheck?: number;
    consecutiveFailures?: number;
    lastError?: string;
  };
}

interface AISuggestion {
  id: string;
  webcamName: string;
  webcamLocation: string;
  type: 'location_mismatch' | 'image_broken' | 'image_mismatch' | 'duplicate' | 'offline_chronic' | 'url_fix';
  severity: 'high' | 'medium' | 'low';
  description: string;
  suggestion: Record<string, unknown>;
  currentValues: Record<string, unknown>;
  geocodeResult?: { lat: number; lon: number; name: string } | null;
  aiAnalysis: string;
  status: 'pending' | 'approved' | 'rejected';
  createdAt: string;
  analyzedBy: string;
}

interface WindStation {
  stableId: string;
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  wind: number;
  gust: number;
  direction: number;
  isOnline: boolean;
  source: string;
  ts?: string | null;
  altitude?: number | null;
  temperature?: number | null;
  pressure?: number | null;
  humidity?: number | null;
  description?: string | null;
  picture?: string | null;
  region?: string | null;
  tags?: string | null;
  _hidden?: boolean;
  _hasOverride?: boolean;
  _isAddition?: boolean;
  _notes?: string | null;
  _priority?: number;
  _associatedWebcamId?: string | null;
  _associatedKiteSpotId?: string | null;
  _customOnlineThreshold?: number | null;
}

interface StationStats {
  total: number;
  online: number;
  offline: number;
  withOverride: number;
  additions: number;
  sources: Record<string, number>;
}

interface StationAiSuggestion {
  id: string;
  type: 'duplicate' | 'chronic_offline' | 'suspicious_data' | 'data_anomaly' | 'location_anomaly' | 'missing_metadata';
  severity: 'high' | 'medium' | 'low';
  stableId: string;
  stationName: string;
  description: string;
  suggestion: Record<string, unknown>;
  currentValues: Record<string, unknown>;
  analysis: string;
  status: 'pending' | 'approved' | 'rejected';
  createdAt: string;
}

interface WebcamWeatherData {
  webcamId: string;
  webcamName: string;
  location: string;
  weather: 'sunny' | 'partly_cloudy' | 'cloudy' | 'overcast' | 'rainy' | 'foggy' | 'stormy' | 'unknown';
  sea_state: 'flat' | 'small' | 'medium' | 'big' | 'rough' | 'not_visible';
  visibility: 'excellent' | 'good' | 'moderate' | 'poor' | 'night';
  crowd: 'empty' | 'few' | 'moderate' | 'crowded' | 'not_visible';
  wind_signs: 'calm' | 'light' | 'moderate' | 'strong' | 'unknown';
  confidence: number;
  notes?: string;
  analyzedAt: string;
}

// ============================================================
// CONSTANTS
// ============================================================

const REGIONS = [
  'Tous', 'Bretagne', 'Normandie', 'Hauts-de-France', 'Pays de la Loire',
  'Nouvelle-Aquitaine', 'Occitanie', 'Provence-Alpes-Cote d\'Azur', 'Corse',
  'Grand Est', 'Bourgogne-Franche-Comte'
];

const WEBCAM_SOURCES = ['Tous', 'Skaping', 'Viewsurf', 'Vision-Env', 'Diabox', 'WindsUp', 'YouTube'];

const KITE_LEVELS = ['Debutant', 'Intermediaire', 'Confirme', 'Expert'];
const KITE_TYPES = ['Plage', 'Lagune', 'Riviere', 'Lac'];
const KITE_WAVE_TYPES = ['Flat', 'Petit', 'Moyen', 'Gros', 'Inconnu'];
const KITE_TIDE_PREFS = ['all', 'high', 'low', 'mid', 'avoidHigh', 'avoidLow'];
const KITE_TIDE_LABELS: Record<string, string> = {
  all: 'Toutes marees', high: 'Maree haute', low: 'Maree basse',
  mid: 'Mi-maree', avoidHigh: 'Eviter haute', avoidLow: 'Eviter basse'
};

const SURF_LEVELS = ['Debutant', 'Intermediaire', 'Confirme', 'Expert'];
const SURF_WAVE_TYPES = ['Beach Break', 'Reef Break', 'Point Break', 'Embouchure', 'Shore Break'];
const SURF_BOTTOM_TYPES = ['Sable', 'Rochers', 'Recif', 'Mixte'];
const SURF_TIDE_PREFS = ['Maree basse', 'Mi-maree', 'Maree haute', 'Toutes marees'];
const SURF_CROWD_LEVELS = ['Desert', 'Peu frequente', 'Modere', 'Frequente', 'Tres frequente'];

const WIND_UNITS = ['knots', 'km/h', 'm/s', 'mph'];
const REFRESH_INTERVALS = [
  { value: 5, label: '5s' }, { value: 10, label: '10s' }, { value: 20, label: '20s' },
  { value: 30, label: '30s' }, { value: 60, label: '1min' }, { value: 120, label: '2min' },
  { value: 300, label: '5min' }
];

const WIND_DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

const WIND_SOURCES = ['Tous', 'meteofrance', 'windcornouaille', 'pioupiou', 'holfuy', 'windguru', 'windsup', 'diabox', 'ffvl', 'ndbc', 'netatmo', 'custom'];
const WIND_SOURCE_COLORS: Record<string, string> = {
  meteofrance: '#3b82f6',
  windcornouaille: '#6366f1',
  pioupiou: '#f97316',
  holfuy: '#22c55e',
  windguru: '#14b8a6',
  windsup: '#8b5cf6',
  diabox: '#ec4899',
  ffvl: '#eab308',
  ndbc: '#0ea5e9',
  netatmo: '#f43f5e',
  custom: '#a855f7',
};
const WIND_SOURCE_LABELS: Record<string, string> = {
  meteofrance: 'Meteo France',
  windcornouaille: 'WindCornouaille',
  pioupiou: 'Pioupiou',
  holfuy: 'Holfuy',
  windguru: 'Windguru',
  windsup: 'WindsUp',
  diabox: 'Diabox',
  ffvl: 'FFVL',
  ndbc: 'NDBC (Bouées)',
  netatmo: 'Netatmo',
  custom: 'Custom',
};
const STATION_STATUS_FILTERS = ['Tous', 'Online', 'Offline', 'Modifie', 'Masque', 'Custom'];

const DEFAULT_CONFIG: AppConfig = {
  sourceWindCornouaille: true, sourceFFVL: true, sourcePioupiou: true,
  sourceHolfuy: true, sourceWindguru: true, sourceWindsUp: false,
  sourceMeteoFrance: true, sourceDiabox: true,
  sourceNDBC: true, sourceNetatmo: true,
  showKiteSpots: true, showSurfSpots: true, showParaglidingSpots: true,
  showTideWidget: true, defaultWindUnit: 'knots', defaultRefreshInterval: 20,
  kiteMinWind: 12, kiteMaxWind: 35, kiteMaxGust: 45,
  quietHoursEnabled: false, quietHoursStart: 22, quietHoursEnd: 7,
  defaultMapLat: 47.8, defaultMapLon: -3.5, defaultMapZoom: 6,
  maintenanceMode: false, maintenanceMessage: '',
  enableFishing: true, enableForecasts: true, enableWebcams: true,
  enableWaveBuoys: true, enableRadar: true
};

// ============================================================
// UTILITY FUNCTIONS
// ============================================================

function extractYouTubeId(input: string): string {
  try {
    const url = new URL(input);
    if (url.hostname.includes('youtube.com')) {
      if (url.pathname.startsWith('/embed/')) return url.pathname.split('/embed/')[1].split(/[?&]/)[0];
      if (url.pathname.startsWith('/live/')) return url.pathname.split('/live/')[1].split(/[?&]/)[0];
      return url.searchParams.get('v') || input;
    }
    if (url.hostname === 'youtu.be') return url.pathname.slice(1).split(/[?&]/)[0];
  } catch { /* not a URL */ }
  return input;
}

function buildImageUrl(source: string, param: string): string {
  switch (source) {
    case 'Skaping': {
      // Support server prefix: "data3:path/to/webcam" or just "path/to/webcam"
      const serverMatch = param.match(/^(data\d*):(.+)$/);
      if (serverMatch) {
        return `${API_BASE}/skaping?path=${encodeURIComponent(serverMatch[2])}&server=${serverMatch[1]}`;
      }
      return `${API_BASE}/skaping?path=${encodeURIComponent(param)}`;
    }
    case 'Viewsurf': return `${API_BASE}/viewsurf?id=${param}`;
    case 'Vision-Env': return `${API_BASE}/vision?slug=${param}`;
    case 'YouTube': {
      const vid = extractYouTubeId(param);
      return `https://img.youtube.com/vi/${vid}/maxresdefault.jpg`;
    }
    default: return param;
  }
}

function extractSourceParam(source: string, imageUrl: string): string {
  try {
    if (source === 'YouTube') {
      const match = imageUrl.match(/img\.youtube\.com\/vi\/([^/]+)/);
      return match ? match[1] : imageUrl;
    }
    const url = new URL(imageUrl);
    switch (source) {
      case 'Skaping': {
        const p = url.searchParams.get('path') || '';
        const srv = url.searchParams.get('server');
        return srv && srv !== 'data' ? `${srv}:${p}` : p;
      }
      case 'Viewsurf': return url.searchParams.get('id') || '';
      case 'Vision-Env': return url.searchParams.get('slug') || '';
      default: return imageUrl;
    }
  } catch {
    return imageUrl;
  }
}

// ============================================================
// SHARED COMPONENTS
// ============================================================

function Field({
  label, value, onChange, type = 'text', readonly = false, placeholder = ''
}: {
  label: string; value: string; onChange?: (v: string) => void; type?: string; readonly?: boolean; placeholder?: string;
}) {
  return (
    <div>
      <label className="text-white/50 text-xs mb-1 block">{label}</label>
      <input
        type={type}
        value={value}
        onChange={e => onChange?.(e.target.value)}
        readOnly={readonly}
        placeholder={placeholder}
        step={type === 'number' ? '0.0001' : undefined}
        className={`w-full p-2 rounded bg-[#2a2a2a] text-white text-sm border border-white/10 outline-none focus:border-cyan-500 ${readonly ? 'opacity-50' : ''}`}
      />
    </div>
  );
}

function Select({
  label, value, options, onChange, labelMap
}: {
  label: string; value: string; options: string[]; onChange: (v: string) => void; labelMap?: Record<string, string>;
}) {
  return (
    <div>
      <label className="text-white/50 text-xs mb-1 block">{label}</label>
      <select
        value={value}
        onChange={e => onChange(e.target.value)}
        className="w-full p-2 rounded bg-[#2a2a2a] text-white text-sm border border-white/10"
      >
        {options.map(o => (
          <option key={o} value={o}>{labelMap ? labelMap[o] || o : o}</option>
        ))}
      </select>
    </div>
  );
}

function Toggle({
  label, value, onChange, description
}: {
  label: string; value: boolean; onChange: (v: boolean) => void; description?: string;
}) {
  return (
    <div
      className="flex items-center justify-between p-2.5 rounded-lg bg-[#2a2a2a] border border-white/10 cursor-pointer hover:border-white/20 transition"
      onClick={() => onChange(!value)}
    >
      <div>
        <span className="text-white text-sm">{label}</span>
        {description && <p className="text-white/30 text-xs mt-0.5">{description}</p>}
      </div>
      <div className={`w-10 h-5 rounded-full transition relative ${value ? 'bg-cyan-600' : 'bg-white/10'}`}>
        <div className={`absolute top-0.5 w-4 h-4 rounded-full bg-white transition-all ${value ? 'left-5' : 'left-0.5'}`} />
      </div>
    </div>
  );
}

function DirectionPicker({
  label, value, onChange
}: {
  label: string; value: string; onChange: (v: string) => void;
}) {
  const selected = value ? value.split(',').map(s => s.trim()) : [];
  return (
    <div>
      <label className="text-white/50 text-xs mb-1 block">{label}</label>
      <div className="flex flex-wrap gap-1">
        {WIND_DIRECTIONS.map(d => (
          <button
            key={d}
            type="button"
            onClick={() => {
              const next = selected.includes(d)
                ? selected.filter(s => s !== d)
                : [...selected, d];
              onChange(next.join(','));
            }}
            className={`px-2 py-1 rounded text-xs transition ${
              selected.includes(d)
                ? 'bg-cyan-700 text-white'
                : 'bg-[#2a2a2a] text-white/40 hover:text-white'
            }`}
          >
            {d}
          </button>
        ))}
      </div>
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <h3 className="text-white/60 text-xs font-semibold uppercase tracking-wider mt-4 mb-2">{children}</h3>;
}

// ============================================================
// LOGIN GATE
// ============================================================

function LoginGate({ onLogin }: { onLogin: (pw: string) => void }) {
  const [pw, setPw] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const res = await fetch(`${API_BASE}/admin/webcams`, {
        headers: { Authorization: `Bearer ${pw}` }
      });
      if (res.ok) {
        sessionStorage.setItem('admin_pw', pw);
        onLogin(pw);
      } else {
        setError('Mot de passe incorrect');
      }
    } catch {
      setError('Erreur de connexion');
    }
    setLoading(false);
  }

  return (
    <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center">
      <form onSubmit={handleLogin} className="bg-[#1a1a1a] p-8 rounded-2xl border border-white/10 w-96">
        <h1 className="text-xl font-bold text-white mb-6">Admin AnemOuest</h1>
        <input
          type="password"
          value={pw}
          onChange={e => setPw(e.target.value)}
          placeholder="Mot de passe"
          className="w-full p-3 rounded-lg bg-[#2a2a2a] text-white border border-white/10 focus:border-cyan-500 outline-none mb-4"
          autoFocus
        />
        {error && <p className="text-red-400 text-sm mb-4">{error}</p>}
        <button
          type="submit"
          disabled={loading || !pw}
          className="w-full p-3 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white font-semibold disabled:opacity-50 transition"
        >
          {loading ? 'Connexion...' : 'Connexion'}
        </button>
      </form>
    </div>
  );
}

// ============================================================
// WEBCAM COMPONENTS
// ============================================================

function isYouTubeUrl(url: string): boolean {
  return url.includes('youtube.com') || url.includes('youtu.be');
}

function StreamPlayer({ url }: { url: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<{ destroy: () => void } | null>(null);
  const [error, setError] = useState('');
  const [playing, setPlaying] = useState(false);
  const isYT = isYouTubeUrl(url);

  useEffect(() => {
    if (!playing || isYT) return;
    const video = videoRef.current;
    if (!video) return;
    setError('');
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = url;
      video.play().catch(e => setError(e.message));
      return;
    }
    let hls: { destroy: () => void } | null = null;
    import('hls.js').then(({ default: Hls }) => {
      if (!Hls.isSupported()) { setError('HLS non supporte'); return; }
      const instance = new Hls({ enableWorker: false });
      hls = instance;
      hlsRef.current = instance;
      instance.loadSource(url);
      instance.attachMedia(video);
      instance.on(Hls.Events.MANIFEST_PARSED, () => { video.play().catch(e => setError(e.message)); });
      instance.on(Hls.Events.ERROR, (_: unknown, data: { fatal: boolean; details: string }) => {
        if (data.fatal) setError(`Erreur stream: ${data.details}`);
      });
    }).catch(() => setError('hls.js introuvable'));
    return () => { if (hls) (hls as { destroy: () => void }).destroy(); hlsRef.current = null; };
  }, [playing, url, isYT]);

  function handleStop() {
    setPlaying(false); setError('');
    if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
  }

  function getYouTubeEmbedUrl(): string {
    if (url.includes('/embed/')) return url;
    return `https://www.youtube.com/embed/${extractYouTubeId(url)}?autoplay=1&mute=1`;
  }

  return (
    <div className="rounded-lg overflow-hidden bg-[#2a2a2a]">
      {!playing ? (
        <button onClick={() => setPlaying(true)}
          className="w-full p-3 flex items-center justify-center gap-2 text-cyan-400 hover:text-cyan-300 text-xs transition">
          <span>&#9654;</span> {isYT ? 'Voir le live YouTube' : 'Tester le stream'}
        </button>
      ) : isYT ? (
        <div className="relative">
          <iframe src={getYouTubeEmbedUrl()} className="w-full aspect-video bg-black"
            allow="autoplay; encrypted-media" allowFullScreen />
          <button onClick={handleStop}
            className="absolute top-1 right-1 bg-black/60 text-white text-xs px-2 py-0.5 rounded hover:bg-black/80 z-10">Fermer</button>
        </div>
      ) : (
        <div className="relative">
          <video ref={videoRef} className="w-full aspect-video bg-black" controls muted playsInline autoPlay />
          <button onClick={handleStop}
            className="absolute top-1 right-1 bg-black/60 text-white text-xs px-2 py-0.5 rounded hover:bg-black/80">Fermer</button>
        </div>
      )}
      {error && <p className="text-red-400 text-[10px] p-2">{error}</p>}
    </div>
  );
}

function LazyThumbnail({ webcam }: { webcam: Webcam }) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { setVisible(true); observer.disconnect(); } },
      { rootMargin: '200px' }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const isYT = webcam.source === 'YouTube';
  const hasStored = !webcam._isAddition && !isYT;
  const thumbUrl = hasStored ? `${API_BASE}/webcam-image?id=${webcam.id}&redirect=true` : webcam.imageUrl;

  return (
    <div ref={ref} className="w-16 h-10 rounded bg-[#2a2a2a] overflow-hidden shrink-0">
      {visible && !error && (
        <img src={thumbUrl} alt="" decoding="async"
          className={`w-full h-full object-cover transition-opacity duration-200 ${loaded ? 'opacity-100' : 'opacity-0'}`}
          onLoad={() => setLoaded(true)} onError={() => setError(true)} />
      )}
    </div>
  );
}

// Compute imageUrl from HLS streamUrl
function computeHlsImageUrl(id: string, streamUrl: string): string {
  return `${API_BASE}/viewsurf-stream?id=${id}&streamUrl=${encodeURIComponent(streamUrl)}`;
}

function isHlsUrl(url: string | null): boolean {
  if (!url) return false;
  return url.includes('.m3u8') || url.includes('quanteec');
}

function WebcamEditor({
  webcam, onSave, onDelete, onClose, saving
}: {
  webcam: Webcam; onSave: (fields: Partial<Webcam>) => void;
  onDelete: () => void; onClose: () => void; saving: boolean;
}) {
  const [form, setForm] = useState({ ...webcam });
  const [sourceParam, setSourceParam] = useState(extractSourceParam(webcam.source, webcam.imageUrl));
  const [imgTimestamp, setImgTimestamp] = useState(0);
  const [streamDirty, setStreamDirty] = useState(false);

  useEffect(() => {
    setForm(prev => {
      if (prev.id === webcam.id) return { ...prev, latitude: webcam.latitude, longitude: webcam.longitude };
      return { ...webcam };
    });
    if (form.id !== webcam.id) {
      setSourceParam(extractSourceParam(webcam.source, webcam.imageUrl));
      setImgTimestamp(0);
      setStreamDirty(false);
    }
  }, [webcam.id, webcam.latitude, webcam.longitude]);

  function updateField(key: string, value: string | number | null) {
    setForm(prev => ({ ...prev, [key]: value }));
  }

  // When streamUrl changes, auto-compute imageUrl (Viewsurf only)
  function handleStreamUrlChange(url: string) {
    const streamUrl = url || null;
    setStreamDirty(true);
    setForm(prev => {
      const updated = { ...prev, streamUrl };
      // Only auto-compute imageUrl for Viewsurf webcams
      if (prev.source === 'Viewsurf' && streamUrl && isHlsUrl(streamUrl)) {
        updated.imageUrl = computeHlsImageUrl(prev.id, streamUrl);
      }
      return updated;
    });
  }

  function handleSourceParamChange(param: string) {
    setSourceParam(param);
    const url = buildImageUrl(form.source, param);
    if (form.source === 'YouTube') {
      const vid = extractYouTubeId(param);
      setForm(prev => ({ ...prev, imageUrl: url, streamUrl: `https://www.youtube.com/embed/${vid}?autoplay=1&mute=1` }));
    } else {
      setForm(prev => ({ ...prev, imageUrl: url }));
    }
  }

  function handleSourceChange(source: string) {
    setForm(prev => ({ ...prev, source }));
    if (sourceParam) setForm(prev => ({ ...prev, imageUrl: buildImageUrl(source, sourceParam) }));
  }

  function handleSave() {
    const fields: Record<string, unknown> = {};
    for (const key of Object.keys(form) as (keyof Webcam)[]) {
      if (key.startsWith('_')) continue;
      fields[key] = form[key];
    }
    onSave(fields as Partial<Webcam>);
  }

  const sourceLabels: Record<string, string> = {
    'Skaping': 'Path (ex: concarneau/panoramique ou data3:tregunc/cam)',
    'Viewsurf': 'ID (ex: 5491)',
    'Vision-Env': 'Slug (ex: saint-malo)',
    'YouTube': 'Video ID ou URL',
  };

  const hasHls = isHlsUrl(form.streamUrl);
  const isYT = form.streamUrl ? isYouTubeUrl(form.streamUrl) : false;

  return (
    <div className="bg-[#1a1a1a] border-l border-white/10 h-full overflow-y-auto">
      <div className="sticky top-0 bg-[#1a1a1a] border-b border-white/10 p-4 flex items-center justify-between z-10">
        <h2 className="text-white font-semibold text-sm truncate flex-1">
          {webcam._isAddition && <span className="text-green-400 mr-1">NEW</span>}
          {webcam._hasOverride && <span className="text-blue-400 mr-1">MOD</span>}
          {form.name || form.id}
        </h2>
        <button onClick={onClose} className="text-white/40 hover:text-white ml-2 text-lg">&times;</button>
      </div>
      <div className="p-4 space-y-4">
        {/* Image preview */}
        <div className="relative rounded-lg overflow-hidden bg-[#2a2a2a] aspect-video">
          <img
            key={`${imgTimestamp}-${streamDirty ? form.imageUrl : ''}`}
            src={imgTimestamp === 0 && !webcam._isAddition && form.source !== 'YouTube' && !streamDirty
              ? `${API_BASE}/webcam-image?id=${webcam.id}&redirect=true`
              : `${form.imageUrl}${form.imageUrl.includes('?') ? '&' : '?'}t=${imgTimestamp || Date.now()}`}
            alt={form.name} className="w-full h-full object-cover" decoding="async"
            onError={(e) => {
              const img = e.target as HTMLImageElement;
              if (img.src.includes('webcam-image')) {
                img.src = `${form.imageUrl}${form.imageUrl.includes('?') ? '&' : '?'}t=${Date.now()}`;
              }
            }}
          />
          <button onClick={() => { setImgTimestamp(Date.now()); setStreamDirty(true); }}
            className="absolute top-2 right-2 bg-black/60 text-white text-xs px-2 py-1 rounded hover:bg-black/80">
            Refresh
          </button>
          {streamDirty && hasHls && (
            <div className="absolute bottom-2 left-2 bg-green-600/90 text-white text-[10px] font-bold px-2 py-0.5 rounded">
              Nouvelle URL
            </div>
          )}
        </div>

        <div className="space-y-3">
          <Field label="ID" value={form.id} readonly={!webcam._isAddition} onChange={v => updateField('id', v)} />
          <Field label="Nom" value={form.name} onChange={v => updateField('name', v)} />
          <Field label="Location" value={form.location} onChange={v => updateField('location', v)} />
          <Select label="Region" value={form.region} options={REGIONS.filter(r => r !== 'Tous')} onChange={v => updateField('region', v)} />
          <div className="grid grid-cols-2 gap-2">
            <Field label="Latitude" value={String(form.latitude)} type="number" onChange={v => updateField('latitude', parseFloat(v) || 0)} />
            <Field label="Longitude" value={String(form.longitude)} type="number" onChange={v => updateField('longitude', parseFloat(v) || 0)} />
          </div>
          <Select label="Source" value={form.source} options={WEBCAM_SOURCES.filter(s => s !== 'Tous')} onChange={handleSourceChange} />
          {sourceLabels[form.source] && (
            <Field label={sourceLabels[form.source]} value={sourceParam} onChange={handleSourceParamChange} />
          )}

          {/* === HLS STREAM SECTION === */}
          {form.source === 'Viewsurf' ? (
            <div className="rounded-xl border border-cyan-500/30 bg-cyan-950/20 p-3 space-y-3">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-cyan-400 animate-pulse" />
                <span className="text-cyan-400 text-xs font-bold uppercase tracking-wide">Stream HLS</span>
              </div>

              {/* m3u8 URL */}
              <div>
                <label className="text-white/50 text-xs mb-1 block">URL m3u8</label>
                <div className="flex gap-1.5">
                  <input
                    type="text"
                    value={form.streamUrl || ''}
                    onChange={e => handleStreamUrlChange(e.target.value)}
                    placeholder="https://ds2-cache.quanteec.com/.../media_0.m3u8"
                    className="flex-1 p-2 rounded-lg bg-[#1a1a1a] text-white text-xs font-mono border border-white/10 outline-none focus:border-cyan-500 placeholder:text-white/20"
                  />
                </div>
                {streamDirty && hasHls && (
                  <div className="text-[10px] text-cyan-400 mt-1.5 flex items-center gap-1">
                    <span className="inline-block w-1.5 h-1.5 rounded-full bg-cyan-400" />
                    ImageUrl sera auto-derive de ce m3u8
                  </div>
                )}
              </div>

              {/* Auto-computed imageUrl (read-only) */}
              {hasHls && (
                <div>
                  <label className="text-white/30 text-[10px] mb-0.5 block">Image URL (auto depuis m3u8)</label>
                  <div className="p-1.5 rounded bg-[#111] text-[10px] font-mono text-white/40 break-all leading-relaxed select-all">
                    {form.imageUrl}
                  </div>
                </div>
              )}

              {/* HLS Player */}
              {form.streamUrl && <StreamPlayer url={form.streamUrl} />}
            </div>
          ) : (
            <>
              {/* Standard image URL + stream fields for non-HLS webcams */}
              <Field label="Image URL" value={form.imageUrl} onChange={v => updateField('imageUrl', v)} />
              <div>
                <Field label={`Live Stream ${isYT ? '(YouTube)' : '(m3u8 / YouTube)'}`}
                  value={form.streamUrl || ''}
                  onChange={v => handleStreamUrlChange(v)}
                  placeholder="URL m3u8 ou YouTube"
                />
                {isYT && (
                  <div className="text-xs text-green-400 mt-1 flex items-center gap-1">
                    <span>&#9654;</span> YouTube detecte
                  </div>
                )}
              </div>
              {form.streamUrl && <StreamPlayer url={form.streamUrl} />}
            </>
          )}

          <Field label="Refresh (sec)" value={String(form.refreshInterval)} type="number"
            onChange={v => updateField('refreshInterval', parseInt(v) || 300)} />
        </div>

        {/* Verified */}
        <div className={`flex items-center justify-between p-3 rounded-lg border ${webcam._verified ? 'bg-green-900/20 border-green-500/30' : 'bg-[#2a2a2a] border-white/10'}`}>
          <div className="flex items-center gap-2">
            <span className={`text-lg ${webcam._verified ? '' : 'grayscale opacity-40'}`}>{webcam._verified ? '\u2705' : '\u2753'}</span>
            <div>
              <div className={`text-xs font-medium ${webcam._verified ? 'text-green-400' : 'text-white/50'}`}>
                {webcam._verified ? 'Verifie' : 'Non verifie'}
              </div>
              {webcam._verifiedAt && <div className="text-[10px] text-white/30">{new Date(webcam._verifiedAt).toLocaleString('fr-FR')}</div>}
            </div>
          </div>
          <button
            onClick={() => onSave({ _verified: !webcam._verified, _verifiedAt: !webcam._verified ? new Date().toISOString() : undefined } as Partial<Webcam>)}
            disabled={saving}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition disabled:opacity-50 ${webcam._verified ? 'bg-orange-800/50 hover:bg-orange-700/50 text-orange-300' : 'bg-green-700 hover:bg-green-600 text-white'}`}
          >
            {webcam._verified ? 'Retirer' : 'Marquer verifie'}
          </button>
        </div>

        {/* Actions */}
        <div className="flex gap-2 pt-2">
          <button onClick={handleSave} disabled={saving}
            className="flex-1 p-2.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde...' : 'Sauvegarder'}
          </button>
          <button onClick={() => { setForm({ ...webcam }); setSourceParam(extractSourceParam(webcam.source, webcam.imageUrl)); setStreamDirty(false); }}
            className="p-2.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-white/60 text-sm transition">Reset</button>
          <button onClick={onDelete}
            className="p-2.5 rounded-lg bg-red-900/50 hover:bg-red-800/50 text-red-400 text-sm transition">Suppr</button>
        </div>
      </div>
    </div>
  );
}

function WebcamCard({
  webcam, health, isSelected, onClick
}: {
  webcam: Webcam; health?: HealthStatus[string]; isSelected: boolean; onClick: () => void;
}) {
  const isOnline = health?.online !== false;
  return (
    <div onClick={onClick}
      className={`flex items-center gap-3 p-3 cursor-pointer border-b border-white/5 hover:bg-white/5 transition ${isSelected ? 'bg-cyan-900/30 border-l-2 border-l-cyan-500' : ''}`}>
      <LazyThumbnail webcam={webcam} />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full shrink-0 ${isOnline ? 'bg-green-500' : 'bg-red-500'}`} />
          <span className="text-white text-xs font-medium truncate">{webcam.name}</span>
          {webcam._verified && <span className="shrink-0 text-[10px]">{'\u2705'}</span>}
        </div>
        <div className="text-white/40 text-[10px] truncate">
          {webcam.location} &middot; {webcam.source}
          {webcam._hasOverride && <span className="text-blue-400 ml-1">MOD</span>}
          {webcam._isAddition && <span className="text-green-400 ml-1">NEW</span>}
        </div>
      </div>
      <div className="text-white/20 text-[9px] text-right shrink-0">
        <div>{webcam.latitude.toFixed(4)}</div>
        <div>{webcam.longitude.toFixed(4)}</div>
      </div>
    </div>
  );
}

// ============================================================
// KITE SPOT EDITOR
// ============================================================

function KiteSpotEditor({
  spot, onSave, onDelete, onClose, saving
}: {
  spot: KiteSpot; onSave: (data: KiteSpot) => void; onDelete: () => void; onClose: () => void; saving: boolean;
}) {
  const [form, setForm] = useState({ ...spot });

  useEffect(() => {
    setForm(prev => {
      if (prev.id === spot.id) return { ...prev, latitude: spot.latitude, longitude: spot.longitude };
      return { ...spot };
    });
  }, [spot.id, spot.latitude, spot.longitude]);

  return (
    <div className="bg-[#1a1a1a] border-l border-white/10 h-full overflow-y-auto">
      <div className="sticky top-0 bg-[#1a1a1a] border-b border-white/10 p-4 flex items-center justify-between z-10">
        <h2 className="text-white font-semibold text-sm truncate flex-1">{form.name || 'Nouveau spot'}</h2>
        <button onClick={onClose} className="text-white/40 hover:text-white ml-2 text-lg">&times;</button>
      </div>
      <div className="p-4 space-y-3">
        <SectionTitle>Identite</SectionTitle>
        <Field label="ID" value={form.id} onChange={v => setForm(f => ({ ...f, id: v }))} />
        <Field label="Nom" value={form.name} onChange={v => setForm(f => ({ ...f, name: v }))} />

        <SectionTitle>Position</SectionTitle>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Latitude" value={String(form.latitude)} type="number" onChange={v => setForm(f => ({ ...f, latitude: parseFloat(v) || 0 }))} />
          <Field label="Longitude" value={String(form.longitude)} type="number" onChange={v => setForm(f => ({ ...f, longitude: parseFloat(v) || 0 }))} />
        </div>

        <SectionTitle>Caracteristiques</SectionTitle>
        <Select label="Niveau" value={form.level} options={KITE_LEVELS} onChange={v => setForm(f => ({ ...f, level: v }))} />
        <Select label="Type de spot" value={form.type} options={KITE_TYPES} onChange={v => setForm(f => ({ ...f, type: v }))} />
        <Select label="Type de vagues" value={form.waveType} options={KITE_WAVE_TYPES} onChange={v => setForm(f => ({ ...f, waveType: v }))} />
        <DirectionPicker label="Orientations vent" value={form.orientation} onChange={v => setForm(f => ({ ...f, orientation: v }))} />
        <Select label="Preference maree" value={form.tidePreference} options={KITE_TIDE_PREFS}
          labelMap={KITE_TIDE_LABELS} onChange={v => setForm(f => ({ ...f, tidePreference: v }))} />

        <SectionTitle>Activites</SectionTitle>
        <Toggle label="Kitesurf" value={form.supportsKite} onChange={v => setForm(f => ({ ...f, supportsKite: v }))} />
        <Toggle label="Windsurf" value={form.supportsWindsurf} onChange={v => setForm(f => ({ ...f, supportsWindsurf: v }))} />
        <Toggle label="Wingfoil" value={form.supportsWing} onChange={v => setForm(f => ({ ...f, supportsWing: v }))} />
        <Toggle label="Surf" value={form.supportsSurf} onChange={v => setForm(f => ({ ...f, supportsSurf: v }))} />

        <div className="flex gap-2 pt-4">
          <button onClick={() => onSave(form)} disabled={saving}
            className="flex-1 p-2.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde...' : 'Sauvegarder'}
          </button>
          <button onClick={() => setForm({ ...spot })}
            className="p-2.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-white/60 text-sm transition">Reset</button>
          <button onClick={onDelete}
            className="p-2.5 rounded-lg bg-red-900/50 hover:bg-red-800/50 text-red-400 text-sm transition">Suppr</button>
        </div>
      </div>
    </div>
  );
}

function KiteSpotCard({
  spot, isSelected, onClick
}: {
  spot: KiteSpot; isSelected: boolean; onClick: () => void;
}) {
  const levelColors: Record<string, string> = {
    'Debutant': 'bg-green-500', 'Intermediaire': 'bg-yellow-500',
    'Confirme': 'bg-orange-500', 'Expert': 'bg-red-500'
  };
  return (
    <div onClick={onClick}
      className={`flex items-center gap-3 p-3 cursor-pointer border-b border-white/5 hover:bg-white/5 transition ${isSelected ? 'bg-cyan-900/30 border-l-2 border-l-cyan-500' : ''}`}>
      <div className="w-8 h-8 rounded-lg bg-[#2a2a2a] flex items-center justify-center text-lg shrink-0">
        {spot.supportsKite ? '\uD83E\uDE81' : '\uD83C\uDFC4'}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full shrink-0 ${levelColors[spot.level] || 'bg-gray-500'}`} />
          <span className="text-white text-xs font-medium truncate">{spot.name}</span>
        </div>
        <div className="text-white/40 text-[10px] truncate">
          {spot.orientation || '—'} &middot; {spot.level} &middot; {spot.type}
          {spot.tidePreference !== 'all' && <span className="text-cyan-400/60 ml-1">{KITE_TIDE_LABELS[spot.tidePreference]}</span>}
        </div>
      </div>
      <div className="text-white/20 text-[9px] text-right shrink-0">
        <div>{spot.latitude.toFixed(4)}</div>
        <div>{spot.longitude.toFixed(4)}</div>
      </div>
    </div>
  );
}

// ============================================================
// SURF SPOT EDITOR
// ============================================================

function SurfSpotEditor({
  spot, onSave, onDelete, onClose, saving
}: {
  spot: SurfSpot; onSave: (data: SurfSpot) => void; onDelete: () => void; onClose: () => void; saving: boolean;
}) {
  const [form, setForm] = useState({ ...spot });

  useEffect(() => {
    setForm(prev => {
      if (prev.id === spot.id) return { ...prev, latitude: spot.latitude, longitude: spot.longitude };
      return { ...spot };
    });
  }, [spot.id, spot.latitude, spot.longitude]);

  return (
    <div className="bg-[#1a1a1a] border-l border-white/10 h-full overflow-y-auto">
      <div className="sticky top-0 bg-[#1a1a1a] border-b border-white/10 p-4 flex items-center justify-between z-10">
        <h2 className="text-white font-semibold text-sm truncate flex-1">{form.name || 'Nouveau spot'}</h2>
        <button onClick={onClose} className="text-white/40 hover:text-white ml-2 text-lg">&times;</button>
      </div>
      <div className="p-4 space-y-3">
        <SectionTitle>Identite</SectionTitle>
        <Field label="ID" value={form.id} onChange={v => setForm(f => ({ ...f, id: v }))} />
        <Field label="Nom" value={form.name} onChange={v => setForm(f => ({ ...f, name: v }))} />
        <Field label="Description" value={form.description} onChange={v => setForm(f => ({ ...f, description: v }))} />

        <SectionTitle>Position</SectionTitle>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Latitude" value={String(form.latitude)} type="number" onChange={v => setForm(f => ({ ...f, latitude: parseFloat(v) || 0 }))} />
          <Field label="Longitude" value={String(form.longitude)} type="number" onChange={v => setForm(f => ({ ...f, longitude: parseFloat(v) || 0 }))} />
        </div>

        <SectionTitle>Caracteristiques</SectionTitle>
        <Select label="Niveau" value={form.level} options={SURF_LEVELS} onChange={v => setForm(f => ({ ...f, level: v }))} />
        <Select label="Type de vague" value={form.waveType} options={SURF_WAVE_TYPES} onChange={v => setForm(f => ({ ...f, waveType: v }))} />
        <Select label="Type de fond" value={form.bottomType} options={SURF_BOTTOM_TYPES} onChange={v => setForm(f => ({ ...f, bottomType: v }))} />
        <DirectionPicker label="Orientation (face houle)" value={form.orientation} onChange={v => setForm(f => ({ ...f, orientation: v }))} />

        <SectionTitle>Conditions ideales - Houle</SectionTitle>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Direction min (deg)" value={String(form.idealSwellDirMin)} type="number" onChange={v => setForm(f => ({ ...f, idealSwellDirMin: parseFloat(v) || 0 }))} />
          <Field label="Direction max (deg)" value={String(form.idealSwellDirMax)} type="number" onChange={v => setForm(f => ({ ...f, idealSwellDirMax: parseFloat(v) || 0 }))} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Taille min (m)" value={String(form.idealSwellSizeMin)} type="number" onChange={v => setForm(f => ({ ...f, idealSwellSizeMin: parseFloat(v) || 0 }))} />
          <Field label="Taille max (m)" value={String(form.idealSwellSizeMax)} type="number" onChange={v => setForm(f => ({ ...f, idealSwellSizeMax: parseFloat(v) || 0 }))} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Periode min (s)" value={String(form.idealPeriodMin)} type="number" onChange={v => setForm(f => ({ ...f, idealPeriodMin: parseFloat(v) || 0 }))} />
          <Field label="Periode max (s)" value={String(form.idealPeriodMax)} type="number" onChange={v => setForm(f => ({ ...f, idealPeriodMax: parseFloat(v) || 0 }))} />
        </div>
        <Select label="Maree ideale" value={form.idealTide} options={SURF_TIDE_PREFS} onChange={v => setForm(f => ({ ...f, idealTide: v }))} />

        <SectionTitle>Informations</SectionTitle>
        <Field label="Dangers (separes par virgule)" value={form.hazards} placeholder="Rochers, courants..."
          onChange={v => setForm(f => ({ ...f, hazards: v }))} />
        <Select label="Affluence" value={form.crowd} options={SURF_CROWD_LEVELS} onChange={v => setForm(f => ({ ...f, crowd: v }))} />
        <Field label="Regularite (1-5)" value={String(form.consistency)} type="number"
          onChange={v => setForm(f => ({ ...f, consistency: Math.min(5, Math.max(1, parseInt(v) || 3)) }))} />

        <div className="flex gap-2 pt-4">
          <button onClick={() => onSave(form)} disabled={saving}
            className="flex-1 p-2.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde...' : 'Sauvegarder'}
          </button>
          <button onClick={() => setForm({ ...spot })}
            className="p-2.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-white/60 text-sm transition">Reset</button>
          <button onClick={onDelete}
            className="p-2.5 rounded-lg bg-red-900/50 hover:bg-red-800/50 text-red-400 text-sm transition">Suppr</button>
        </div>
      </div>
    </div>
  );
}

function SurfSpotCard({
  spot, isSelected, onClick
}: {
  spot: SurfSpot; isSelected: boolean; onClick: () => void;
}) {
  const levelColors: Record<string, string> = {
    'Debutant': 'bg-green-500', 'Intermediaire': 'bg-yellow-500',
    'Confirme': 'bg-orange-500', 'Expert': 'bg-red-500'
  };
  return (
    <div onClick={onClick}
      className={`flex items-center gap-3 p-3 cursor-pointer border-b border-white/5 hover:bg-white/5 transition ${isSelected ? 'bg-cyan-900/30 border-l-2 border-l-cyan-500' : ''}`}>
      <div className="w-8 h-8 rounded-lg bg-[#2a2a2a] flex items-center justify-center text-lg shrink-0">{'\uD83C\uDFC4'}</div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full shrink-0 ${levelColors[spot.level] || 'bg-gray-500'}`} />
          <span className="text-white text-xs font-medium truncate">{spot.name}</span>
        </div>
        <div className="text-white/40 text-[10px] truncate">
          {spot.waveType} &middot; {spot.bottomType} &middot; {spot.level}
        </div>
      </div>
      <div className="text-white/20 text-[9px] text-right shrink-0">
        <div>{spot.latitude.toFixed(4)}</div>
        <div>{spot.longitude.toFixed(4)}</div>
      </div>
    </div>
  );
}

// ============================================================
// STATION COMPONENTS
// ============================================================

function StationEditor({
  station, onSave, onDelete, onRestore, onClose, saving, webcams, kiteSpots
}: {
  station: WindStation;
  onSave: (changes: Partial<WindStation>) => void;
  onDelete: () => void;
  onRestore?: () => void;
  onClose: () => void;
  saving: boolean;
  webcams: Webcam[];
  kiteSpots: KiteSpot[];
}) {
  const [form, setForm] = useState({ ...station });

  useEffect(() => {
    setForm(prev => {
      if (prev.stableId === station.stableId) {
        return { ...prev, latitude: station.latitude, longitude: station.longitude };
      }
      return { ...station };
    });
  }, [station.stableId, station.latitude, station.longitude, station]);

  function getChangedFields(): Partial<WindStation> {
    const changes: Partial<WindStation> = {};
    const keys = ['name', 'latitude', 'longitude', 'altitude', 'description', 'picture', 'region', 'tags', '_hidden', '_notes', '_priority', '_associatedWebcamId', '_associatedKiteSpotId', '_customOnlineThreshold'] as const;
    for (const key of keys) {
      if (form[key] !== station[key]) {
        (changes as Record<string, unknown>)[key] = form[key];
      }
    }
    return changes;
  }

  const windColor = form.wind >= 25 ? 'text-red-400' : form.wind >= 15 ? 'text-orange-400' : form.wind >= 8 ? 'text-green-400' : 'text-white/50';
  const isCustom = station._isAddition || station.source === 'custom';

  return (
    <div className="bg-[#1a1a1a] border-l border-white/10 h-full overflow-y-auto">
      <div className="sticky top-0 bg-[#1a1a1a] border-b border-white/10 p-4 flex items-center justify-between z-10">
        <div className="flex items-center gap-2 flex-1 min-w-0">
          <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: WIND_SOURCE_COLORS[form.source] || '#888' }} />
          <h2 className="text-white font-semibold text-sm truncate">{form.name || 'Nouvelle station'}</h2>
          {station._hasOverride && <span className="px-1.5 py-0.5 bg-blue-600/30 text-blue-400 text-[9px] rounded">MOD</span>}
          {station._isAddition && <span className="px-1.5 py-0.5 bg-green-600/30 text-green-400 text-[9px] rounded">NEW</span>}
          {station._hidden && <span className="px-1.5 py-0.5 bg-red-600/30 text-red-400 text-[9px] rounded">HIDDEN</span>}
        </div>
        <button onClick={onClose} className="text-white/40 hover:text-white ml-2 text-lg">&times;</button>
      </div>
      <div className="p-4 space-y-3">
        {/* Live Data Panel */}
        <div className="bg-[#252525] rounded-lg p-3 mb-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-white/40 text-xs">Donnees live</span>
            <span className={`text-xs px-2 py-0.5 rounded ${form.isOnline ? 'bg-green-600/30 text-green-400' : 'bg-red-600/30 text-red-400'}`}>
              {form.isOnline ? 'Online' : 'Offline'}
            </span>
          </div>
          <div className="grid grid-cols-3 gap-3 text-center">
            <div>
              <div className={`text-xl font-bold ${windColor}`}>{form.wind.toFixed(1)}</div>
              <div className="text-white/30 text-[10px]">Vent (nds)</div>
            </div>
            <div>
              <div className="text-xl font-bold text-white/80">{form.gust.toFixed(1)}</div>
              <div className="text-white/30 text-[10px]">Rafale (nds)</div>
            </div>
            <div>
              <div className="text-xl font-bold text-white/80">{form.direction}&deg;</div>
              <div className="text-white/30 text-[10px]">Direction</div>
            </div>
          </div>
          {(form.temperature || form.pressure || form.humidity) && (
            <div className="grid grid-cols-3 gap-3 text-center mt-3 pt-3 border-t border-white/10">
              {form.temperature && <div><div className="text-sm text-white/70">{form.temperature}&deg;C</div><div className="text-white/30 text-[9px]">Temp</div></div>}
              {form.pressure && <div><div className="text-sm text-white/70">{form.pressure} hPa</div><div className="text-white/30 text-[9px]">Pression</div></div>}
              {form.humidity && <div><div className="text-sm text-white/70">{form.humidity}%</div><div className="text-white/30 text-[9px]">Humidite</div></div>}
            </div>
          )}
          {form.ts && (
            <div className="text-white/30 text-[10px] text-center mt-2">
              Derniere MAJ: {new Date(form.ts).toLocaleString('fr')}
            </div>
          )}
        </div>

        <SectionTitle>Identite</SectionTitle>
        <Field label="Stable ID" value={form.stableId} readonly />
        <Field label="Source" value={WIND_SOURCE_LABELS[form.source] || form.source} readonly={!isCustom} />
        <Field label="Nom" value={form.name} onChange={v => setForm(f => ({ ...f, name: v }))} />
        <Select label="Region" value={form.region || 'Tous'} options={REGIONS} onChange={v => setForm(f => ({ ...f, region: v === 'Tous' ? null : v }))} />
        <Field label="Description" value={form.description || ''} onChange={v => setForm(f => ({ ...f, description: v || null }))} />
        <Field label="URL Photo" value={form.picture || ''} placeholder="https://..." onChange={v => setForm(f => ({ ...f, picture: v || null }))} />

        <SectionTitle>Position</SectionTitle>
        <div className="grid grid-cols-2 gap-2">
          <Field label="Latitude" value={String(form.latitude)} type="number" onChange={v => setForm(f => ({ ...f, latitude: parseFloat(v) || 0 }))} />
          <Field label="Longitude" value={String(form.longitude)} type="number" onChange={v => setForm(f => ({ ...f, longitude: parseFloat(v) || 0 }))} />
        </div>
        <Field label="Altitude (m)" value={form.altitude ? String(form.altitude) : ''} type="number" placeholder="Optionnel"
          onChange={v => setForm(f => ({ ...f, altitude: v ? parseInt(v) : null }))} />

        <SectionTitle>Options avancees</SectionTitle>
        <Toggle label="Masquer cette station" value={form._hidden || false}
          description="La station ne sera plus visible dans l'app"
          onChange={v => setForm(f => ({ ...f, _hidden: v }))} />
        <Field label="Priorite d'affichage" value={form._priority ? String(form._priority) : '0'} type="number"
          onChange={v => setForm(f => ({ ...f, _priority: parseInt(v) || 0 }))} />
        <Field label="Seuil online custom (minutes)" value={form._customOnlineThreshold ? String(form._customOnlineThreshold) : ''} type="number" placeholder="Defaut: 30"
          onChange={v => setForm(f => ({ ...f, _customOnlineThreshold: v ? parseInt(v) : null }))} />
        <Field label="Notes admin" value={form._notes || ''} placeholder="Notes internes..."
          onChange={v => setForm(f => ({ ...f, _notes: v || null }))} />
        <Field label="Tags" value={form.tags || ''} placeholder="kite, spot-expo..."
          onChange={v => setForm(f => ({ ...f, tags: v || null }))} />

        <SectionTitle>Associations</SectionTitle>
        <div>
          <label className="text-white/50 text-xs mb-1 block">Webcam associee</label>
          <select
            value={form._associatedWebcamId || ''}
            onChange={e => setForm(f => ({ ...f, _associatedWebcamId: e.target.value || null }))}
            className="w-full p-2 rounded bg-[#2a2a2a] text-white text-sm border border-white/10"
          >
            <option value="">Aucune</option>
            {webcams.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        </div>
        <div>
          <label className="text-white/50 text-xs mb-1 block">Spot kite associe</label>
          <select
            value={form._associatedKiteSpotId || ''}
            onChange={e => setForm(f => ({ ...f, _associatedKiteSpotId: e.target.value || null }))}
            className="w-full p-2 rounded bg-[#2a2a2a] text-white text-sm border border-white/10"
          >
            <option value="">Aucun</option>
            {kiteSpots.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </div>

        <div className="flex gap-2 pt-4">
          <button onClick={() => onSave(getChangedFields())} disabled={saving}
            className="flex-1 p-2.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde...' : 'Sauvegarder'}
          </button>
          <button onClick={() => setForm({ ...station })}
            className="p-2.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-white/60 text-sm transition">Reset</button>
          {station._hidden && onRestore ? (
            <button onClick={onRestore}
              className="p-2.5 rounded-lg bg-green-900/50 hover:bg-green-800/50 text-green-400 text-sm transition">Restaurer</button>
          ) : (
            <button onClick={onDelete}
              className="p-2.5 rounded-lg bg-red-900/50 hover:bg-red-800/50 text-red-400 text-sm transition">
              {isCustom ? 'Suppr' : 'Masquer'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function StationCard({
  station, isSelected, onClick
}: {
  station: WindStation; isSelected: boolean; onClick: () => void;
}) {
  const windColor = station.wind >= 25 ? 'text-red-400' : station.wind >= 15 ? 'text-orange-400' : station.wind >= 8 ? 'text-green-400' : 'text-white/40';
  const sourceColor = WIND_SOURCE_COLORS[station.source] || '#888';

  return (
    <div onClick={onClick}
      className={`flex items-center gap-3 p-3 cursor-pointer border-b border-white/5 hover:bg-white/5 transition ${isSelected ? 'bg-cyan-900/30 border-l-2 border-l-cyan-500' : ''} ${station._hidden ? 'opacity-40' : ''}`}>
      <div className="w-10 h-10 rounded-lg bg-[#2a2a2a] flex flex-col items-center justify-center shrink-0 relative">
        <span className={`text-lg font-bold ${windColor}`}>{Math.round(station.wind)}</span>
        <span className="text-[8px] text-white/30">nds</span>
        <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full" style={{ backgroundColor: sourceColor }} />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full shrink-0 ${station.isOnline ? 'bg-green-500' : 'bg-red-500'}`} />
          <span className="text-white text-xs font-medium truncate">{station.name}</span>
          {station._hasOverride && <span className="px-1 py-0.5 bg-blue-600/30 text-blue-400 text-[8px] rounded">MOD</span>}
          {station._isAddition && <span className="px-1 py-0.5 bg-green-600/30 text-green-400 text-[8px] rounded">NEW</span>}
          {station._hidden && <span className="px-1 py-0.5 bg-red-600/30 text-red-400 text-[8px] rounded">X</span>}
        </div>
        <div className="text-white/40 text-[10px] truncate">
          {WIND_SOURCE_LABELS[station.source] || station.source} &middot; {station.gust.toFixed(1)} nds rafale &middot; {station.direction}&deg;
        </div>
      </div>
      <div className="text-right shrink-0">
        <div className="text-white/20 text-[9px]">{station.stableId.split('_')[0]}</div>
        {station.ts && (
          <div className="text-white/15 text-[8px]">{new Date(station.ts).toLocaleTimeString('fr', { hour: '2-digit', minute: '2-digit' })}</div>
        )}
      </div>
    </div>
  );
}

// ============================================================
// APP CONFIG PANEL
// ============================================================

function AppConfigPanel({
  config, onSave, saving
}: {
  config: AppConfig; onSave: (c: AppConfig) => void; saving: boolean;
}) {
  const [form, setForm] = useState<AppConfig>({ ...DEFAULT_CONFIG, ...config });

  useEffect(() => {
    setForm({ ...DEFAULT_CONFIG, ...config });
  }, [config]);

  function update(key: string, value: unknown) {
    setForm(prev => ({ ...prev, [key]: value }));
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto p-6 space-y-2">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-white text-lg font-bold">Configuration de l&apos;app</h2>
          <button onClick={() => onSave(form)} disabled={saving}
            className="px-4 py-2 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde...' : 'Sauvegarder'}
          </button>
        </div>

        {/* Maintenance */}
        <SectionTitle>Maintenance</SectionTitle>
        <Toggle label="Mode maintenance" value={form.maintenanceMode}
          description="Affiche un message de maintenance dans l'app"
          onChange={v => update('maintenanceMode', v)} />
        {form.maintenanceMode && (
          <Field label="Message de maintenance" value={form.maintenanceMessage}
            placeholder="L'app est en maintenance..."
            onChange={v => update('maintenanceMessage', v)} />
        )}

        {/* Feature Flags */}
        <SectionTitle>Fonctionnalites</SectionTitle>
        <Toggle label="Peche / Solunar" value={form.enableFishing} onChange={v => update('enableFishing', v)} />
        <Toggle label="Previsions meteo" value={form.enableForecasts} onChange={v => update('enableForecasts', v)} />
        <Toggle label="Webcams" value={form.enableWebcams} onChange={v => update('enableWebcams', v)} />
        <Toggle label="Bouees houlographes" value={form.enableWaveBuoys} onChange={v => update('enableWaveBuoys', v)} />
        <Toggle label="Radar pluie" value={form.enableRadar} onChange={v => update('enableRadar', v)} />

        {/* Wind Sources */}
        <SectionTitle>Sources de vent</SectionTitle>
        <Toggle label="Wind Cornouaille / Morbihan" value={form.sourceWindCornouaille}
          description="18 capteurs Wind France" onChange={v => update('sourceWindCornouaille', v)} />
        <Toggle label="FFVL" value={form.sourceFFVL}
          description="Stations federation vol libre" onChange={v => update('sourceFFVL', v)} />
        <Toggle label="Pioupiou" value={form.sourcePioupiou}
          description="Stations communautaires" onChange={v => update('sourcePioupiou', v)} />
        <Toggle label="Holfuy" value={form.sourceHolfuy}
          description="Stations Holfuy via GoWind" onChange={v => update('sourceHolfuy', v)} />
        <Toggle label="Windguru" value={form.sourceWindguru}
          description="Stations Windguru via GoWind" onChange={v => update('sourceWindguru', v)} />
        <Toggle label="WindsUp" value={form.sourceWindsUp}
          description="Service premium (necessite abonnement)" onChange={v => update('sourceWindsUp', v)} />
        <Toggle label="Meteo-France" value={form.sourceMeteoFrance}
          description="45 stations officielles" onChange={v => update('sourceMeteoFrance', v)} />
        <Toggle label="Diabox" value={form.sourceDiabox}
          description="~9 stations Diabox" onChange={v => update('sourceDiabox', v)} />
        <Toggle label="NDBC (Bouées offshore)" value={form.sourceNDBC}
          description="7 bouées NOAA Manche/Atlantique" onChange={v => update('sourceNDBC', v)} />
        <Toggle label="Netatmo" value={form.sourceNetatmo}
          description="~3000 stations communautaires" onChange={v => update('sourceNetatmo', v)} />

        {/* Spot Display */}
        <SectionTitle>Affichage spots</SectionTitle>
        <Toggle label="Spots de kite" value={form.showKiteSpots} onChange={v => update('showKiteSpots', v)} />
        <Toggle label="Spots de surf" value={form.showSurfSpots} onChange={v => update('showSurfSpots', v)} />
        <Toggle label="Spots de parapente" value={form.showParaglidingSpots} onChange={v => update('showParaglidingSpots', v)} />
        <Toggle label="Widget marees" value={form.showTideWidget} onChange={v => update('showTideWidget', v)} />

        {/* Wind */}
        <SectionTitle>Parametres vent</SectionTitle>
        <Select label="Unite de vent par defaut" value={form.defaultWindUnit} options={WIND_UNITS}
          onChange={v => update('defaultWindUnit', v)} />
        <Select label="Intervalle de rafraichissement" value={String(form.defaultRefreshInterval)}
          options={REFRESH_INTERVALS.map(r => String(r.value))}
          labelMap={Object.fromEntries(REFRESH_INTERVALS.map(r => [String(r.value), r.label]))}
          onChange={v => update('defaultRefreshInterval', parseInt(v))} />

        {/* Kite Thresholds */}
        <SectionTitle>Seuils kite</SectionTitle>
        <div className="grid grid-cols-3 gap-2">
          <Field label="Vent min (nds)" value={String(form.kiteMinWind)} type="number"
            onChange={v => update('kiteMinWind', parseInt(v) || 0)} />
          <Field label="Vent max (nds)" value={String(form.kiteMaxWind)} type="number"
            onChange={v => update('kiteMaxWind', parseInt(v) || 0)} />
          <Field label="Rafale max (nds)" value={String(form.kiteMaxGust)} type="number"
            onChange={v => update('kiteMaxGust', parseInt(v) || 0)} />
        </div>

        {/* Notifications */}
        <SectionTitle>Notifications</SectionTitle>
        <Toggle label="Heures calmes" value={form.quietHoursEnabled}
          description="Pas de notifications pendant les heures calmes"
          onChange={v => update('quietHoursEnabled', v)} />
        {form.quietHoursEnabled && (
          <div className="grid grid-cols-2 gap-2">
            <Field label="Debut (heure)" value={String(form.quietHoursStart)} type="number"
              onChange={v => update('quietHoursStart', Math.min(23, Math.max(0, parseInt(v) || 0)))} />
            <Field label="Fin (heure)" value={String(form.quietHoursEnd)} type="number"
              onChange={v => update('quietHoursEnd', Math.min(23, Math.max(0, parseInt(v) || 0)))} />
          </div>
        )}

        {/* Map Defaults */}
        <SectionTitle>Carte par defaut</SectionTitle>
        <div className="grid grid-cols-3 gap-2">
          <Field label="Latitude" value={String(form.defaultMapLat)} type="number"
            onChange={v => update('defaultMapLat', parseFloat(v) || 0)} />
          <Field label="Longitude" value={String(form.defaultMapLon)} type="number"
            onChange={v => update('defaultMapLon', parseFloat(v) || 0)} />
          <Field label="Zoom" value={String(form.defaultMapZoom)} type="number"
            onChange={v => update('defaultMapZoom', parseInt(v) || 6)} />
        </div>

        {/* Save button at bottom too */}
        <div className="pt-6">
          <button onClick={() => onSave(form)} disabled={saving}
            className="w-full p-3 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white font-semibold disabled:opacity-50 transition">
            {saving ? 'Sauvegarde en cours...' : 'Sauvegarder la configuration'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ============================================================
// MAIN ADMIN PAGE
// ============================================================

export default function AdminPage() {
  const [password, setPassword] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<AdminTab>('webcams');
  const [toast, setToast] = useState('');
  const [saving, setSaving] = useState(false);

  // Webcams state
  const [webcams, setWebcams] = useState<Webcam[]>([]);
  const [health, setHealth] = useState<HealthStatus>({});
  const [webcamLoading, setWebcamLoading] = useState(true);
  const [selectedWebcamId, setSelectedWebcamId] = useState<string | null>(null);
  const [webcamSearch, setWebcamSearch] = useState('');
  const [regionFilter, setRegionFilter] = useState('Tous');
  const [sourceFilter, setSourceFilter] = useState('Tous');
  const [statusFilter, setStatusFilter] = useState('Tous');
  const [showExport, setShowExport] = useState(false);
  const [exportData, setExportData] = useState('');
  const [creatingWebcam, setCreatingWebcam] = useState(false);
  const [webcamSaveVersion, setWebcamSaveVersion] = useState(0);

  // Kite spots state
  const [kiteSpots, setKiteSpots] = useState<KiteSpot[]>([]);
  const [kiteLoading, setKiteLoading] = useState(true);
  const [selectedKiteId, setSelectedKiteId] = useState<string | null>(null);
  const [kiteSearch, setKiteSearch] = useState('');
  const [kiteLevelFilter, setKiteLevelFilter] = useState('Tous');

  // Surf spots state
  const [surfSpots, setSurfSpots] = useState<SurfSpot[]>([]);
  const [surfLoading, setSurfLoading] = useState(true);
  const [selectedSurfId, setSelectedSurfId] = useState<string | null>(null);
  const [surfSearch, setSurfSearch] = useState('');
  const [surfLevelFilter, setSurfLevelFilter] = useState('Tous');

  // Config state
  const [appConfig, setAppConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [configLoading, setConfigLoading] = useState(true);

  // AI suggestions state (webcam AI)
  const [aiSuggestions, setAiSuggestions] = useState<AISuggestion[]>([]);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiAnalyzing, setAiAnalyzing] = useState(false);

  // Station AI state
  const [stationAiSuggestions, setStationAiSuggestions] = useState<StationAiSuggestion[]>([]);
  const [stationAiLoading, setStationAiLoading] = useState(false);
  const [stationAiAnalyzing, setStationAiAnalyzing] = useState(false);

  // Webcam Weather AI state
  const [webcamWeather, setWebcamWeather] = useState<WebcamWeatherData[]>([]);
  const [webcamWeatherLoading, setWebcamWeatherLoading] = useState(false);
  const [webcamWeatherAnalyzing, setWebcamWeatherAnalyzing] = useState(false);

  // Stations state
  const [stations, setStations] = useState<WindStation[]>([]);
  const [stationStats, setStationStats] = useState<StationStats | null>(null);
  const [stationLoading, setStationLoading] = useState(true);
  const [selectedStationId, setSelectedStationId] = useState<string | null>(null);
  const [stationSearch, setStationSearch] = useState('');
  const [stationSourceFilter, setStationSourceFilter] = useState('Tous');
  const [stationStatusFilter, setStationStatusFilter] = useState('Tous');
  const [stationRegionFilter, setStationRegionFilter] = useState('Tous');
  const [creatingStation, setCreatingStation] = useState(false);

  // Map
  const mapContainer = useRef<HTMLDivElement>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const markersRef = useRef<Map<string, mapboxgl.Marker>>(new Map());
  const [mapSearchQuery, setMapSearchQuery] = useState('');
  const [mapSearchResults, setMapSearchResults] = useState<Array<{ place_name: string; center: [number, number] }>>([]);
  const mapSearchTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Init from sessionStorage
  useEffect(() => {
    const saved = sessionStorage.getItem('admin_pw');
    if (saved) setPassword(saved);
  }, []);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(''), 3000);
  }

  // Map geocoding search
  function handleMapSearch(query: string) {
    setMapSearchQuery(query);
    if (mapSearchTimeout.current) clearTimeout(mapSearchTimeout.current);
    if (!query.trim()) { setMapSearchResults([]); return; }
    mapSearchTimeout.current = setTimeout(async () => {
      try {
        const res = await fetch(
          `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(query)}.json?access_token=${MAPBOX_TOKEN}&country=fr&limit=5&language=fr`
        );
        const data = await res.json();
        setMapSearchResults(data.features?.map((f: { place_name: string; center: [number, number] }) => ({
          place_name: f.place_name, center: f.center
        })) || []);
      } catch { setMapSearchResults([]); }
    }, 300);
  }

  function selectMapSearchResult(center: [number, number]) {
    mapRef.current?.flyTo({ center, zoom: 14, duration: 800 });
    setMapSearchQuery('');
    setMapSearchResults([]);
  }

  function authHeaders() {
    return { Authorization: `Bearer ${password}`, 'Content-Type': 'application/json' };
  }

  // ============================================================
  // DATA FETCHING
  // ============================================================

  const fetchWebcams = useCallback(async () => {
    if (!password) return;
    setWebcamLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcams`, { headers: { Authorization: `Bearer ${password}` } });
      if (res.status === 401) { sessionStorage.removeItem('admin_pw'); setPassword(null); return; }
      const data = await res.json();
      setWebcams(data.webcams || []);
      setHealth(data.health || {});
    } catch (e) { console.error('Fetch webcams error:', e); }
    setWebcamLoading(false);
  }, [password]);

  const fetchKiteSpots = useCallback(async () => {
    if (!password) return;
    setKiteLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=kite_spots`, { headers: { Authorization: `Bearer ${password}` } });
      const data = await res.json();
      setKiteSpots(data.data || []);
    } catch (e) { console.error('Fetch kite spots error:', e); }
    setKiteLoading(false);
  }, [password]);

  const fetchSurfSpots = useCallback(async () => {
    if (!password) return;
    setSurfLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=surf_spots`, { headers: { Authorization: `Bearer ${password}` } });
      const data = await res.json();
      setSurfSpots(data.data || []);
    } catch (e) { console.error('Fetch surf spots error:', e); }
    setSurfLoading(false);
  }, [password]);

  const fetchConfig = useCallback(async () => {
    if (!password) return;
    setConfigLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=app_config`, { headers: { Authorization: `Bearer ${password}` } });
      const data = await res.json();
      setAppConfig({ ...DEFAULT_CONFIG, ...data.data });
    } catch (e) { console.error('Fetch config error:', e); }
    setConfigLoading(false);
  }, [password]);

  // AI suggestions functions
  const fetchAiSuggestions = useCallback(async () => {
    if (!password) return;
    setAiLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcam-ai`, { headers: authHeaders() });
      const data = await res.json();
      setAiSuggestions(data.suggestions || []);
    } catch (e) { console.error('Fetch AI suggestions error:', e); }
    setAiLoading(false);
  }, [password]);

  async function runAiAnalysis(scope: string) {
    setAiAnalyzing(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcam-ai?scope=${scope}`, {
        method: 'POST', headers: authHeaders()
      });
      const data = await res.json();
      showToast(`Analyse terminee: ${data.newSuggestions || 0} nouvelles suggestions (${data.elapsed})`);
      await fetchAiSuggestions();
    } catch { showToast('Erreur analyse IA'); }
    setAiAnalyzing(false);
  }

  async function handleAiAction(id: string, action: 'approve' | 'reject' | 'dismiss') {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcam-ai?id=${encodeURIComponent(id)}&action=${action}`, {
        method: 'PUT', headers: authHeaders()
      });
      if (res.ok) {
        showToast(action === 'approve' ? 'Correction appliquee' : action === 'reject' ? 'Suggestion rejetee' : 'Suggestion supprimee');
        setAiSuggestions(prev => prev.filter(s => s.id !== id));
        if (action === 'approve') await fetchWebcams(); // Refresh webcams after applying correction
      } else showToast('Erreur');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  // Station AI functions
  const fetchStationAiSuggestions = useCallback(async () => {
    if (!password) return;
    setStationAiLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/station-ai`, { headers: authHeaders() });
      const data = await res.json();
      setStationAiSuggestions(data.suggestions || []);
    } catch (e) { console.error('Fetch Station AI error:', e); }
    setStationAiLoading(false);
  }, [password]);

  async function runStationAiAnalysis(scope: string) {
    setStationAiAnalyzing(true);
    try {
      const res = await fetch(`${API_BASE}/admin/station-ai?scope=${scope}`, {
        method: 'POST', headers: authHeaders()
      });
      const data = await res.json();
      showToast(`Analyse stations: ${data.newSuggestions || 0} nouveaux problemes (${data.elapsed})`);
      await fetchStationAiSuggestions();
    } catch { showToast('Erreur analyse stations'); }
    setStationAiAnalyzing(false);
  }

  async function handleStationAiAction(id: string, action: 'approve' | 'reject' | 'dismiss') {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/station-ai?id=${encodeURIComponent(id)}&action=${action}`, {
        method: 'PUT', headers: authHeaders()
      });
      if (res.ok) {
        showToast(action === 'approve' ? 'Correction appliquee' : action === 'reject' ? 'Rejete' : 'Supprime');
        setStationAiSuggestions(prev => prev.filter(s => s.id !== id));
        if (action === 'approve') await fetchStations();
      } else showToast('Erreur');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  // Webcam Weather AI functions
  const fetchWebcamWeather = useCallback(async () => {
    if (!password) return;
    setWebcamWeatherLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcam-weather`, { headers: authHeaders() });
      const data = await res.json();
      setWebcamWeather(data.data || []);
    } catch (e) { console.error('Fetch Webcam Weather error:', e); }
    setWebcamWeatherLoading(false);
  }, [password]);

  async function runWebcamWeatherAnalysis(limit: number = 10) {
    setWebcamWeatherAnalyzing(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcam-weather?limit=${limit}`, {
        method: 'POST', headers: authHeaders()
      });
      const data = await res.json();
      showToast(`Analyse meteo: ${data.analyzed || 0} webcams analysees (${data.elapsed})`);
      await fetchWebcamWeather();
    } catch { showToast('Erreur analyse meteo'); }
    setWebcamWeatherAnalyzing(false);
  }

  // Stations functions
  const fetchStations = useCallback(async () => {
    if (!password) return;
    setStationLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/stations`, { headers: authHeaders() });
      if (res.status === 401) { sessionStorage.removeItem('admin_pw'); setPassword(null); return; }
      const data = await res.json();
      setStations(data.stations || []);
      setStationStats({ total: data.total, online: data.online, offline: data.offline, withOverride: data.withOverride, additions: data.additions, sources: data.sources });
    } catch (e) { console.error('Fetch stations error:', e); }
    setStationLoading(false);
  }, [password]);

  // Load data on tab change
  useEffect(() => {
    if (!password) return;
    if (activeTab === 'webcams') fetchWebcams();
    else if (activeTab === 'kite') fetchKiteSpots();
    else if (activeTab === 'surf') fetchSurfSpots();
    else if (activeTab === 'stations') fetchStations();
    else if (activeTab === 'config') fetchConfig();
    else if (activeTab === 'ai') {
      fetchAiSuggestions();
      fetchStationAiSuggestions();
      fetchWebcamWeather();
    }
  }, [activeTab, password, fetchWebcams, fetchKiteSpots, fetchSurfSpots, fetchStations, fetchConfig, fetchAiSuggestions, fetchStationAiSuggestions, fetchWebcamWeather]);

  // ============================================================
  // MAP INITIALIZATION
  // ============================================================

  useEffect(() => {
    if (!mapContainer.current || mapRef.current || !password) return;
    mapboxgl.accessToken = MAPBOX_TOKEN;
    const map = new mapboxgl.Map({
      container: mapContainer.current,
      style: 'mapbox://styles/mapbox/satellite-streets-v12',
      center: [-3.5, 47.8],
      zoom: 6,
    });
    map.addControl(new mapboxgl.NavigationControl(), 'top-left');
    mapRef.current = map;
    return () => { map.remove(); mapRef.current = null; };
  }, [password]);

  // ============================================================
  // MAP MARKERS
  // ============================================================

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    // Clear all markers
    markersRef.current.forEach(m => m.remove());
    markersRef.current.clear();

    if (activeTab === 'webcams') {
      webcams.forEach(webcam => {
        const isOnline = health[webcam.id]?.online !== false;
        const isModified = webcam._hasOverride;
        const isNew = webcam._isAddition;
        const isVerified = webcam._verified;
        const isSelected = webcam.id === selectedWebcamId;
        const color = isNew ? '#22c55e' : isModified ? '#3b82f6' : isVerified ? '#06b6d4' : isOnline ? '#a3a3a3' : '#ef4444';
        const size = isSelected ? 16 : 10;
        const el = document.createElement('div');
        el.style.cssText = `width:${size}px;height:${size}px;border-radius:50%;background:${color};border:2px solid ${isSelected ? '#fff' : 'rgba(255,255,255,0.6)'};cursor:pointer;transition:all 0.15s;box-shadow:${isSelected ? '0 0 8px rgba(6,182,212,0.8)' : '0 1px 3px rgba(0,0,0,0.5)'};`;
        el.addEventListener('click', (e) => { e.stopPropagation(); setSelectedWebcamId(webcam.id); setCreatingWebcam(false); });
        const marker = new mapboxgl.Marker({ element: el, draggable: true })
          .setLngLat([webcam.longitude, webcam.latitude]).addTo(map);
        marker.on('dragend', () => {
          const { lat, lng } = marker.getLngLat();
          handleUpdateWebcamLocal(webcam.id, {
            latitude: Math.round(lat * 10000) / 10000,
            longitude: Math.round(lng * 10000) / 10000
          });
        });
        markersRef.current.set(webcam.id, marker);
      });
    } else if (activeTab === 'kite') {
      const levelColors: Record<string, string> = {
        'Debutant': '#22c55e', 'Intermediaire': '#eab308',
        'Confirme': '#f97316', 'Expert': '#ef4444'
      };
      kiteSpots.forEach(spot => {
        const isSelected = spot.id === selectedKiteId;
        const color = levelColors[spot.level] || '#a3a3a3';
        const size = isSelected ? 16 : 10;
        const el = document.createElement('div');
        el.style.cssText = `width:${size}px;height:${size}px;border-radius:50%;background:${color};border:2px solid ${isSelected ? '#fff' : 'rgba(255,255,255,0.6)'};cursor:pointer;transition:all 0.15s;box-shadow:${isSelected ? '0 0 8px rgba(6,182,212,0.8)' : '0 1px 3px rgba(0,0,0,0.5)'};`;
        el.addEventListener('click', (e) => { e.stopPropagation(); setSelectedKiteId(spot.id); });
        const marker = new mapboxgl.Marker({ element: el, draggable: true })
          .setLngLat([spot.longitude, spot.latitude]).addTo(map);
        marker.on('dragend', () => {
          const { lat, lng } = marker.getLngLat();
          setKiteSpots(prev => prev.map(s => s.id === spot.id ? {
            ...s,
            latitude: Math.round(lat * 10000) / 10000,
            longitude: Math.round(lng * 10000) / 10000
          } : s));
        });
        markersRef.current.set(spot.id, marker);
      });
    } else if (activeTab === 'surf') {
      const levelColors: Record<string, string> = {
        'Debutant': '#22c55e', 'Intermediaire': '#eab308',
        'Confirme': '#f97316', 'Expert': '#ef4444'
      };
      surfSpots.forEach(spot => {
        const isSelected = spot.id === selectedSurfId;
        const color = levelColors[spot.level] || '#a3a3a3';
        const size = isSelected ? 16 : 10;
        const el = document.createElement('div');
        el.style.cssText = `width:${size}px;height:${size}px;border-radius:3px;background:${color};border:2px solid ${isSelected ? '#fff' : 'rgba(255,255,255,0.6)'};cursor:pointer;transition:all 0.15s;box-shadow:${isSelected ? '0 0 8px rgba(6,182,212,0.8)' : '0 1px 3px rgba(0,0,0,0.5)'};`;
        el.addEventListener('click', (e) => { e.stopPropagation(); setSelectedSurfId(spot.id); });
        const marker = new mapboxgl.Marker({ element: el, draggable: true })
          .setLngLat([spot.longitude, spot.latitude]).addTo(map);
        marker.on('dragend', () => {
          const { lat, lng } = marker.getLngLat();
          setSurfSpots(prev => prev.map(s => s.id === spot.id ? {
            ...s,
            latitude: Math.round(lat * 10000) / 10000,
            longitude: Math.round(lng * 10000) / 10000
          } : s));
        });
        markersRef.current.set(spot.id, marker);
      });
    } else if (activeTab === 'stations') {
      stations.forEach(station => {
        if (station._hidden) return;
        const isSelected = station.stableId === selectedStationId;
        const color = WIND_SOURCE_COLORS[station.source] || '#a3a3a3';
        const size = isSelected ? 16 : station.isOnline ? 10 : 8;
        const opacity = station.isOnline ? 1 : 0.5;
        const el = document.createElement('div');
        el.style.cssText = `width:${size}px;height:${size}px;border-radius:50%;background:${color};opacity:${opacity};border:2px solid ${isSelected ? '#fff' : 'rgba(255,255,255,0.6)'};cursor:pointer;transition:all 0.15s;box-shadow:${isSelected ? '0 0 8px rgba(6,182,212,0.8)' : '0 1px 3px rgba(0,0,0,0.5)'};`;
        el.addEventListener('click', (e) => { e.stopPropagation(); setSelectedStationId(station.stableId); setCreatingStation(false); });
        const marker = new mapboxgl.Marker({ element: el, draggable: true })
          .setLngLat([station.longitude, station.latitude]).addTo(map);
        marker.on('dragend', () => {
          const { lat, lng } = marker.getLngLat();
          handleUpdateStationLocal(station.stableId, {
            latitude: Math.round(lat * 10000) / 10000,
            longitude: Math.round(lng * 10000) / 10000
          });
        });
        markersRef.current.set(station.stableId, marker);
      });
    }
  }, [activeTab, webcams, health, selectedWebcamId, kiteSpots, selectedKiteId, surfSpots, selectedSurfId, stations, selectedStationId]);

  // Fly to selected item
  useEffect(() => {
    if (!mapRef.current) return;
    let target: { lat: number; lng: number } | null = null;
    if (activeTab === 'webcams' && selectedWebcamId) {
      const w = webcams.find(w => w.id === selectedWebcamId);
      if (w) target = { lat: w.latitude, lng: w.longitude };
    } else if (activeTab === 'kite' && selectedKiteId) {
      const s = kiteSpots.find(s => s.id === selectedKiteId);
      if (s) target = { lat: s.latitude, lng: s.longitude };
    } else if (activeTab === 'surf' && selectedSurfId) {
      const s = surfSpots.find(s => s.id === selectedSurfId);
      if (s) target = { lat: s.latitude, lng: s.longitude };
    } else if (activeTab === 'stations' && selectedStationId) {
      const s = stations.find(s => s.stableId === selectedStationId);
      if (s) target = { lat: s.latitude, lng: s.longitude };
    }
    if (target) {
      mapRef.current.flyTo({ center: [target.lng, target.lat], zoom: Math.max(mapRef.current.getZoom(), 10), duration: 500 });
    }
  }, [selectedWebcamId, selectedKiteId, selectedSurfId, selectedStationId, activeTab]);

  // ============================================================
  // WEBCAM OPERATIONS
  // ============================================================

  function handleUpdateWebcamLocal(id: string, changes: Partial<Webcam>) {
    setWebcams(prev => prev.map(w => w.id === id ? { ...w, ...changes } : w));
    if (changes.latitude !== undefined || changes.longitude !== undefined) {
      const marker = markersRef.current.get(id);
      const webcam = webcams.find(w => w.id === id);
      if (marker && webcam) {
        marker.setLngLat([changes.longitude ?? webcam.longitude, changes.latitude ?? webcam.latitude]);
      }
    }
  }

  async function handleSaveWebcam(id: string, changes: Partial<Webcam>) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/webcams?id=${id}`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(changes)
      });
      const data = await res.json();
      if (res.ok) {
        showToast('Sauvegarde OK');
        // Update local state immediately from response (bypasses CDN cache)
        if (data.webcam) {
          setWebcams(prev => prev.map(w => w.id === id ? { ...w, ...data.webcam } : w));
        }
        setWebcamSaveVersion(v => v + 1);
        // Also refresh full list in background
        fetchWebcams();
      } else {
        showToast(`Erreur: ${data.error}`);
      }
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleDeleteWebcam(id: string) {
    if (!confirm(`Supprimer la webcam "${id}" ?`)) return;
    try {
      const res = await fetch(`${API_BASE}/admin/webcams?id=${id}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${password}` }
      });
      if (res.ok) { showToast('Webcam supprimee'); setSelectedWebcamId(null); await fetchWebcams(); }
    } catch { showToast('Erreur de suppression'); }
  }

  function handleAddWebcam() {
    const id = `new-${Date.now()}`;
    const newCam: Webcam = {
      id, name: 'Nouvelle webcam', location: '', region: 'Bretagne',
      latitude: 47.8, longitude: -3.5, imageUrl: '', streamUrl: null,
      source: 'Viewsurf', refreshInterval: 300, _isAddition: true
    };
    setWebcams(prev => [...prev, newCam]);
    setSelectedWebcamId(id);
    setCreatingWebcam(true);
    mapRef.current?.flyTo({ center: [-3.5, 47.8], zoom: 8 });
  }

  async function handleSaveNewWebcam(webcam: Webcam, changes: Partial<Webcam>) {
    setSaving(true);
    const fullObj = { ...webcam, ...changes };
    delete (fullObj as Record<string, unknown>)._isAddition;
    delete (fullObj as Record<string, unknown>)._hasOverride;
    try {
      const res = await fetch(`${API_BASE}/admin/webcams`, {
        method: 'POST', headers: authHeaders(), body: JSON.stringify(fullObj)
      });
      if (res.ok) { showToast('Webcam ajoutee'); setCreatingWebcam(false); await fetchWebcams(); setWebcamSaveVersion(v => v + 1); }
      else { const err = await res.json(); showToast(`Erreur: ${err.error}`); }
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleExportWebcams() {
    try {
      const res = await fetch(`${API_BASE}/admin/webcams?action=export`, { headers: { Authorization: `Bearer ${password}` } });
      const data = await res.json();
      setExportData(JSON.stringify(data.webcams, null, 2));
      setShowExport(true);
    } catch { showToast('Erreur export'); }
  }

  // ============================================================
  // KITE SPOT OPERATIONS
  // ============================================================

  async function handleSaveKiteSpot(spot: KiteSpot) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=kite_spots&id=${spot.id}`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(spot)
      });
      if (res.ok) { showToast('Spot kite sauvegarde'); await fetchKiteSpots(); }
      else showToast('Erreur sauvegarde');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleDeleteKiteSpot(id: string) {
    if (!confirm(`Supprimer le spot kite "${id}" ?`)) return;
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=kite_spots&id=${id}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${password}` }
      });
      if (res.ok) { showToast('Spot kite supprime'); setSelectedKiteId(null); await fetchKiteSpots(); }
      else showToast('Erreur suppression');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  function handleAddKiteSpot() {
    const id = `kite-${Date.now()}`;
    const newSpot: KiteSpot = {
      id, name: 'Nouveau spot', latitude: 47.8, longitude: -3.5,
      orientation: 'W,NW', level: 'Intermediaire', type: 'Plage',
      waveType: 'Petit', supportsKite: true, supportsWindsurf: true,
      supportsWing: true, supportsSurf: false, tidePreference: 'all'
    };
    setKiteSpots(prev => [...prev, newSpot]);
    setSelectedKiteId(id);
    mapRef.current?.flyTo({ center: [-3.5, 47.8], zoom: 8 });
  }

  async function handleImportKiteSpots() {
    const input = prompt('Collez le JSON des spots kite (tableau JSON):');
    if (!input) return;
    try {
      const spots = JSON.parse(input);
      if (!Array.isArray(spots)) { showToast('Format invalide (tableau attendu)'); return; }
      setSaving(true);
      const res = await fetch(`${API_BASE}/admin/config?type=kite_spots`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(spots)
      });
      if (res.ok) { showToast(`${spots.length} spots importes`); await fetchKiteSpots(); }
      else showToast('Erreur import');
      setSaving(false);
    } catch { showToast('JSON invalide'); setSaving(false); }
  }

  // ============================================================
  // SURF SPOT OPERATIONS
  // ============================================================

  async function handleSaveSurfSpot(spot: SurfSpot) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=surf_spots&id=${spot.id}`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(spot)
      });
      if (res.ok) { showToast('Spot surf sauvegarde'); await fetchSurfSpots(); }
      else showToast('Erreur sauvegarde');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleDeleteSurfSpot(id: string) {
    if (!confirm(`Supprimer le spot surf "${id}" ?`)) return;
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=surf_spots&id=${id}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${password}` }
      });
      if (res.ok) { showToast('Spot surf supprime'); setSelectedSurfId(null); await fetchSurfSpots(); }
      else showToast('Erreur suppression');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  function handleAddSurfSpot() {
    const id = `surf-${Date.now()}`;
    const newSpot: SurfSpot = {
      id, name: 'Nouveau spot', latitude: 47.8, longitude: -3.5,
      level: 'Intermediaire', waveType: 'Beach Break', bottomType: 'Sable',
      orientation: 'W', idealSwellDirMin: 250, idealSwellDirMax: 310,
      idealSwellSizeMin: 0.5, idealSwellSizeMax: 2.0,
      idealPeriodMin: 8, idealPeriodMax: 15, idealTide: 'Toutes marees',
      description: '', hazards: '', crowd: 'Modere', consistency: 3
    };
    setSurfSpots(prev => [...prev, newSpot]);
    setSelectedSurfId(id);
    mapRef.current?.flyTo({ center: [-3.5, 47.8], zoom: 8 });
  }

  async function handleImportSurfSpots() {
    const input = prompt('Collez le JSON des spots surf (tableau JSON):');
    if (!input) return;
    try {
      const spots = JSON.parse(input);
      if (!Array.isArray(spots)) { showToast('Format invalide (tableau attendu)'); return; }
      setSaving(true);
      const res = await fetch(`${API_BASE}/admin/config?type=surf_spots`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(spots)
      });
      if (res.ok) { showToast(`${spots.length} spots importes`); await fetchSurfSpots(); }
      else showToast('Erreur import');
      setSaving(false);
    } catch { showToast('JSON invalide'); setSaving(false); }
  }

  // ============================================================
  // STATION OPERATIONS
  // ============================================================

  function handleUpdateStationLocal(stableId: string, changes: Partial<WindStation>) {
    setStations(prev => prev.map(s => s.stableId === stableId ? { ...s, ...changes } : s));
    if (changes.latitude !== undefined || changes.longitude !== undefined) {
      const marker = markersRef.current.get(stableId);
      const station = stations.find(s => s.stableId === stableId);
      if (marker && station) {
        marker.setLngLat([changes.longitude ?? station.longitude, changes.latitude ?? station.latitude]);
      }
    }
  }

  async function handleSaveStation(stableId: string, changes: Partial<WindStation>) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/stations?id=${encodeURIComponent(stableId)}`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(changes)
      });
      if (res.ok) { showToast('Station sauvegardee'); await fetchStations(); }
      else { const err = await res.json(); showToast(`Erreur: ${err.error}`); }
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleDeleteStation(stableId: string) {
    const station = stations.find(s => s.stableId === stableId);
    const action = station?._isAddition ? 'supprimer' : 'masquer';
    if (!confirm(`${action === 'supprimer' ? 'Supprimer' : 'Masquer'} la station "${station?.name}" ?`)) return;
    try {
      const res = await fetch(`${API_BASE}/admin/stations?id=${encodeURIComponent(stableId)}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${password}` }
      });
      if (res.ok) { showToast(action === 'supprimer' ? 'Station supprimee' : 'Station masquee'); setSelectedStationId(null); await fetchStations(); }
    } catch { showToast('Erreur'); }
  }

  function handleAddStation() {
    const stableId = `custom_${Date.now()}`;
    const newStation: WindStation = {
      stableId,
      id: String(Date.now()),
      name: 'Nouvelle station',
      latitude: 47.8,
      longitude: -3.5,
      wind: 0,
      gust: 0,
      direction: 0,
      isOnline: false,
      source: 'custom',
      ts: null,
      _isAddition: true,
    };
    setStations(prev => [...prev, newStation]);
    setSelectedStationId(stableId);
    setCreatingStation(true);
    mapRef.current?.flyTo({ center: [-3.5, 47.8], zoom: 8 });
  }

  async function handleSaveNewStation(station: WindStation, changes: Partial<WindStation>) {
    setSaving(true);
    const fullObj = { ...station, ...changes };
    delete (fullObj as Record<string, unknown>)._isAddition;
    delete (fullObj as Record<string, unknown>)._hasOverride;
    try {
      const res = await fetch(`${API_BASE}/admin/stations`, {
        method: 'POST', headers: authHeaders(), body: JSON.stringify(fullObj)
      });
      if (res.ok) { showToast('Station ajoutee'); setCreatingStation(false); await fetchStations(); }
      else { const err = await res.json(); showToast(`Erreur: ${err.error}`); }
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  async function handleExportStations() {
    try {
      const res = await fetch(`${API_BASE}/admin/stations?action=export`, { headers: { Authorization: `Bearer ${password}` } });
      const data = await res.json();
      setExportData(JSON.stringify(data.stations, null, 2));
      setShowExport(true);
    } catch { showToast('Erreur export'); }
  }

  async function handleRestoreStation(stableId: string) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/stations?id=${encodeURIComponent(stableId)}`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify({ _hidden: false })
      });
      if (res.ok) { showToast('Station restauree'); await fetchStations(); }
    } catch { showToast('Erreur'); }
    setSaving(false);
  }

  // ============================================================
  // CONFIG OPERATIONS
  // ============================================================

  async function handleSaveConfig(config: AppConfig) {
    setSaving(true);
    try {
      const res = await fetch(`${API_BASE}/admin/config?type=app_config`, {
        method: 'PUT', headers: authHeaders(), body: JSON.stringify(config)
      });
      if (res.ok) { showToast('Configuration sauvegardee'); setAppConfig(config); }
      else showToast('Erreur sauvegarde');
    } catch { showToast('Erreur de connexion'); }
    setSaving(false);
  }

  // ============================================================
  // FILTERS
  // ============================================================

  const filteredWebcams = webcams.filter(w => {
    if (webcamSearch) {
      const q = webcamSearch.toLowerCase();
      if (![w.id, w.name, w.location, w.region].some(v => v?.toLowerCase().includes(q))) return false;
    }
    if (regionFilter !== 'Tous' && w.region !== regionFilter) return false;
    if (sourceFilter !== 'Tous' && w.source !== sourceFilter) return false;
    if (statusFilter === 'Online' && health[w.id]?.online === false) return false;
    if (statusFilter === 'Offline' && health[w.id]?.online !== false) return false;
    if (statusFilter === 'Modifie' && !w._hasOverride && !w._isAddition) return false;
    if (statusFilter === 'Verifie' && !w._verified) return false;
    if (statusFilter === 'Non verifie' && w._verified) return false;
    return true;
  });

  const filteredKiteSpots = kiteSpots.filter(s => {
    if (kiteSearch) {
      const q = kiteSearch.toLowerCase();
      if (![s.id, s.name, s.orientation].some(v => v?.toLowerCase().includes(q))) return false;
    }
    if (kiteLevelFilter !== 'Tous' && s.level !== kiteLevelFilter) return false;
    return true;
  });

  const filteredSurfSpots = surfSpots.filter(s => {
    if (surfSearch) {
      const q = surfSearch.toLowerCase();
      if (![s.id, s.name, s.description].some(v => v?.toLowerCase().includes(q))) return false;
    }
    if (surfLevelFilter !== 'Tous' && s.level !== surfLevelFilter) return false;
    return true;
  });

  const filteredStations = stations.filter(s => {
    if (stationSearch) {
      const q = stationSearch.toLowerCase();
      if (![s.stableId, s.name, s.source, s.region].some(v => v?.toLowerCase().includes(q))) return false;
    }
    if (stationSourceFilter !== 'Tous' && s.source !== stationSourceFilter) return false;
    if (stationStatusFilter === 'Online' && !s.isOnline) return false;
    if (stationStatusFilter === 'Offline' && s.isOnline) return false;
    if (stationStatusFilter === 'Modifie' && !s._hasOverride) return false;
    if (stationStatusFilter === 'Masque' && !s._hidden) return false;
    if (stationStatusFilter === 'Custom' && !s._isAddition) return false;
    if (stationRegionFilter !== 'Tous' && s.region !== stationRegionFilter) return false;
    return true;
  });

  const selectedWebcam = webcams.find(w => w.id === selectedWebcamId);
  const selectedKiteSpot = kiteSpots.find(s => s.id === selectedKiteId);
  const selectedSurfSpot = surfSpots.find(s => s.id === selectedSurfId);
  const selectedStation = stations.find(s => s.stableId === selectedStationId);

  if (!password) return <LoginGate onLogin={setPassword} />;

  // ============================================================
  // RENDER TABS
  // ============================================================

  const pendingAiCount = aiSuggestions.filter(s => s.status === 'pending').length;
  const tabs: { key: AdminTab; label: string; count?: number; badge?: number }[] = [
    { key: 'webcams', label: 'Webcams', count: webcams.length },
    { key: 'kite', label: 'Spots Kite', count: kiteSpots.length },
    { key: 'surf', label: 'Spots Surf', count: surfSpots.length },
    { key: 'stations', label: 'Stations', count: stations.length },
    { key: 'config', label: 'Config' },
    { key: 'ai', label: 'IA', badge: pendingAiCount },
  ];

  function renderSidebar() {
    if (activeTab === 'webcams') {
      if (selectedWebcam) {
        return (
          <WebcamEditor
            key={`${selectedWebcam.id}-${webcamSaveVersion}`}
            webcam={selectedWebcam}
            onSave={(changes) => {
              if (selectedWebcam._isAddition && creatingWebcam) handleSaveNewWebcam(selectedWebcam, changes);
              else handleSaveWebcam(selectedWebcam.id, changes);
            }}
            onDelete={() => handleDeleteWebcam(selectedWebcam.id)}
            onClose={() => { setSelectedWebcamId(null); setCreatingWebcam(false); }}
            saving={saving}
          />
        );
      }
      return (
        <>
          <div className="p-3 border-b border-white/10 space-y-2">
            <input type="text" placeholder="Rechercher..." value={webcamSearch}
              onChange={e => setWebcamSearch(e.target.value)}
              className="w-full p-2 rounded-lg bg-[#2a2a2a] text-white text-sm border border-white/10 outline-none focus:border-cyan-500" />
            <div className="flex gap-1 flex-wrap">
              {['Tous', 'Online', 'Offline', 'Modifie', 'Verifie', 'Non verifie'].map(s => (
                <button key={s} onClick={() => setStatusFilter(s)}
                  className={`px-2 py-1 rounded text-xs transition ${statusFilter === s ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {s === 'Verifie' ? `\u2705 ${s}` : s === 'Non verifie' ? `\u2753 ${s}` : s}
                </button>
              ))}
            </div>
            <div className="flex gap-1 flex-wrap">
              {WEBCAM_SOURCES.map(s => (
                <button key={s} onClick={() => setSourceFilter(s)}
                  className={`px-2 py-1 rounded text-xs transition ${sourceFilter === s ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {s}
                </button>
              ))}
            </div>
            <select value={regionFilter} onChange={e => setRegionFilter(e.target.value)}
              className="w-full p-2 rounded bg-[#2a2a2a] text-white text-xs border border-white/10">
              {REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>
          <div className="flex-1 overflow-y-auto">
            {webcamLoading ? (
              <div className="p-8 text-center text-white/30">Chargement...</div>
            ) : (
              <>
                <div className="px-3 py-1.5 text-white/30 text-xs">{filteredWebcams.length} resultats</div>
                {filteredWebcams.map(w => (
                  <WebcamCard key={w.id} webcam={w} health={health[w.id]} isSelected={w.id === selectedWebcamId}
                    onClick={() => setSelectedWebcamId(w.id)} />
                ))}
              </>
            )}
          </div>
        </>
      );
    }

    if (activeTab === 'kite') {
      if (selectedKiteSpot) {
        return (
          <KiteSpotEditor
            spot={selectedKiteSpot}
            onSave={handleSaveKiteSpot}
            onDelete={() => handleDeleteKiteSpot(selectedKiteSpot.id)}
            onClose={() => setSelectedKiteId(null)}
            saving={saving}
          />
        );
      }
      return (
        <>
          <div className="p-3 border-b border-white/10 space-y-2">
            <input type="text" placeholder="Rechercher spot..." value={kiteSearch}
              onChange={e => setKiteSearch(e.target.value)}
              className="w-full p-2 rounded-lg bg-[#2a2a2a] text-white text-sm border border-white/10 outline-none focus:border-cyan-500" />
            <div className="flex gap-1 flex-wrap">
              {['Tous', ...KITE_LEVELS].map(l => (
                <button key={l} onClick={() => setKiteLevelFilter(l)}
                  className={`px-2 py-1 rounded text-xs transition ${kiteLevelFilter === l ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {l}
                </button>
              ))}
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">
            {kiteLoading ? (
              <div className="p-8 text-center text-white/30">Chargement...</div>
            ) : kiteSpots.length === 0 ? (
              <div className="p-8 text-center text-white/30">
                <p className="mb-4">Aucun spot kite</p>
                <p className="text-xs text-white/20 mb-4">Ajoutez des spots manuellement ou importez un JSON</p>
              </div>
            ) : (
              <>
                <div className="px-3 py-1.5 text-white/30 text-xs">{filteredKiteSpots.length} spots</div>
                {filteredKiteSpots.map(s => (
                  <KiteSpotCard key={s.id} spot={s} isSelected={s.id === selectedKiteId}
                    onClick={() => setSelectedKiteId(s.id)} />
                ))}
              </>
            )}
          </div>
        </>
      );
    }

    if (activeTab === 'surf') {
      if (selectedSurfSpot) {
        return (
          <SurfSpotEditor
            spot={selectedSurfSpot}
            onSave={handleSaveSurfSpot}
            onDelete={() => handleDeleteSurfSpot(selectedSurfSpot.id)}
            onClose={() => setSelectedSurfId(null)}
            saving={saving}
          />
        );
      }
      return (
        <>
          <div className="p-3 border-b border-white/10 space-y-2">
            <input type="text" placeholder="Rechercher spot..." value={surfSearch}
              onChange={e => setSurfSearch(e.target.value)}
              className="w-full p-2 rounded-lg bg-[#2a2a2a] text-white text-sm border border-white/10 outline-none focus:border-cyan-500" />
            <div className="flex gap-1 flex-wrap">
              {['Tous', ...SURF_LEVELS].map(l => (
                <button key={l} onClick={() => setSurfLevelFilter(l)}
                  className={`px-2 py-1 rounded text-xs transition ${surfLevelFilter === l ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {l}
                </button>
              ))}
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">
            {surfLoading ? (
              <div className="p-8 text-center text-white/30">Chargement...</div>
            ) : surfSpots.length === 0 ? (
              <div className="p-8 text-center text-white/30">
                <p className="mb-4">Aucun spot surf</p>
                <p className="text-xs text-white/20 mb-4">Ajoutez des spots manuellement ou importez un JSON</p>
              </div>
            ) : (
              <>
                <div className="px-3 py-1.5 text-white/30 text-xs">{filteredSurfSpots.length} spots</div>
                {filteredSurfSpots.map(s => (
                  <SurfSpotCard key={s.id} spot={s} isSelected={s.id === selectedSurfId}
                    onClick={() => setSelectedSurfId(s.id)} />
                ))}
              </>
            )}
          </div>
        </>
      );
    }

    if (activeTab === 'stations') {
      if (selectedStation) {
        return (
          <StationEditor
            station={selectedStation}
            onSave={(changes) => {
              if (selectedStation._isAddition && creatingStation) handleSaveNewStation(selectedStation, changes);
              else handleSaveStation(selectedStation.stableId, changes);
            }}
            onDelete={() => handleDeleteStation(selectedStation.stableId)}
            onRestore={selectedStation._hidden ? () => handleRestoreStation(selectedStation.stableId) : undefined}
            onClose={() => { setSelectedStationId(null); setCreatingStation(false); }}
            saving={saving}
            webcams={webcams}
            kiteSpots={kiteSpots}
          />
        );
      }
      return (
        <>
          <div className="p-3 border-b border-white/10 space-y-2">
            <input type="text" placeholder="Rechercher station..." value={stationSearch}
              onChange={e => setStationSearch(e.target.value)}
              className="w-full p-2 rounded-lg bg-[#2a2a2a] text-white text-sm border border-white/10 outline-none focus:border-cyan-500" />
            <div className="flex gap-1 flex-wrap">
              {STATION_STATUS_FILTERS.map(s => (
                <button key={s} onClick={() => setStationStatusFilter(s)}
                  className={`px-2 py-1 rounded text-xs transition ${stationStatusFilter === s ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {s}
                </button>
              ))}
            </div>
            <div className="flex gap-1 flex-wrap">
              {WIND_SOURCES.map(s => (
                <button key={s} onClick={() => setStationSourceFilter(s)}
                  className={`px-2 py-1 rounded text-xs transition flex items-center gap-1 ${stationSourceFilter === s ? 'bg-cyan-700 text-white' : 'bg-[#2a2a2a] text-white/50 hover:text-white'}`}>
                  {s !== 'Tous' && <span className="w-2 h-2 rounded-full" style={{ backgroundColor: WIND_SOURCE_COLORS[s] }} />}
                  {WIND_SOURCE_LABELS[s] || s}
                </button>
              ))}
            </div>
            <select value={stationRegionFilter} onChange={e => setStationRegionFilter(e.target.value)}
              className="w-full p-2 rounded bg-[#2a2a2a] text-white text-xs border border-white/10">
              {REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>
          <div className="flex-1 overflow-y-auto">
            {stationLoading ? (
              <div className="p-8 text-center text-white/30">Chargement...</div>
            ) : stations.length === 0 ? (
              <div className="p-8 text-center text-white/30">
                <p className="mb-4">Aucune station</p>
                <p className="text-xs text-white/20">Les stations seront chargees depuis les APIs</p>
              </div>
            ) : (
              <>
                <div className="px-3 py-1.5 text-white/30 text-xs flex items-center justify-between">
                  <span>{filteredStations.length} / {stations.length} stations</span>
                  {stationStats && (
                    <span className="text-white/20">
                      {stationStats.online} online &middot; {stationStats.offline} offline
                    </span>
                  )}
                </div>
                {filteredStations.map(s => (
                  <StationCard key={s.stableId} station={s} isSelected={s.stableId === selectedStationId}
                    onClick={() => { setSelectedStationId(s.stableId); setCreatingStation(false); }} />
                ))}
              </>
            )}
          </div>
        </>
      );
    }

    // Config tab - full width, no sidebar split
    return null;
  }

  return (
    <div className="h-screen bg-[#0a0a0a] text-white flex flex-col">
      {/* Toolbar */}
      <div className="h-12 bg-[#111] border-b border-white/10 flex items-center px-4 gap-2 shrink-0">
        {/* Tabs */}
        {tabs.map(tab => (
          <button key={tab.key} onClick={() => {
            setActiveTab(tab.key);
            setSelectedWebcamId(null); setSelectedKiteId(null); setSelectedSurfId(null); setSelectedStationId(null);
            setCreatingWebcam(false); setCreatingStation(false);
          }}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition ${
              activeTab === tab.key
                ? 'bg-cyan-700 text-white'
                : 'bg-[#1a1a1a] text-white/50 hover:text-white hover:bg-[#2a2a2a]'
            }`}>
            {tab.label}
            {tab.count !== undefined && <span className="ml-1 text-white/30">{tab.count}</span>}
            {tab.badge ? <span className="ml-1 bg-red-600 text-white text-[10px] px-1.5 py-0.5 rounded-full font-bold">{tab.badge}</span> : null}
          </button>
        ))}

        <div className="flex-1" />

        {/* Tab-specific toolbar actions */}
        {activeTab === 'webcams' && (
          <>
            <span className="text-green-400/60 text-xs">{'\u2705'} {webcams.filter(w => w._verified).length}/{webcams.length}</span>
            <button onClick={handleAddWebcam}
              className="px-3 py-1.5 rounded-lg bg-green-700 hover:bg-green-600 text-xs font-semibold transition">+ Ajouter</button>
            <button onClick={handleExportWebcams}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Export</button>
            <button onClick={fetchWebcams}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
          </>
        )}
        {activeTab === 'kite' && (
          <>
            <button onClick={handleAddKiteSpot}
              className="px-3 py-1.5 rounded-lg bg-green-700 hover:bg-green-600 text-xs font-semibold transition">+ Ajouter</button>
            <button onClick={handleImportKiteSpots}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Import JSON</button>
            <button onClick={() => {
              setExportData(JSON.stringify(kiteSpots, null, 2)); setShowExport(true);
            }}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Export</button>
            <button onClick={fetchKiteSpots}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
          </>
        )}
        {activeTab === 'surf' && (
          <>
            <button onClick={handleAddSurfSpot}
              className="px-3 py-1.5 rounded-lg bg-green-700 hover:bg-green-600 text-xs font-semibold transition">+ Ajouter</button>
            <button onClick={handleImportSurfSpots}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Import JSON</button>
            <button onClick={() => {
              setExportData(JSON.stringify(surfSpots, null, 2)); setShowExport(true);
            }}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Export</button>
            <button onClick={fetchSurfSpots}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
          </>
        )}
        {activeTab === 'stations' && (
          <>
            {stationStats && (
              <span className="text-white/40 text-xs">
                {stationStats.online}/{stationStats.total} online &middot;
                {Object.entries(stationStats.sources || {}).slice(0, 3).map(([k, v]) => ` ${k}: ${v}`).join(' &middot;')}
              </span>
            )}
            <button onClick={handleAddStation}
              className="px-3 py-1.5 rounded-lg bg-green-700 hover:bg-green-600 text-xs font-semibold transition">+ Ajouter</button>
            <button onClick={handleExportStations}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Export</button>
            <button onClick={fetchStations}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
          </>
        )}
        {activeTab === 'config' && (
          <button onClick={fetchConfig}
            className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
        )}
        {activeTab === 'ai' && (
          <>
            <button onClick={() => runAiAnalysis('offline')} disabled={aiAnalyzing}
              className="px-3 py-1.5 rounded-lg bg-purple-700 hover:bg-purple-600 disabled:opacity-50 text-xs font-semibold transition">
              {aiAnalyzing ? 'Analyse en cours...' : 'Analyser offline'}
            </button>
            <button onClick={() => runAiAnalysis('all')} disabled={aiAnalyzing}
              className="px-3 py-1.5 rounded-lg bg-purple-900 hover:bg-purple-800 disabled:opacity-50 text-xs transition">
              {aiAnalyzing ? '...' : 'Analyser tout'}
            </button>
            <button onClick={fetchAiSuggestions}
              className="px-3 py-1.5 rounded-lg bg-[#2a2a2a] hover:bg-[#3a3a3a] text-xs transition">Reload</button>
          </>
        )}
      </div>

      {/* Main content */}
      <div className="flex-1 flex overflow-hidden relative">
        {/* Map + Sidebar: always rendered (never display:none) so Mapbox keeps its dimensions */}
        <div className="flex-1 flex">
          {/* Map */}
          <div className="flex-[3] relative">
            <div ref={mapContainer} className="absolute inset-0" />
            {/* Map search bar - only show on map tabs */}
            {activeTab !== 'ai' && activeTab !== 'config' && (
              <div className="absolute top-3 right-3 z-10 w-72">
                <input
                  type="text"
                  value={mapSearchQuery}
                  onChange={e => handleMapSearch(e.target.value)}
                  placeholder="Rechercher un lieu..."
                  className="w-full bg-black/80 text-white text-sm px-3 py-2 rounded-lg border border-white/20 placeholder:text-white/40 backdrop-blur-sm outline-none focus:border-white/50"
                />
                {mapSearchResults.length > 0 && (
                  <div className="mt-1 bg-black/90 border border-white/20 rounded-lg overflow-hidden backdrop-blur-sm">
                    {mapSearchResults.map((r, i) => (
                      <button key={i} onClick={() => selectMapSearchResult(r.center)}
                        className="w-full text-left text-xs text-white/90 px-3 py-2 hover:bg-white/10 border-b border-white/5 last:border-0 truncate">
                        {r.place_name}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
            {creatingWebcam && (
              <div className="absolute top-4 left-1/2 -translate-x-1/2 bg-green-800/90 text-white text-xs px-4 py-2 rounded-full z-10">
                Cliquez sur la carte pour positionner ou glissez le marqueur
              </div>
            )}
            {creatingStation && (
              <div className="absolute top-4 left-1/2 -translate-x-1/2 bg-purple-800/90 text-white text-xs px-4 py-2 rounded-full z-10">
                Glissez le marqueur pour positionner la station
              </div>
            )}
          </div>
          {/* Sidebar - only show on map tabs */}
          {activeTab !== 'ai' && activeTab !== 'config' && (
            <div className="flex-[2] flex flex-col min-w-[320px] max-w-[500px] border-l border-white/10">
              {renderSidebar()}
            </div>
          )}
        </div>

        {/* AI tab: full width overlay on top of map */}
        {activeTab === 'ai' && (
          <div className="absolute inset-0 bg-[#0a0a0a] z-20 overflow-y-auto p-6">
            <div className="max-w-6xl mx-auto space-y-8">
              {/* Webcam AI Section */}
              <div className="border border-white/10 rounded-xl p-4">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">📷</span>
                    <div>
                      <h2 className="text-white font-semibold">Webcam AI</h2>
                      <p className="text-white/40 text-xs">Detection d'images cassees, positions incorrectes, doublons</p>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => runAiAnalysis('offline')} disabled={aiAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-purple-700 hover:bg-purple-600 disabled:opacity-50 text-xs transition">
                      {aiAnalyzing ? '...' : 'Analyser offline'}
                    </button>
                    <button onClick={() => runAiAnalysis('all')} disabled={aiAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-purple-900 hover:bg-purple-800 disabled:opacity-50 text-xs transition">
                      Analyser tout
                    </button>
                  </div>
                </div>
                {aiLoading ? (
                  <div className="text-center text-white/30 py-8">Chargement...</div>
                ) : aiSuggestions.length === 0 ? (
                  <div className="text-center text-white/30 py-4 text-sm">Aucune suggestion webcam</div>
                ) : (
                  <div className="space-y-3">
                    {aiSuggestions.filter(s => s.status === 'pending').slice(0, 5).map(s => {
                      const severityColors = { high: 'border-red-500/30', medium: 'border-yellow-500/30', low: 'border-blue-500/30' };
                      const typeLabels: Record<string, string> = {
                        location_mismatch: 'Position', image_broken: 'Image cassee', image_mismatch: 'Image incorrecte',
                        duplicate: 'Doublon', offline_chronic: 'Offline', url_fix: 'URL'
                      };
                      return (
                        <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg bg-white/5 border ${severityColors[s.severity]}`}>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="text-white text-sm font-medium truncate">{s.webcamName}</span>
                              <span className="px-1.5 py-0.5 bg-white/10 rounded text-[10px] text-white/60">{typeLabels[s.type]}</span>
                            </div>
                            <div className="text-white/40 text-xs truncate">{s.description}</div>
                          </div>
                          <div className="flex gap-1">
                            <button onClick={() => handleAiAction(s.id, 'approve')} className="px-2 py-1 rounded bg-green-700 hover:bg-green-600 text-[10px]">OK</button>
                            <button onClick={() => handleAiAction(s.id, 'reject')} className="px-2 py-1 rounded bg-red-800 hover:bg-red-700 text-[10px]">X</button>
                          </div>
                        </div>
                      );
                    })}
                    {aiSuggestions.length > 5 && (
                      <div className="text-center text-white/30 text-xs">+{aiSuggestions.length - 5} autres suggestions</div>
                    )}
                  </div>
                )}
              </div>

              {/* Station AI Section */}
              <div className="border border-white/10 rounded-xl p-4">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">📡</span>
                    <div>
                      <h2 className="text-white font-semibold">Station AI</h2>
                      <p className="text-white/40 text-xs">Doublons, offline chroniques, donnees suspectes, anomalies</p>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => runStationAiAnalysis('duplicates')} disabled={stationAiAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-cyan-700 hover:bg-cyan-600 disabled:opacity-50 text-xs transition">
                      {stationAiAnalyzing ? '...' : 'Doublons'}
                    </button>
                    <button onClick={() => runStationAiAnalysis('quality')} disabled={stationAiAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-cyan-800 hover:bg-cyan-700 disabled:opacity-50 text-xs transition">
                      Qualite
                    </button>
                    <button onClick={() => runStationAiAnalysis('all')} disabled={stationAiAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-cyan-900 hover:bg-cyan-800 disabled:opacity-50 text-xs transition">
                      Tout
                    </button>
                  </div>
                </div>
                {stationAiLoading ? (
                  <div className="text-center text-white/30 py-8">Chargement...</div>
                ) : stationAiSuggestions.length === 0 ? (
                  <div className="text-center text-white/30 py-4 text-sm">Aucun probleme de station detecte</div>
                ) : (
                  <div className="space-y-3">
                    {stationAiSuggestions.filter(s => s.status === 'pending').slice(0, 8).map(s => {
                      const severityColors = { high: 'border-red-500/30', medium: 'border-yellow-500/30', low: 'border-blue-500/30' };
                      const typeLabels: Record<string, string> = {
                        duplicate: 'Doublon', chronic_offline: 'Offline', suspicious_data: 'Suspect',
                        data_anomaly: 'Anomalie', location_anomaly: 'Position', missing_metadata: 'Metadata'
                      };
                      return (
                        <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg bg-white/5 border ${severityColors[s.severity]}`}>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="text-white text-sm font-medium truncate">{s.stationName}</span>
                              <span className="px-1.5 py-0.5 bg-white/10 rounded text-[10px] text-white/60">{typeLabels[s.type]}</span>
                            </div>
                            <div className="text-white/40 text-xs truncate">{s.description}</div>
                          </div>
                          <div className="flex gap-1">
                            <button onClick={() => handleStationAiAction(s.id, 'approve')} className="px-2 py-1 rounded bg-green-700 hover:bg-green-600 text-[10px]">OK</button>
                            <button onClick={() => handleStationAiAction(s.id, 'reject')} className="px-2 py-1 rounded bg-red-800 hover:bg-red-700 text-[10px]">X</button>
                            <button onClick={() => {
                              setActiveTab('stations');
                              setSelectedStationId(s.stableId);
                            }} className="px-2 py-1 rounded bg-[#2a2a2a] hover:bg-[#3a3a3a] text-[10px]">Voir</button>
                          </div>
                        </div>
                      );
                    })}
                    {stationAiSuggestions.length > 8 && (
                      <div className="text-center text-white/30 text-xs">+{stationAiSuggestions.length - 8} autres problemes</div>
                    )}
                  </div>
                )}
              </div>

              {/* Webcam Weather AI Section */}
              <div className="border border-white/10 rounded-xl p-4">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">🌤️</span>
                    <div>
                      <h2 className="text-white font-semibold">Webcam Weather AI</h2>
                      <p className="text-white/40 text-xs">Analyse visuelle: meteo, houle, visibilite, affluence</p>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => runWebcamWeatherAnalysis(5)} disabled={webcamWeatherAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-orange-700 hover:bg-orange-600 disabled:opacity-50 text-xs transition">
                      {webcamWeatherAnalyzing ? '...' : 'Analyser 5'}
                    </button>
                    <button onClick={() => runWebcamWeatherAnalysis(20)} disabled={webcamWeatherAnalyzing}
                      className="px-3 py-1.5 rounded-lg bg-orange-800 hover:bg-orange-700 disabled:opacity-50 text-xs transition">
                      Analyser 20
                    </button>
                  </div>
                </div>
                {webcamWeatherLoading ? (
                  <div className="text-center text-white/30 py-8">Chargement...</div>
                ) : webcamWeather.length === 0 ? (
                  <div className="text-center text-white/30 py-4 text-sm">Aucune analyse meteo. Lancez une analyse.</div>
                ) : (
                  <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                    {webcamWeather.slice(0, 12).map(w => {
                      const weatherEmoji: Record<string, string> = {
                        sunny: '☀️', partly_cloudy: '⛅', cloudy: '☁️', overcast: '🌫️',
                        rainy: '🌧️', foggy: '🌫️', stormy: '⛈️', unknown: '❓'
                      };
                      const seaEmoji: Record<string, string> = {
                        flat: '🏊', small: '🌊', medium: '🌊🌊', big: '🌊🌊🌊', rough: '💨', not_visible: '❓'
                      };
                      const crowdEmoji: Record<string, string> = {
                        empty: '🏖️', few: '👤', moderate: '👥', crowded: '👥👥', not_visible: '❓'
                      };
                      return (
                        <div key={w.webcamId} className="p-3 rounded-lg bg-white/5 border border-white/10">
                          <div className="text-white text-xs font-medium truncate mb-2">{w.webcamName}</div>
                          <div className="flex items-center gap-2 text-lg mb-1">
                            <span title={w.weather}>{weatherEmoji[w.weather] || '❓'}</span>
                            <span title={w.sea_state}>{seaEmoji[w.sea_state] || ''}</span>
                            <span title={w.crowd}>{crowdEmoji[w.crowd] || ''}</span>
                          </div>
                          <div className="text-white/30 text-[10px]">
                            Visibilite: {w.visibility} &middot; Vent: {w.wind_signs}
                          </div>
                          <div className="text-white/20 text-[9px] mt-1">
                            {new Date(w.analyzedAt).toLocaleString('fr', { hour: '2-digit', minute: '2-digit' })} &middot; {Math.round(w.confidence * 100)}%
                          </div>
                          {w.notes && <div className="text-white/40 text-[10px] mt-1 italic">{w.notes}</div>}
                        </div>
                      );
                    })}
                  </div>
                )}
                {webcamWeather.length > 12 && (
                  <div className="text-center text-white/30 text-xs mt-3">+{webcamWeather.length - 12} autres webcams analysees</div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Config tab: overlay on top of map */}
        {activeTab === 'config' && (
          <div className="absolute inset-0 bg-[#0a0a0a] z-20">
            {configLoading ? (
              <div className="flex-1 h-full flex items-center justify-center text-white/30">Chargement...</div>
            ) : (
              <AppConfigPanel config={appConfig} onSave={handleSaveConfig} saving={saving} />
            )}
          </div>
        )}
      </div>

      {/* Export Modal */}
      {showExport && (
        <div className="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-8">
          <div className="bg-[#1a1a1a] rounded-2xl border border-white/10 w-full max-w-4xl max-h-[80vh] flex flex-col">
            <div className="p-4 border-b border-white/10 flex items-center justify-between">
              <h2 className="text-white font-semibold">Export JSON</h2>
              <div className="flex gap-2">
                <button onClick={() => { navigator.clipboard.writeText(exportData); showToast('Copie!'); }}
                  className="px-3 py-1.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-xs font-semibold transition">Copier</button>
                <button onClick={() => setShowExport(false)}
                  className="text-white/40 hover:text-white text-lg px-2">&times;</button>
              </div>
            </div>
            <pre className="flex-1 overflow-auto p-4 text-xs text-green-400 font-mono">{exportData}</pre>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[#2a2a2a] text-white text-sm px-4 py-2 rounded-lg border border-white/10 shadow-lg z-50 animate-pulse">
          {toast}
        </div>
      )}
    </div>
  );
}
