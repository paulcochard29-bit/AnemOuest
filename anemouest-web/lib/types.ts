// Shared types for AnemOuest web app

// ===== Forecast =====

export type ForecastModel = 'arome' | 'ecmwf' | 'gfs' | 'icon'

export interface ForecastPoint {
  time: string
  windSpeed: number // knots
  windGust: number // knots
  windDirection: number // degrees
  temperature: number // °C
  humidity: number // %
  cloudCoverHigh: number // %
  cloudCoverMid: number // %
  cloudCoverLow: number // %
  precipitation: number // mm
  weatherCode: number
  visibility: number // m
  pressure: number // hPa
  uvIndex: number // 0-11+
}

export interface DailyForecast {
  date: string
  maxWind: number
  maxGust: number
  avgDir: number
  maxTemp: number
  minTemp: number
  precipitationSum: number
  weatherCode: number
}

export interface MarinePoint {
  time: string
  waveHeight: number
  wavePeriod: number
  waveDirection: number
  swellHeight: number
  swellPeriod: number
  swellDirection: number
  windWaveHeight: number
  windWavePeriod: number
  windWaveDirection: number
}

export interface ForecastResponse {
  model: ForecastModel
  lat: number
  lon: number
  points: ForecastPoint[]
  daily: DailyForecast[]
}

export interface MarineResponse {
  lat: number
  lon: number
  points: MarinePoint[]
}

// ===== Favorites =====

export interface AlertConfig {
  minWind: number
  maxWind: number
  directions: string[]
  enabled: boolean
  minWaveHeight?: number
  maxWaveHeight?: number
  minWavePeriod?: number
  tidePreference?: 'all' | 'low' | 'mid' | 'high' | 'rising' | 'falling'
  minScore?: number
}

export interface FavoriteSpot {
  id: string
  name: string
  lat: number
  lon: number
  type: 'station' | 'buoy' | 'spot'
  spotType?: 'kite' | 'surf' | 'paragliding'
  alert?: AlertConfig
}

// ===== Radar =====

export interface RadarFrame {
  path: string
  time: number
}

export interface RadarData {
  host: string
  past: RadarFrame[]
  nowcast: RadarFrame[]
}

// ===== Solunar =====

export interface MoonPhaseData {
  phase: number // 0-1
  name: string
  illumination: number // 0-100
  transitHour: number
  riseHour: number
  setHour: number
}

export interface SolunarPeriod {
  start: Date
  end: Date
  type: 'major' | 'minor'
}

export interface FishingScoreBreakdown {
  solunar: number   // /25
  tide: number      // /20
  wind: number      // /20
  sea: number       // /20
  pressure: number  // /15
  total: number     // /100
}

export interface SolunarData {
  moonPhase: MoonPhaseData
  periods: SolunarPeriod[]
  fishingScore: number
  breakdown: FishingScoreBreakdown
}

export interface FishSpecies {
  name: string
  months: number[]      // 1-12
  peakMonths: number[]
  technique: string
  minimumSize?: string
  region: string
}

// ===== Tides =====

export interface TideEvent {
  type: string // 'PM' | 'BM'
  time: string
  height: number
  coeff?: number
}

export interface TideChartPoint {
  time: number
  height: number
}

// ===== Tabs =====

export type TabId = 'map' | 'forecast' | 'favorites' | 'fishing' | 'webcams'

// ===== Weather Codes =====

export function getWeatherIcon(code: number): string {
  if (code === 0) return '☀️'
  if (code === 1) return '🌤️'
  if (code === 2) return '⛅'
  if (code === 3) return '☁️'
  if (code >= 45 && code <= 48) return '🌫️'
  if (code >= 51 && code <= 55) return '🌦️'
  if (code >= 56 && code <= 57) return '🌧️'
  if (code >= 61 && code <= 65) return '🌧️'
  if (code >= 66 && code <= 67) return '🌨️'
  if (code >= 71 && code <= 77) return '❄️'
  if (code >= 80 && code <= 82) return '🌦️'
  if (code >= 85 && code <= 86) return '🌨️'
  if (code >= 95) return '⛈️'
  return '🌤️'
}

export function getWeatherLabel(code: number): string {
  if (code === 0) return 'Ciel clair'
  if (code === 1) return 'Peu nuageux'
  if (code === 2) return 'Partiellement nuageux'
  if (code === 3) return 'Couvert'
  if (code >= 45 && code <= 48) return 'Brouillard'
  if (code >= 51 && code <= 55) return 'Bruine'
  if (code >= 56 && code <= 57) return 'Bruine verglacante'
  if (code >= 61 && code <= 63) return 'Pluie'
  if (code >= 64 && code <= 65) return 'Forte pluie'
  if (code >= 66 && code <= 67) return 'Pluie verglacante'
  if (code >= 71 && code <= 75) return 'Neige'
  if (code >= 76 && code <= 77) return 'Grains de neige'
  if (code >= 80 && code <= 82) return 'Averses'
  if (code >= 85 && code <= 86) return 'Averses de neige'
  if (code === 95) return 'Orage'
  if (code >= 96) return 'Orage avec grele'
  return ''
}
