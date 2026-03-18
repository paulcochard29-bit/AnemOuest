// Wind Raster PNG - Serves pre-generated wind overlay from Blob cache
// Falls back to on-the-fly generation if cache miss
//
// Usage: GET /api/wind-raster?t={hours}  (-72 to +72)
// Returns: image/png (1024x1024, semi-transparent)

import { list } from '../lib/storage.js';
import sharp from 'sharp';

const GRID_SIZE = 20; // fallback only — cron uses 40x40
const OUTPUT_SIZE = 1024;
const BOUNDS = { latMin: 38, latMax: 55, lonMin: -8, lonMax: 13 };

// Windy-style color scale (knots)
const COLOR_STOPS = [
  [0,   98,  113, 183],
  [3,   57,  136, 210],
  [6,   30,  172, 230],
  [9,   30,  205, 180],
  [12,  55,  210, 100],
  [15,  115, 220,  50],
  [18,  200, 225,  30],
  [21,  245, 200,  30],
  [24,  250, 150,  25],
  [27,  245, 100,  20],
  [30,  235,  50,  35],
  [34,  220,  30,  75],
  [38,  200,  30, 145],
  [42,  175,  50, 200],
  [48,  150,  80, 225],
  [55,  180, 120, 255],
  [65,  210, 170, 255],
];

const COLOR_LUT = new Array(256);
for (let i = 0; i < 256; i++) {
  const knots = ((i / 255) * 120) * 0.539957;
  let lo = 0, hi = COLOR_STOPS.length - 1;
  for (let j = 1; j < COLOR_STOPS.length; j++) {
    if (COLOR_STOPS[j][0] > knots) { hi = j; lo = j - 1; break; }
  }
  if (knots >= COLOR_STOPS[COLOR_STOPS.length - 1][0]) lo = hi = COLOR_STOPS.length - 1;
  const [k0, r0, g0, b0] = COLOR_STOPS[lo];
  const [k1, r1, g1, b1] = COLOR_STOPS[hi];
  const t = lo === hi ? 0 : Math.min(1, (knots - k0) / (k1 - k0));
  COLOR_LUT[i] = [
    Math.round(r0 + t * (r1 - r0)),
    Math.round(g0 + t * (g1 - g0)),
    Math.round(b0 + t * (b1 - b0)),
  ];
}

function speedToRGB(kmh) {
  const idx = Math.min(255, Math.max(0, Math.round((kmh / 120) * 255)));
  return COLOR_LUT[idx];
}

// On-the-fly fallback
async function generateRaster(forecastHour) {
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
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}&hourly=wind_speed_10m,wind_direction_10m&past_hours=${pastHours}&forecast_hours=${fcastHours}&models=best_match&timezone=auto`;

  const response = await fetch(url);
  if (!response.ok) return null;

  const data = await response.json();
  const dataArray = Array.isArray(data) ? data : [data];
  const speeds = new Float32Array(GRID_SIZE * GRID_SIZE);

  for (let idx = 0; idx < points.length && idx < dataArray.length; idx++) {
    const pd = dataArray[idx];
    const totalHours = pd.hourly?.wind_speed_10m?.length || 1;
    const hourIndex = Math.min(Math.max(0, pastHours + forecastHour), totalHours - 1);
    speeds[idx] = pd.hourly?.wind_speed_10m?.[hourIndex] ?? 0;
  }

  const rawBuf = Buffer.alloc(GRID_SIZE * GRID_SIZE * 4);
  for (let row = 0; row < GRID_SIZE; row++) {
    const srcRow = GRID_SIZE - 1 - row;
    for (let col = 0; col < GRID_SIZE; col++) {
      const srcIdx = srcRow * GRID_SIZE + col;
      const dstIdx = row * GRID_SIZE + col;
      const [r, g, b] = speedToRGB(speeds[srcIdx]);
      rawBuf[dstIdx * 4] = r;
      rawBuf[dstIdx * 4 + 1] = g;
      rawBuf[dstIdx * 4 + 2] = b;
      rawBuf[dstIdx * 4 + 3] = 230;
    }
  }

  return sharp(rawBuf, { raw: { width: GRID_SIZE, height: GRID_SIZE, channels: 4 } })
    .resize(OUTPUT_SIZE, OUTPUT_SIZE, { kernel: 'cubic' })
    .blur(3.5)
    .png()
    .toBuffer();
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const forecastHour = parseInt(req.query.t) || 0;
  if (forecastHour < -72 || forecastHour > 72) {
    return res.status(400).json({ error: 'Hour must be -72 to 72' });
  }

  // Try Blob cache first — proxy PNG (no redirect, avoids CORS issues with Mapbox)
  try {
    const result = await list({ prefix: `wind/raster/t${forecastHour}.png`, limit: 1 });
    if (result.blobs.length > 0) {
      const blob = result.blobs[0];
      const age = Date.now() - new Date(blob.uploadedAt).getTime();
      if (age < 2 * 3600_000) {
        const blobRes = await fetch(blob.url);
        const buffer = Buffer.from(await blobRes.arrayBuffer());
        res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=900');
        res.setHeader('X-Bounds', JSON.stringify(BOUNDS));
        res.setHeader('X-Cache', 'HIT');
        res.setHeader('Access-Control-Expose-Headers', 'X-Bounds, X-Cache');
        res.setHeader('Content-Type', 'image/png');
        return res.send(buffer);
      }
    }
  } catch (e) {
    console.warn('[WindRaster] Blob cache error:', e.message);
  }

  // Fallback: generate on-the-fly
  try {
    const png = await generateRaster(forecastHour);
    if (!png) return res.status(500).json({ error: 'Failed to fetch wind data' });

    res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=900');
    res.setHeader('X-Bounds', JSON.stringify(BOUNDS));
    res.setHeader('X-Cache', 'MISS');
    res.setHeader('Access-Control-Expose-Headers', 'X-Bounds, X-Cache');
    res.setHeader('Content-Type', 'image/png');
    return res.send(png);
  } catch (e) {
    console.error('[WindRaster] Error:', e);
    return res.status(500).json({ error: 'Raster generation failed' });
  }
}
