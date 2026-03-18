// CANDHIS Wave Buoy Cron - Uses official CANDHIS REST API
// Run via cron every 30 min: /api/candhis-cron
// Single API call fetches ALL buoys at once (vs 25+ HTML scrapes before)

import { put, list } from '../lib/storage.js';

export const config = { maxDuration: 60 };

const CRON_SECRET = process.env.CRON_SECRET;
const CANDHIS_API_KEY = process.env.CANDHIS_API_KEY;
const CANDHIS_API_BASE = 'https://candhis.cerema.fr/API/v1';
const CANDHIS_BLOB_PATH = 'candhis-data.json';
const SENTINEL = 999.9999;

// Static metadata (lat/lon/region) — API doesn't return coordinates in TR data
const buoyMeta = {
  "02922": { name: "Île de Batz", lat: 48.7283, lon: -4.0717, depth: 30, region: "bretagne" },
  "02911": { name: "Les Pierres Noires", lat: 48.2903, lon: -4.9683, depth: 60, region: "bretagne" },
  "05602": { name: "Belle-Île", lat: 47.2850, lon: -3.2850, depth: 45, region: "bretagne" },
  "04403": { name: "Plateau du Four", lat: 47.2398, lon: -2.7805, depth: 30, region: "bretagne" },
  "08504": { name: "Île d'Yeu Nord", lat: 46.8332, lon: -2.2950, depth: 14, region: "vendee" },
  "08505": { name: "Noirmoutier", lat: 46.9238, lon: -2.4679, depth: 18, region: "vendee" },
  "01704": { name: "Oléron Large", lat: 45.9163, lon: -1.8336, depth: 50, region: "charentes" },
  "01705": { name: "Royan", lat: 45.6100, lon: -1.0317, depth: 14, region: "charentes" },
  "03302": { name: "Cap Ferret", lat: 44.6525, lon: -1.4467, depth: 54, region: "aquitaine" },
  "06402": { name: "Anglet", lat: 43.5322, lon: -1.6150, depth: 50, region: "aquitaine" },
  "06403": { name: "Saint-Jean-de-Luz", lat: 43.4083, lon: -1.6817, depth: 20, region: "aquitaine" },
  "05008": { name: "Cherbourg", lat: 49.6941, lon: -1.6214, depth: 25, region: "manche" },
  "07611": { name: "Le Havre Nord", lat: 49.4900, lon: 0.0900, depth: 20, region: "manche" },
  "07609": { name: "Le Havre Sud-Ouest", lat: 49.4700, lon: 0.0500, depth: 20, region: "manche" },
  "07610": { name: "Port d'Antifer", lat: 49.6500, lon: 0.1500, depth: 25, region: "manche" },
  "05903": { name: "Gravelines", lat: 51.0427, lon: 2.0660, depth: 15, region: "nord" },
  "01101": { name: "Leucate", lat: 42.9167, lon: 3.1250, depth: 40, region: "mediterranee" },
  "01305": { name: "Le Planier", lat: 43.2083, lon: 5.2300, depth: 70, region: "mediterranee" },
  "03001": { name: "Espiguette", lat: 43.4110, lon: 4.1625, depth: 32, region: "mediterranee" },
  "03404": { name: "Sète", lat: 43.3713, lon: 3.7771, depth: 30, region: "mediterranee" },
  "06601": { name: "Banyuls", lat: 42.4895, lon: 3.1677, depth: 50, region: "mediterranee" },
  "08302": { name: "Porquerolles", lat: 42.9667, lon: 6.2048, depth: 98, region: "mediterranee" },
  "98000": { name: "Monaco", lat: 43.7000, lon: 7.4000, depth: 50, region: "mediterranee" },
  "02A01": { name: "Bonifacio", lat: 41.3226, lon: 8.8775, depth: 150, region: "corse" },
  "02B04": { name: "La Revellata", lat: 42.5692, lon: 8.6500, depth: 130, region: "corse" },
  "02B05": { name: "Alistro", lat: 42.2617, lon: 9.6433, depth: 120, region: "corse" },
};

// Parse a single API result row into our buoy data format
// Headers: ["Campagne", "Date", "H1/3 (m)", "Hmax (m)", "TH1/3 (s)", "Dir. au pic (°)", "Etal. au pic (°)", "Temp. mer (°C)"]
function parseRow(row) {
  const id = row[0];
  const dateStr = row[1]; // "YYYY-MM-DD HH:MM"
  const hm0 = parseFloat(row[2]);
  const hmax = parseFloat(row[3]);
  const tp = parseFloat(row[4]);
  const direction = parseFloat(row[5]);
  const spread = parseFloat(row[6]);
  const seaTemp = parseFloat(row[7]);

  const data = { id };

  if (dateStr) {
    try {
      data.lastUpdate = new Date(dateStr.replace(' ', 'T') + ':00Z').toISOString();
    } catch (e) {}
  }

  if (!isNaN(hm0) && hm0 < SENTINEL) data.hm0 = hm0;
  if (!isNaN(hmax) && hmax < SENTINEL) data.hmax = hmax;
  if (!isNaN(tp) && tp < SENTINEL) data.tp = tp;
  if (!isNaN(direction) && direction < SENTINEL && direction >= 0 && direction <= 360) data.direction = direction;
  if (!isNaN(spread) && spread < SENTINEL && spread >= 0 && spread <= 180) data.spread = spread;
  if (!isNaN(seaTemp) && seaTemp < SENTINEL && seaTemp >= -5 && seaTemp <= 40) data.seaTemp = seaTemp;

  return data;
}

// Fetch real-time data for ALL buoys in a single API call
async function fetchAllBuoysRT() {
  const url = `${CANDHIS_API_BASE}/getCampListeTR.php?type=2`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000);

  try {
    const response = await fetch(url, {
      headers: { 'Authorization': CANDHIS_API_KEY },
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const json = await response.json();

    if (!json.success) throw new Error(json.message || 'API returned success=false');
    return json.results || [];
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (!CANDHIS_API_KEY) {
    return res.status(500).json({ error: 'CANDHIS_API_KEY not configured' });
  }

  // Verify cron authorization
  const { test } = req.query || {};
  const isTest = test === 'true';

  if (!isTest) {
    const authHeader = req.headers.authorization;
    if (CRON_SECRET && authHeader !== `Bearer ${CRON_SECRET}`) {
      if (req.headers['x-vercel-cron'] !== '1') {
        return res.status(401).json({ error: 'Unauthorized' });
      }
    }
  }

  const startTime = Date.now();
  console.log(`CANDHIS cron: Starting at ${new Date(startTime).toISOString()}`);

  // Test mode: just fetch and return raw API response
  if (isTest) {
    try {
      const rows = await fetchAllBuoysRT();
      const parsed = rows.map(parseRow);
      return res.json({
        test: true,
        apiRows: rows.length,
        parsed: parsed.slice(0, 5),
        allIds: parsed.map(p => p.id),
      });
    } catch (error) {
      return res.json({ test: true, error: error.message });
    }
  }

  // 1. Fetch all buoys from API (1 single request)
  let apiRows;
  try {
    apiRows = await fetchAllBuoysRT();
    console.log(`CANDHIS cron: API returned ${apiRows.length} buoys`);
  } catch (error) {
    console.error(`CANDHIS cron: API fetch failed - ${error.message}`);
    const duration = Math.round((Date.now() - startTime) / 1000);
    return res.status(200).json({
      message: 'CANDHIS cron: API fetch failed, cache preserved',
      duration: `${duration}s`,
      error: error.message,
    });
  }

  // 2. Parse API rows and merge with static metadata
  const buoysWithData = [];
  let successCount = 0;

  for (const row of apiRows) {
    const parsed = parseRow(row);
    const meta = buoyMeta[parsed.id];

    // Build buoy object: use static metadata if available, otherwise skip unknown buoys
    if (!meta) {
      console.log(`CANDHIS cron: Unknown buoy ${parsed.id}, skipping`);
      continue;
    }

    const buoy = {
      id: parsed.id,
      name: meta.name,
      lat: meta.lat,
      lon: meta.lon,
      depth: meta.depth,
      region: meta.region,
      status: parsed.hm0 !== undefined ? 'TOTALE' : 'LIMITE',
      ...parsed,
    };
    delete buoy.id; // Already set above
    buoy.id = parsed.id;

    if (parsed.hm0 !== undefined) {
      successCount++;
      console.log(`CANDHIS cron: ${parsed.id} ${meta.name} - Hm0=${parsed.hm0}m`);
    }

    buoysWithData.push(buoy);
  }

  // Also include buoys from our metadata that weren't in the API response (offline)
  for (const [id, meta] of Object.entries(buoyMeta)) {
    if (!buoysWithData.find(b => b.id === id)) {
      buoysWithData.push({ id, ...meta, status: 'LIMITE' });
    }
  }

  console.log(`CANDHIS cron: ${successCount}/${buoysWithData.length} buoys with data`);

  // 3. Merge with existing cache (preserve history from on-demand fetches)
  let mergedBuoys = buoysWithData;
  let existingCacheHm0Count = 0;

  try {
    const existingCache = await getExistingCache();
    if (existingCache && existingCache.buoys) {
      existingCacheHm0Count = existingCache.buoys.filter(b => b.hm0 !== undefined).length;
      const existingMap = {};
      for (const b of existingCache.buoys) {
        existingMap[b.id] = b;
      }

      mergedBuoys = buoysWithData.map(newBuoy => {
        const old = existingMap[newBuoy.id];
        if (!old) return newBuoy;

        // If new data has hm0, use it but preserve old history
        if (newBuoy.hm0 !== undefined) {
          if (old.history && old.history.length > 0) {
            return { ...newBuoy, history: old.history };
          }
          return newBuoy;
        }

        // New data has no hm0 (buoy offline) — keep old data
        return old;
      });

      const mergedSuccess = mergedBuoys.filter(b => b.hm0 !== undefined).length;
      console.log(`CANDHIS cron: Merged - ${mergedSuccess} buoys with hm0 (${successCount} fresh, ${mergedSuccess - successCount} from cache)`);
    }
  } catch (e) {
    console.log(`CANDHIS cron: Could not load existing cache: ${e.message}`);
    if (successCount < 5) {
      const duration = Math.round((Date.now() - startTime) / 1000);
      return res.status(200).json({
        message: 'CANDHIS cron: Skipped save to protect cache',
        duration: `${duration}s`,
        successCount,
        mergeFailed: true,
      });
    }
  }

  // Safety check
  const mergedHm0Count = mergedBuoys.filter(b => b.hm0 !== undefined).length;
  if (existingCacheHm0Count > 0 && mergedHm0Count < existingCacheHm0Count * 0.5) {
    console.log(`CANDHIS cron: Skipping save - ${mergedHm0Count} hm0 vs cache ${existingCacheHm0Count}`);
    const duration = Math.round((Date.now() - startTime) / 1000);
    return res.status(200).json({
      message: 'CANDHIS cron: Skipped save to protect cache quality',
      duration: `${duration}s`,
      mergedHm0Count,
      existingCacheHm0Count,
    });
  }

  // 4. Save to Vercel Blob
  const cacheData = {
    buoys: mergedBuoys,
    count: mergedBuoys.length,
    timestamp: new Date().toISOString(),
    results: { success: successCount, total: buoysWithData.length, failed: buoysWithData.length - successCount },
  };

  try {
    await put(CANDHIS_BLOB_PATH, JSON.stringify(cacheData), {
      access: 'public',
      contentType: 'application/json',
      addRandomSuffix: false,
    });

    const duration = Math.round((Date.now() - startTime) / 1000);
    console.log(`CANDHIS cron: Complete - ${successCount} buoys with data in ${duration}s (1 API call)`);

    res.status(200).json({
      message: 'CANDHIS data cached successfully',
      duration: `${duration}s`,
      results: cacheData.results,
    });
  } catch (error) {
    console.error('CANDHIS cron: Failed to save to blob:', error);
    res.status(500).json({ error: 'Failed to cache data', message: error.message });
  }
}

// Load existing Blob cache for merge
async function getExistingCache() {
  try {
    const { blobs } = await list({ prefix: CANDHIS_BLOB_PATH });
    if (blobs.length > 0) {
      const latestBlob = blobs.sort((a, b) =>
        new Date(b.uploadedAt) - new Date(a.uploadedAt)
      )[0];
      const url = new URL(latestBlob.url);
      url.searchParams.set('_t', Date.now());
      const response = await fetch(url.toString(), { cache: 'no-store' });
      return await response.json();
    }
  } catch (e) {
    console.log('CANDHIS cron: Failed to read existing cache:', e.message);
  }
  return null;
}
