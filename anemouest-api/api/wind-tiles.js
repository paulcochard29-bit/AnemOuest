// Wind Tiles - Serves pre-generated wind u/v data from Blob cache
// Falls back to on-the-fly generation if cache miss
//
// Usage: GET /api/wind-tiles?t={hours}  (-72 to +72)
// Returns: JSON with u/v components for particle rendering

import { list } from '../lib/storage.js';

const GRID_SIZE = 20; // fallback only — cron uses 40x40
const BOUNDS = { latMin: 38, latMax: 55, lonMin: -8, lonMax: 13 };

// On-the-fly fallback
async function generateTiles(forecastHour) {
  const points = [];
  for (let i = 0; i < GRID_SIZE; i++) {
    for (let j = 0; j < GRID_SIZE; j++) {
      points.push({
        lat: (BOUNDS.latMin + (BOUNDS.latMax - BOUNDS.latMin) * (i / (GRID_SIZE - 1))).toFixed(4),
        lon: (BOUNDS.lonMin + (BOUNDS.lonMax - BOUNDS.lonMin) * (j / (GRID_SIZE - 1))).toFixed(4),
      });
    }
  }

  const lats = points.map(p => p.lat).join(',');
  const lons = points.map(p => p.lon).join(',');
  const pastHours = forecastHour < 0 ? Math.abs(forecastHour) : 0;
  const fcastHours = forecastHour >= 0 ? Math.max(forecastHour + 1, 24) : 24;
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl&past_hours=${pastHours}&forecast_hours=${fcastHours}&models=best_match&timezone=auto`;

  const response = await fetch(url);
  if (!response.ok) return null;

  const data = await response.json();
  const dataArray = Array.isArray(data) ? data : [data];

  const u = new Array(GRID_SIZE * GRID_SIZE);
  const v = new Array(GRID_SIZE * GRID_SIZE);
  const speeds = new Array(GRID_SIZE * GRID_SIZE);
  const pressure = new Array(GRID_SIZE * GRID_SIZE);

  for (let idx = 0; idx < points.length && idx < dataArray.length; idx++) {
    const pd = dataArray[idx];
    const totalHours = pd.hourly?.wind_speed_10m?.length || 1;
    const hourIndex = Math.min(Math.max(0, pastHours + forecastHour), totalHours - 1);

    const ws = pd.hourly?.wind_speed_10m?.[hourIndex] ?? 0;
    const wd = pd.hourly?.wind_direction_10m?.[hourIndex] ?? 0;
    const pMsl = pd.hourly?.pressure_msl?.[hourIndex] ?? null;

    const speedMs = ws / 3.6;
    const dirRad = wd * Math.PI / 180;
    u[idx] = Math.round(-speedMs * Math.sin(dirRad) * 100) / 100;
    v[idx] = Math.round(-speedMs * Math.cos(dirRad) * 100) / 100;
    speeds[idx] = Math.round(ws * 10) / 10;
    pressure[idx] = pMsl !== null ? Math.round(pMsl * 10) / 10 : null;
  }

  return { u, v, speeds, pressure, width: GRID_SIZE, height: GRID_SIZE, bounds: BOUNDS };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const forecastHour = parseInt(req.query.t) || 0;
  if (forecastHour < -72 || forecastHour > 72) {
    return res.status(400).json({ error: 'Hour must be -72 to 72' });
  }

  // Try Blob cache first — proxy JSON (no redirect)
  try {
    const result = await list({ prefix: `wind/tiles/t${forecastHour}.json`, limit: 1 });
    if (result.blobs.length > 0) {
      const blob = result.blobs[0];
      const age = Date.now() - new Date(blob.uploadedAt).getTime();
      if (age < 6 * 3600_000) {
        const blobRes = await fetch(blob.url);
        const data = await blobRes.json();
        res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=900');
        res.setHeader('X-Cache', 'HIT');
        return res.json(data);
      }
    }
  } catch (e) {
    console.warn('[WindTiles] Blob cache error:', e.message);
  }

  // Fallback: generate on-the-fly
  try {
    const tiles = await generateTiles(forecastHour);
    if (!tiles) return res.status(500).json({ error: 'Failed to fetch wind data' });

    res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=900');
    res.setHeader('X-Cache', 'MISS');
    return res.json(tiles);
  } catch (e) {
    console.error('[WindTiles] Error:', e);
    return res.status(500).json({ error: 'Tiles generation failed' });
  }
}
