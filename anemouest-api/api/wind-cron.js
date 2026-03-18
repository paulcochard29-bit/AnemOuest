// Wind Forecast Cron - Pre-generates raster PNGs + tile JSONs for -72h to +72h
// Stores in Vercel Blob for instant serving
// Runs every hour via Vercel cron
// Uses 40x40 grid (1600 points) fetched in 4 batches of 400

import { put } from '../lib/storage.js';
import sharp from 'sharp';

const GRID_SIZE = 40;
const BATCH_ROWS = 5; // 8 batches of 5 rows × 40 cols = 200 points each
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

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  const startTime = Date.now();

  // 1. Build 40x40 grid and fetch in 4 batches of 10×40 = 400 points
  const allPoints = [];
  for (let i = 0; i < GRID_SIZE; i++) {
    for (let j = 0; j < GRID_SIZE; j++) {
      allPoints.push({
        lat: (BOUNDS.latMin + (BOUNDS.latMax - BOUNDS.latMin) * (i / (GRID_SIZE - 1))).toFixed(4),
        lon: (BOUNDS.lonMin + (BOUNDS.lonMax - BOUNDS.lonMin) * (j / (GRID_SIZE - 1))).toFixed(4),
      });
    }
  }

  // Fetch in 4 sequential batches (10 lat rows × 40 lon cols = 400 points each)
  // Sequential to avoid Open-Meteo rate limits
  const numBatches = GRID_SIZE / BATCH_ROWS;
  console.log(`[WindCron] Fetching ${numBatches} batches of ${BATCH_ROWS}×${GRID_SIZE} points...`);

  const batchResults = [];
  for (let b = 0; b < numBatches; b++) {
    const startIdx = b * BATCH_ROWS * GRID_SIZE;
    const endIdx = startIdx + BATCH_ROWS * GRID_SIZE;
    const batchPoints = allPoints.slice(startIdx, endIdx);

    const lats = batchPoints.map(p => p.lat).join(',');
    const lons = batchPoints.map(p => p.lon).join(',');
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lons}&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl&past_hours=72&forecast_hours=73&models=best_match&timezone=auto`;

    console.log(`[WindCron] Batch ${b + 1}/${numBatches} (${batchPoints.length} points, URL ${url.length} chars)...`);
    // Retry with backoff on rate limit
    let response;
    for (let attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await new Promise(r => setTimeout(r, 5000 * (attempt + 1)));
      try {
        response = await fetch(url);
        if (response.ok) break;
        if (response.status === 429) {
          console.warn(`[WindCron] Batch ${b + 1} rate limited, retrying in ${5 * (attempt + 1)}s...`);
          continue;
        }
        console.error(`[WindCron] Batch ${b + 1} error: ${response.status}`);
        return res.status(500).json({ error: `Open-Meteo batch ${b + 1} failed: ${response.status}` });
      } catch (e) {
        console.error(`[WindCron] Batch ${b + 1} fetch error:`, e.message);
        if (attempt === 3) return res.status(500).json({ error: 'Open-Meteo fetch failed' });
      }
    }
    // Validate response after retry loop
    if (!response || !response.ok) {
      console.error(`[WindCron] Batch ${b + 1} failed after all retries`);
      return res.status(500).json({ error: `Open-Meteo batch ${b + 1} failed after retries` });
    }
    const data = await response.json();
    const arr = Array.isArray(data) ? data : [data];
    if (arr.length < batchPoints.length) {
      console.warn(`[WindCron] Batch ${b + 1}: expected ${batchPoints.length} items, got ${arr.length}`);
    }
    batchResults.push(data);
    // Wait between batches to avoid rate limits
    if (b < numBatches - 1) await new Promise(r => setTimeout(r, 5000));
  }

  // Combine all batch results into a single flat array (order matches allPoints)
  const dataArray = [];
  for (let bi = 0; bi < batchResults.length; bi++) {
    const batchData = batchResults[bi];
    const isArr = Array.isArray(batchData);
    const arr = isArr ? batchData : [batchData];
    console.log(`[WindCron] Batch ${bi + 1} result: isArray=${isArr}, items=${arr.length}, hasHourly=${!!arr[0]?.hourly}`);
    dataArray.push(...arr);
  }

  console.log(`[WindCron] Got data for ${dataArray.length} points (expected ${allPoints.length}), ${dataArray[0]?.hourly?.wind_speed_10m?.length || 0} hours`);
  const totalHoursAvailable = dataArray[0]?.hourly?.wind_speed_10m?.length || 0;
  if (totalHoursAvailable < 10) {
    return res.status(500).json({ error: 'Insufficient data from Open-Meteo' });
  }

  // 2. Generate rasters + tiles for each hour
  const urls = {};
  let generated = 0;

  for (let batchStart = -72; batchStart <= 72; batchStart += 15) {
    const batchEnd = Math.min(batchStart + 14, 72);
    const promises = [];

    for (let h = batchStart; h <= batchEnd; h++) {
      const hourIndex = Math.min(72 + h, totalHoursAvailable - 1);
      if (hourIndex < 0) continue;

      promises.push((async () => {
        const speeds = new Float32Array(GRID_SIZE * GRID_SIZE);
        const u = new Array(GRID_SIZE * GRID_SIZE);
        const v = new Array(GRID_SIZE * GRID_SIZE);
        const speedsArr = new Array(GRID_SIZE * GRID_SIZE);
        const pressureArr = new Array(GRID_SIZE * GRID_SIZE);

        for (let idx = 0; idx < allPoints.length && idx < dataArray.length; idx++) {
          const pd = dataArray[idx];
          const ws = pd?.hourly?.wind_speed_10m?.[hourIndex] ?? 0;
          const wd = pd?.hourly?.wind_direction_10m?.[hourIndex] ?? 0;
          const pMsl = pd?.hourly?.pressure_msl?.[hourIndex] ?? null;

          speeds[idx] = ws;
          const speedMs = ws / 3.6;
          const dirRad = wd * Math.PI / 180;
          u[idx] = Math.round(-speedMs * Math.sin(dirRad) * 100) / 100;
          v[idx] = Math.round(-speedMs * Math.cos(dirRad) * 100) / 100;
          speedsArr[idx] = Math.round(ws * 10) / 10;
          pressureArr[idx] = pMsl !== null ? Math.round(pMsl * 10) / 10 : null;
        }

        // Generate raster PNG
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

        const png = await sharp(rawBuf, {
          raw: { width: GRID_SIZE, height: GRID_SIZE, channels: 4 }
        })
          .resize(OUTPUT_SIZE, OUTPUT_SIZE, { kernel: 'cubic' })
          .blur(2.5)
          .png()
          .toBuffer();

        // Upload raster + tiles
        const [rasterResult, tilesResult] = await Promise.all([
          put(`wind/raster/t${h}.png`, png, {
            access: 'public', addRandomSuffix: false,
            contentType: 'image/png', cacheControlMaxAge: 3600,
          }),
          put(`wind/tiles/t${h}.json`, JSON.stringify({
            u, v, speeds: speedsArr, pressure: pressureArr,
            width: GRID_SIZE, height: GRID_SIZE, bounds: BOUNDS,
          }), {
            access: 'public', addRandomSuffix: false,
            contentType: 'application/json', cacheControlMaxAge: 3600,
          }),
        ]);

        urls[h] = { raster: rasterResult.url, tiles: tilesResult.url };
        generated++;
      })());
    }

    await Promise.all(promises);
  }

  // 3. Store index
  await put('wind/index.json', JSON.stringify({
    generated: new Date().toISOString(),
    bounds: BOUNDS,
    gridSize: GRID_SIZE,
    hours: urls,
  }), {
    access: 'public', addRandomSuffix: false,
    contentType: 'application/json', cacheControlMaxAge: 300,
  });

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`[WindCron] Done: ${generated} hours (${GRID_SIZE}x${GRID_SIZE}) in ${elapsed}s`);

  return res.json({ ok: true, generated, gridSize: GRID_SIZE, elapsed: `${elapsed}s` });
}
