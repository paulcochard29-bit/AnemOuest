// CANDHIS Wave Buoy API — Official REST API
// Returns wave buoy data for map display
// Bulk data cached in Vercel Blob by candhis-cron.js
// History fetched on-demand via getCampTR.php

import { list, put } from '../lib/storage.js';

export const config = { maxDuration: 60 };

const CANDHIS_API_KEY = process.env.CANDHIS_API_KEY;
const CANDHIS_API_BASE = 'https://candhis.cerema.fr/API/v1';
const CANDHIS_BLOB_PATH = 'candhis-data.json';
const SENTINEL = 999.9999;

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();

  // POST: receive pre-parsed updates from iOS app
  if (req.method === 'POST') return handleHistoryPush(req, res);

  res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');

  const { region, id, history } = req.query;

  // Serve from Blob cache
  try {
    const cachedData = await getCachedData();

    if (cachedData && cachedData.buoys) {
      const hasWaveData = cachedData.buoys.some(b => b.hm0 !== undefined);

      if (hasWaveData) {
        let buoys = cachedData.buoys;

        // Single buoy request
        if (id) {
          const buoy = buoys.find(b => b.id === id);
          if (!buoy) return res.status(404).json({ error: 'Buoy not found' });

          // Fetch history on demand via API (always fetch fresh)
          if (history === 'true' && CANDHIS_API_KEY) {
            console.log(`CANDHIS: Fetching history for ${id} via API`);
            try {
              const historyData = await fetchBuoyHistory(id);
              if (historyData.length > 0) {
                const mergedBuoy = { ...buoy, history: historyData };
                selfCacheBuoy(cachedData, id, { history: historyData }).catch(e =>
                  console.log(`CANDHIS: Self-cache failed for ${id}: ${e.message}`)
                );
                return res.json(mergedBuoy);
              }
            } catch (e) {
              console.log(`CANDHIS: History fetch failed for ${id}: ${e.message}`);
            }
            // Fallback to cached history if available
            return res.json(buoy);
          }

          return res.json(buoy);
        }

        // Filter by region
        if (region) {
          const regions = region.split(',');
          buoys = buoys.filter(b => regions.includes(b.region));
        }

        // Strip history for bulk requests
        const buoysWithoutHistory = buoys.map(b => {
          const { history, ...rest } = b;
          return rest;
        });

        console.log(`CANDHIS: Serving ${buoysWithoutHistory.length} buoys from cache (${cachedData.timestamp})`);

        return res.json({
          buoys: buoysWithoutHistory,
          count: buoysWithoutHistory.length,
          timestamp: cachedData.timestamp,
          cached: true,
        });
      }
    }
  } catch (error) {
    console.error('CANDHIS: Cache read error:', error.message);
  }

  // Fallback: direct API call if cache is empty
  if (CANDHIS_API_KEY) {
    console.log('CANDHIS: No cache, fetching from API...');
    try {
      const url = `${CANDHIS_API_BASE}/getCampListeTR.php?type=2`;
      const response = await fetch(url, {
        headers: { 'Authorization': CANDHIS_API_KEY },
      });
      const json = await response.json();

      if (json.success && json.results) {
        const buoys = json.results.map(row => parseApiRow(row)).filter(b => b.hm0 !== undefined);
        console.log(`CANDHIS: API returned ${buoys.length} buoys`);

        return res.json({
          buoys,
          count: buoys.length,
          timestamp: new Date().toISOString(),
          cached: false,
        });
      }
    } catch (e) {
      console.error('CANDHIS: API fallback failed:', e.message);
    }
  }

  return res.status(503).json({ error: 'No cached data available and API unavailable' });
}

// Static metadata for coordinates/regions
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

// Parse a single API result row into our buoy format
function parseApiRow(row) {
  const id = row[0];
  const dateStr = row[1];
  const hm0 = parseFloat(row[2]);
  const hmax = parseFloat(row[3]);
  const tp = parseFloat(row[4]);
  const direction = parseFloat(row[5]);
  const spread = parseFloat(row[6]);
  const seaTemp = parseFloat(row[7]);

  const meta = buoyMeta[id] || {};
  const data = { id, name: meta.name || id, lat: meta.lat, lon: meta.lon, depth: meta.depth, region: meta.region };

  if (dateStr) {
    try { data.lastUpdate = new Date(dateStr.replace(' ', 'T') + ':00Z').toISOString(); } catch (e) {}
  }

  if (!isNaN(hm0) && hm0 < SENTINEL) data.hm0 = hm0;
  if (!isNaN(hmax) && hmax < SENTINEL) data.hmax = hmax;
  if (!isNaN(tp) && tp < SENTINEL) data.tp = tp;
  if (!isNaN(direction) && direction < SENTINEL && direction >= 0 && direction <= 360) data.direction = direction;
  if (!isNaN(spread) && spread < SENTINEL && spread >= 0 && spread <= 180) data.spread = spread;
  if (!isNaN(seaTemp) && seaTemp < SENTINEL && seaTemp >= -5 && seaTemp <= 40) data.seaTemp = seaTemp;

  return data;
}

// Fetch history for a single buoy via getCampTR.php (7 days)
async function fetchBuoyHistory(buoyId) {
  const dateDeb = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  const url = `${CANDHIS_API_BASE}/getCampTR.php?camp=${buoyId}&dateDeb=${dateDeb}`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 20000);

  try {
    const response = await fetch(url, {
      headers: { 'Authorization': CANDHIS_API_KEY },
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const json = await response.json();

    if (!json.success || !json.results) return [];

    // getCampTR format: [Date, H1/3, Hmax, TH1/3, Dir, Etal, Temp] (no Campagne column)
    const history = [];
    for (const row of json.results) {
      const dateStr = row[0];
      const hm0 = parseFloat(row[1]);
      const hmax = parseFloat(row[2]);
      const tp = parseFloat(row[3]);
      const direction = parseFloat(row[4]);

      if (isNaN(hm0) || hm0 >= SENTINEL) continue;

      let timestamp;
      try { timestamp = new Date(dateStr.replace(' ', 'T') + ':00Z').toISOString(); } catch (e) { continue; }

      const point = { timestamp, hm0 };
      if (!isNaN(hmax) && hmax < SENTINEL) point.hmax = hmax;
      if (!isNaN(tp) && tp < SENTINEL) point.tp = tp;
      if (!isNaN(direction) && direction < SENTINEL) point.direction = direction;

      history.push(point);
    }

    history.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
    console.log(`CANDHIS: History for ${buoyId}: ${history.length} points over 7 days`);
    return history;
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  }
}

// Get cached data from Vercel Blob
async function getCachedData() {
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
  } catch (error) {
    console.log('CANDHIS: No cached data available:', error.message);
  }
  return null;
}

// Self-cache: update a single buoy in Blob (fire-and-forget)
async function selfCacheBuoy(cachedData, buoyId, updates) {
  const updatedBuoys = cachedData.buoys.map(b => {
    if (b.id !== buoyId) return b;
    return { ...b, ...updates };
  });
  const cacheData = { ...cachedData, buoys: updatedBuoys, timestamp: new Date().toISOString() };
  await put(CANDHIS_BLOB_PATH, JSON.stringify(cacheData), {
    access: 'public',
    contentType: 'application/json',
    addRandomSuffix: false,
  });
  console.log(`CANDHIS: Self-cached history for ${buoyId} (${updates.history?.length || 0} points)`);
}

// Handle POST: receive pre-parsed updates from iOS app
async function handleHistoryPush(req, res) {
  try {
    const body = req.body || {};

    const cachedData = await getCachedData();
    if (!cachedData || !cachedData.buoys) {
      return res.status(500).json({ error: 'No existing cache to merge into' });
    }

    const updateMap = {};
    const results = [];

    if (body.updates && Array.isArray(body.updates)) {
      for (const u of body.updates) {
        if (!u.id || !u.history || u.history.length === 0) continue;
        if (!buoyMeta[u.id]) continue;
        const { id, ...data } = u;
        updateMap[id] = data;
        results.push({ id, historyPoints: u.history.length, hm0: u.hm0 });
      }
    }

    if (Object.keys(updateMap).length === 0) {
      return res.status(422).json({ error: 'No valid data could be processed' });
    }

    const updatedBuoys = cachedData.buoys.map(b => {
      const update = updateMap[b.id];
      if (!update) return b;
      return { ...b, ...update };
    });

    const cacheData = {
      ...cachedData,
      buoys: updatedBuoys,
      timestamp: new Date().toISOString(),
    };

    await put(CANDHIS_BLOB_PATH, JSON.stringify(cacheData), {
      access: 'public',
      contentType: 'application/json',
      addRandomSuffix: false,
    });

    console.log(`CANDHIS: Push - ${results.length} buoys updated`);

    if (results.length === 1) {
      const updatedBuoy = updatedBuoys.find(b => b.id === results[0].id);
      return res.json(updatedBuoy);
    }

    return res.json({ ok: true, updated: results });
  } catch (error) {
    console.error('CANDHIS push error:', error);
    return res.status(500).json({ error: error.message });
  }
}
