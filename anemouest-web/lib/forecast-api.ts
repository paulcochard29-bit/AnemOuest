import type { ForecastModel, ForecastResponse, ForecastPoint, DailyForecast, MarineResponse, MarinePoint } from './types'

const MODEL_ENDPOINTS: Record<ForecastModel, { url: string; days: number }> = {
  arome: { url: 'https://api.open-meteo.com/v1/meteofrance', days: 4 },
  ecmwf: { url: 'https://api.open-meteo.com/v1/ecmwf', days: 10 },
  gfs: { url: 'https://api.open-meteo.com/v1/gfs', days: 16 },
  icon: { url: 'https://api.open-meteo.com/v1/dwd-icon', days: 7 },
}

const MARINE_URL = 'https://marine-api.open-meteo.com/v1/marine'

const cache = new Map<string, { data: unknown; ts: number }>()
const CACHE_TTL = 15 * 60 * 1000

function getCached<T>(key: string): T | null {
  const entry = cache.get(key)
  if (entry && Date.now() - entry.ts < CACHE_TTL) return entry.data as T
  cache.delete(key)
  return null
}

function setCache(key: string, data: unknown) {
  cache.set(key, { data, ts: Date.now() })
}

const HOURLY_PARAMS = [
  'wind_speed_10m', 'wind_gusts_10m', 'wind_direction_10m',
  'temperature_2m', 'relative_humidity_2m',
  'cloud_cover_high', 'cloud_cover_mid', 'cloud_cover_low',
  'precipitation', 'weather_code', 'visibility', 'surface_pressure', 'uv_index',
].join(',')

const DAILY_PARAMS = [
  'temperature_2m_max', 'temperature_2m_min',
  'precipitation_sum', 'weather_code',
  'wind_speed_10m_max', 'wind_gusts_10m_max',
  'wind_direction_10m_dominant',
].join(',')

export async function fetchWindForecast(lat: number, lon: number, model: ForecastModel): Promise<ForecastResponse> {
  const cacheKey = `wind:${lat.toFixed(2)},${lon.toFixed(2)},${model}`
  const cached = getCached<ForecastResponse>(cacheKey)
  if (cached) return cached

  const cfg = MODEL_ENDPOINTS[model]
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lon),
    hourly: HOURLY_PARAMS,
    daily: DAILY_PARAMS,
    wind_speed_unit: 'kn',
    timezone: 'Europe/Paris',
    forecast_days: String(cfg.days),
  })

  const res = await fetch(`${cfg.url}?${params}`)
  if (!res.ok) throw new Error(`Open-Meteo error: ${res.status}`)
  const json = await res.json()

  const h = json.hourly || {}
  const times: string[] = h.time || []

  const points: ForecastPoint[] = times.map((t: string, i: number) => ({
    time: t,
    windSpeed: h.wind_speed_10m?.[i] ?? 0,
    windGust: h.wind_gusts_10m?.[i] ?? 0,
    windDirection: h.wind_direction_10m?.[i] ?? 0,
    temperature: h.temperature_2m?.[i] ?? 0,
    humidity: h.relative_humidity_2m?.[i] ?? 0,
    cloudCoverHigh: h.cloud_cover_high?.[i] ?? 0,
    cloudCoverMid: h.cloud_cover_mid?.[i] ?? 0,
    cloudCoverLow: h.cloud_cover_low?.[i] ?? 0,
    precipitation: h.precipitation?.[i] ?? 0,
    weatherCode: h.weather_code?.[i] ?? 0,
    visibility: h.visibility?.[i] ?? 0,
    pressure: h.surface_pressure?.[i] ?? 0,
    uvIndex: h.uv_index?.[i] ?? 0,
  }))

  // Parse daily
  const d = json.daily || {}
  const dailyTimes: string[] = d.time || []
  const daily: DailyForecast[] = dailyTimes.map((date: string, i: number) => ({
    date,
    maxWind: d.wind_speed_10m_max?.[i] ?? 0,
    maxGust: d.wind_gusts_10m_max?.[i] ?? 0,
    avgDir: d.wind_direction_10m_dominant?.[i] ?? 0,
    maxTemp: d.temperature_2m_max?.[i] ?? 0,
    minTemp: d.temperature_2m_min?.[i] ?? 0,
    precipitationSum: d.precipitation_sum?.[i] ?? 0,
    weatherCode: d.weather_code?.[i] ?? 0,
  }))

  const result: ForecastResponse = { model, lat, lon, points, daily }
  setCache(cacheKey, result)
  return result
}

export async function fetchMarineForecast(lat: number, lon: number): Promise<MarineResponse> {
  const cacheKey = `marine:${lat.toFixed(2)},${lon.toFixed(2)}`
  const cached = getCached<MarineResponse>(cacheKey)
  if (cached) return cached

  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lon),
    hourly: 'wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,wind_wave_height,wind_wave_period,wind_wave_direction',
    timezone: 'Europe/Paris',
    forecast_days: '7',
  })

  const res = await fetch(`${MARINE_URL}?${params}`)
  if (!res.ok) throw new Error(`Open-Meteo marine error: ${res.status}`)
  const json = await res.json()

  const h = json.hourly || {}
  const times: string[] = h.time || []

  const points: MarinePoint[] = times.map((t: string, i: number) => ({
    time: t,
    waveHeight: h.wave_height?.[i] ?? 0,
    wavePeriod: h.wave_period?.[i] ?? 0,
    waveDirection: h.wave_direction?.[i] ?? 0,
    swellHeight: h.swell_wave_height?.[i] ?? 0,
    swellPeriod: h.swell_wave_period?.[i] ?? 0,
    swellDirection: h.swell_wave_direction?.[i] ?? 0,
    windWaveHeight: h.wind_wave_height?.[i] ?? 0,
    windWavePeriod: h.wind_wave_period?.[i] ?? 0,
    windWaveDirection: h.wind_wave_direction?.[i] ?? 0,
  }))

  const result: MarineResponse = { lat, lon, points }
  setCache(cacheKey, result)
  return result
}

export const MODEL_LABELS: Record<ForecastModel, { name: string; color: string; days: number }> = {
  arome: { name: 'AROME', color: '#3b82f6', days: 4 },
  ecmwf: { name: 'ECMWF', color: '#22c55e', days: 10 },
  gfs: { name: 'GFS', color: '#f97316', days: 16 },
  icon: { name: 'ICON', color: '#a855f7', days: 7 },
}
