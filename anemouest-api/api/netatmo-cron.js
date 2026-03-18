// Netatmo Cron - Two modes:
// 1. Default: snapshot wind data to Blob for history graphs (every 1 min)
// 2. ?scan=true: full unfiltered scan to discover ALL stations (every 2h)
//
// Stations stored as netatmo-stations/all.json
// History stored as netatmo-history/data.json (rolling 48h)

import { put, list } from '../lib/storage.js';
import { getAccessToken, invalidateToken, fetchTile, parseStation, generateTiles } from './netatmo.js';

const CRON_SECRET = process.env.CRON_SECRET;
const RETENTION_MS = 48 * 60 * 60 * 1000; // 48h
const LOCK_TTL_MS = 55 * 1000; // 55s lock to prevent overlapping 1-min cron runs

const FRANCE_BBOX = {
  lat_sw: 41.3, lon_sw: -5.2,
  lat_ne: 51.1, lon_ne: 9.6,
};

// Full scan: combines filtered + unfiltered to discover ALL NAModule2 stations
async function fullScan() {
  let token = await getAccessToken();
  const CONCURRENCY = 3;
  const allRaw = [];

  // Pass 1: filtered scan with big tiles (fast, gets ~6000 wind stations)
  const bigTiles = generateTiles(FRANCE_BBOX, 3.3, 3.8);
  console.log(`Netatmo scan pass 1: ${bigTiles.length} filtered tiles`);
  let tokenRetried = false;
  for (let i = 0; i < bigTiles.length; i += CONCURRENCY) {
    const batch = bigTiles.slice(i, i + CONCURRENCY);
    try {
      const results = await Promise.all(batch.map(async t => {
        const res = await fetch('https://api.netatmo.com/api/getpublicdata', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            lat_ne: String(t.lat_ne), lon_ne: String(t.lon_ne),
            lat_sw: String(t.lat_sw), lon_sw: String(t.lon_sw),
            required_data: 'wind', filter: 'true',
          }).toString(),
        });
        if (res.status === 403) throw new Error('NETATMO_TOKEN_INVALID');
        if (res.status === 429) throw new Error('NETATMO_RATE_LIMITED');
        if (!res.ok) return [];
        const data = await res.json();
        return data.body || [];
      }));
      for (const r of results) allRaw.push(...r);
    } catch (e) {
      if (e.message === 'NETATMO_RATE_LIMITED') {
        console.warn('Netatmo scan: rate limited in pass 1, skipping to pass 2');
        break;
      }
      if (e.message === 'NETATMO_TOKEN_INVALID' && !tokenRetried) {
        console.warn('Netatmo scan pass 1: token invalid, forcing refresh');
        tokenRetried = true;
        invalidateToken();
        token = await getAccessToken(true);
        i -= CONCURRENCY;
        continue;
      }
      throw e;
    }
  }

  const pass1Count = allRaw.length;
  console.log(`Netatmo scan pass 1: ${pass1Count} raw stations`);

  // Pass 2: unfiltered scan with medium tiles (catches stations missed by Netatmo's wind filter)
  // 1.0° × 1.2° = ~140 tiles (fits in 300s timeout)
  // Rate limit: Netatmo allows ~50 requests per 10 seconds
  const smallTiles = generateTiles(FRANCE_BBOX, 1.0, 1.2);
  console.log(`Netatmo scan pass 2: ${smallTiles.length} unfiltered tiles`);
  let failedTiles = 0;
  for (let i = 0; i < smallTiles.length; i += 5) {
    const batch = smallTiles.slice(i, i + 5);
    try {
      const results = await Promise.all(batch.map(t => fetchTile(token, t)));
      for (const r of results) {
        if (r.length === 0) failedTiles++;
        allRaw.push(...r);
      }
    } catch (e) {
      if (e.message === 'NETATMO_RATE_LIMITED') {
        console.warn(`Netatmo scan: rate limited in pass 2, continuing with ${allRaw.length} raw from pass 1`);
        break;
      }
      if (e.message === 'NETATMO_TOKEN_INVALID' && !tokenRetried) {
        console.warn('Netatmo scan: token invalid, forcing refresh');
        tokenRetried = true;
        invalidateToken();
        token = await getAccessToken(true);
        i -= 5;
        continue;
      }
      throw e;
    }
    // Rate limit delay: 300ms between batches
    if (i + 5 < smallTiles.length) {
      await new Promise(r => setTimeout(r, 300));
    }
  }
  console.log(`Netatmo scan pass 2: failed/empty tiles: ${failedTiles}/${smallTiles.length}`);

  console.log(`Netatmo scan: ${allRaw.length} total raw (pass1: ${pass1Count}, pass2: ${allRaw.length - pass1Count})`);

  // Parse and deduplicate
  const stationMap = new Map();
  for (const raw of allRaw) {
    const station = parseStation(raw);
    if (station && !stationMap.has(station.id)) {
      stationMap.set(station.id, station);
    }
  }

  const stations = Array.from(stationMap.values());

  // Update known stations registry (only grows, never shrinks)
  let knownRegistry = {};
  try {
    const blobs = await list({ prefix: 'netatmo-stations/known-ids.json' });
    if (blobs.blobs.length > 0) {
      const blobUrl = new URL(blobs.blobs[0].url);
      blobUrl.searchParams.set('_t', Date.now());
      const res = await fetch(blobUrl.toString(), { cache: 'no-store' });
      if (res.ok) knownRegistry = await res.json();
    }
  } catch (e) { /* first run */ }

  const previousCount = Object.keys(knownRegistry).length;
  for (const s of stations) {
    knownRegistry[s.id] = { name: s.name, lat: s.lat, lon: s.lon };
  }
  const newCount = Object.keys(knownRegistry).length;
  console.log(`Netatmo scan: registry ${previousCount} → ${newCount} known stations`);

  // Don't overwrite Blob if scan got nothing (rate limited / failed)
  if (stations.length === 0) {
    console.warn('Netatmo scan: 0 stations, skipping Blob write');
    return stations;
  }

  // Merge with existing Blob data to never lose stations
  let existingStations = [];
  try {
    const blobs = await list({ prefix: 'netatmo-stations/all.json' });
    if (blobs.blobs.length > 0) {
      const blobUrl = new URL(blobs.blobs[0].url);
      blobUrl.searchParams.set('_t', Date.now());
      const res = await fetch(blobUrl.toString(), { cache: 'no-store' });
      if (res.ok) existingStations = await res.json();
    }
  } catch (e) { /* first run */ }

  if (existingStations.length > 0) {
    // Merge: update existing with fresh data, keep stations not in fresh scan
    const freshById = new Map(stations.map(s => [s.id, s]));
    const mergedMap = new Map();

    // Keep all existing, update with fresh where available
    for (const s of existingStations) {
      const fresh = freshById.get(s.id);
      mergedMap.set(s.id, fresh || { ...s, isOnline: false });
      if (fresh) freshById.delete(s.id);
    }
    // Add genuinely new stations
    for (const s of freshById.values()) {
      mergedMap.set(s.id, s);
    }

    stations = Array.from(mergedMap.values());
    console.log(`Netatmo scan: merged ${existingStations.length} existing + fresh → ${stations.length} total`);
  }

  const writes = [
    put('netatmo-stations/all.json', JSON.stringify(stations), {
      access: 'public', addRandomSuffix: false, contentType: 'application/json',
    }),
  ];
  // Only update registry if we got a meaningful number of stations
  if (newCount > previousCount || stations.length > 1000) {
    writes.push(
      put('netatmo-stations/known-ids.json', JSON.stringify(knownRegistry), {
        access: 'public', addRandomSuffix: false, contentType: 'application/json',
      })
    );
  }
  await Promise.all(writes);

  return stations;
}

// History snapshot: fetch fresh wind data from Netatmo API and record for graphs
async function snapshotHistory() {
  // Unfiltered refresh with medium tiles — catches ALL stations including those missed by Netatmo's wind filter
  let token = await getAccessToken();
  const tiles = generateTiles(FRANCE_BBOX, 1.0, 1.2);
  const allRaw = [];
  let failedTiles = 0;
  let firstFailStatus = null;

  // Concurrency 5 + 300ms delay to stay within Netatmo rate limits (~50 req/10s)
  let rateLimited = false;
  let tokenRetried = false;
  for (let i = 0; i < tiles.length; i += 5) {
    const batch = tiles.slice(i, i + 5);
    try {
      const results = await Promise.all(batch.map(async t => {
        const r = await fetchTile(token, t);
        if (r.length === 0) failedTiles++;
        return r;
      }));
      for (const r of results) allRaw.push(...r);
    } catch (e) {
      if (e.message === 'NETATMO_RATE_LIMITED') {
        console.warn('Netatmo: rate limited, stopping tile fetch');
        rateLimited = true;
        break;
      }
      if (e.message === 'NETATMO_TOKEN_INVALID' && !tokenRetried) {
        console.warn('Netatmo: token invalid (403), forcing refresh and retrying');
        tokenRetried = true;
        invalidateToken();
        token = await getAccessToken(true);
        i -= 5; // Retry the same batch
        continue;
      }
      throw e;
    }
    if (i + 5 < tiles.length) {
      await new Promise(r => setTimeout(r, 300));
    }
  }

  console.log(`Netatmo snapshot: token=${token?.slice(0,20)}... | ${allRaw.length} raw from ${tiles.length} tiles (${failedTiles} empty, rateLimited=${rateLimited})`);

  // If rate limited, skip everything — don't overwrite Blob with incomplete data
  if (rateLimited) {
    return { status: 'rate_limited', message: 'Netatmo API rate limit reached, skipping update' };
  }

  // Parse fresh data
  const freshMap = new Map();
  for (const raw of allRaw) {
    const station = parseStation(raw);
    if (station && !freshMap.has(station.id)) {
      freshMap.set(station.id, station);
    }
  }
  console.log(`Netatmo snapshot: ${freshMap.size} parsed stations from ${allRaw.length} raw`);

  // Merge fresh wind values into existing stations list
  // Use known-ids registry as ground truth to never lose stations
  let stations = [];
  try {
    const blobs = await list({ prefix: 'netatmo-stations/all.json' });
    if (blobs.blobs.length > 0) {
      const blobUrl = new URL(blobs.blobs[0].url);
      blobUrl.searchParams.set('_t', Date.now());
      const res = await fetch(blobUrl.toString(), { cache: 'no-store' });
      if (res.ok) stations = await res.json();
    }
  } catch (e) { /* use fresh only */ }

  // Load known stations registry to restore any missing stations
  let knownRegistry = null;
  try {
    const blobs = await list({ prefix: 'netatmo-stations/known-ids.json' });
    if (blobs.blobs.length > 0) {
      const blobUrl = new URL(blobs.blobs[0].url);
      blobUrl.searchParams.set('_t', Date.now());
      const res = await fetch(blobUrl.toString(), { cache: 'no-store' });
      if (res.ok) knownRegistry = await res.json();
    }
  } catch (e) { /* no registry yet */ }

  const existingCount = stations.length;

  if (stations.length > 0) {
    // Update existing stations with fresh wind data
    const existingIds = new Set();
    for (let i = 0; i < stations.length; i++) {
      existingIds.add(stations[i].id);
      const fresh = freshMap.get(stations[i].id);
      if (fresh) {
        stations[i] = fresh;
        freshMap.delete(stations[i].id);
      }
    }

    // Add new stations from this snapshot
    for (const s of freshMap.values()) {
      if (!existingIds.has(s.id)) {
        stations.push(s);
        existingIds.add(s.id);
      }
    }

    // Restore known stations missing from current list (from registry)
    if (knownRegistry) {
      let restored = 0;
      for (const [id, meta] of Object.entries(knownRegistry)) {
        if (!existingIds.has(id)) {
          // Add a placeholder with last known position (offline, no wind data)
          stations.push({
            id,
            stableId: `netatmo_${id}`,
            name: meta.name,
            lat: meta.lat,
            lon: meta.lon,
            wind: 0, gust: 0, direction: 0,
            isOnline: false,
            source: 'netatmo',
            ts: null,
          });
          existingIds.add(id);
          restored++;
        }
      }
      if (restored > 0) {
        console.log(`Netatmo snapshot: restored ${restored} stations from registry`);
      }
    }

    await put('netatmo-stations/all.json', JSON.stringify(stations), {
      access: 'public', addRandomSuffix: false, contentType: 'application/json',
    });
  } else if (freshMap.size > 0) {
    // Blob was empty but we have fresh data — bootstrap from fresh + registry
    stations = Array.from(freshMap.values());
    const freshIds = new Set(stations.map(s => s.id));

    // Restore known stations from registry
    if (knownRegistry) {
      let restored = 0;
      for (const [id, meta] of Object.entries(knownRegistry)) {
        if (!freshIds.has(id)) {
          stations.push({
            id, stableId: `netatmo_${id}`,
            name: meta.name, lat: meta.lat, lon: meta.lon,
            wind: 0, gust: 0, direction: 0,
            isOnline: false, source: 'netatmo', ts: null,
          });
          restored++;
        }
      }
      if (restored > 0) console.log(`Netatmo snapshot: restored ${restored} from registry (bootstrap)`);
    }

    await put('netatmo-stations/all.json', JSON.stringify(stations), {
      access: 'public', addRandomSuffix: false, contentType: 'application/json',
    });
    console.log(`Netatmo snapshot: bootstrapped ${stations.length} stations to Blob`);
  }

  if (stations.length === 0) return { status: 'skip', reason: 'No stations' };

  const now = Date.now();
  const cutoff = now - RETENTION_MS;

  // Load existing history
  let allHistory = {};
  try {
    const histBlobs = await list({ prefix: 'netatmo-history/data.json' });
    if (histBlobs.blobs.length > 0) {
      const histRes = await fetch(histBlobs.blobs[0].url);
      if (histRes.ok) allHistory = await histRes.json();
    }
  } catch (e) { /* first run */ }

  let newPoints = 0;
  for (const station of stations) {
    if (!station.isOnline || !station.ts) continue;

    const key = station.stableId;
    if (!allHistory[key]) {
      allHistory[key] = {
        name: station.name,
        lat: station.lat,
        lon: station.lon,
        observations: [],
      };
    }

    allHistory[key].name = station.name;

    const ts = new Date(station.ts).getTime();
    const lastObs = allHistory[key].observations;

    const isDuplicate = lastObs.length > 0 &&
      Math.abs(ts - (lastObs[lastObs.length - 1]?.t || 0)) < 1 * 60 * 1000;

    if (!isDuplicate) {
      lastObs.push({
        t: ts,
        w: station.wind,
        g: station.gust,
        d: station.direction,
        tp: station.temperature ?? null,
      });
      newPoints++;
    }

    allHistory[key].observations = lastObs.filter(o => o.t > cutoff);
    if (allHistory[key].observations.length === 0) delete allHistory[key];
  }

  await put('netatmo-history/data.json', JSON.stringify(allHistory), {
    access: 'public',
    addRandomSuffix: false,
    contentType: 'application/json',
  });

  return {
    stationsProcessed: stations.length,
    freshFromAPI: allRaw.length,
    freshParsed: freshMap.size,
    stationsStored: Object.keys(allHistory).length,
    newPoints,
    totalObservations: Object.values(allHistory).reduce((sum, s) => sum + s.observations.length, 0),
  };
}

// Blob-based lock to prevent overlapping snapshot executions
async function acquireLock() {
  try {
    const blobs = await list({ prefix: 'netatmo-lock/snapshot.json' });
    if (blobs.blobs.length > 0) {
      const r = await fetch(blobs.blobs[0].url);
      if (r.ok) {
        const lock = await r.json();
        if (lock.ts && Date.now() - lock.ts < LOCK_TTL_MS) {
          return false; // Lock still held
        }
      }
    }
  } catch (e) { /* no lock = free */ }

  await put('netatmo-lock/snapshot.json', JSON.stringify({ ts: Date.now() }), {
    access: 'public', addRandomSuffix: false, contentType: 'application/json',
  });
  return true;
}

async function releaseLock() {
  try {
    await put('netatmo-lock/snapshot.json', JSON.stringify({ ts: 0 }), {
      access: 'public', addRandomSuffix: false, contentType: 'application/json',
    });
  } catch (e) { /* best effort */ }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const authHeader = req.headers.authorization;
  if (CRON_SECRET && authHeader !== `Bearer ${CRON_SECRET}`) {
    if (req.headers['x-vercel-cron'] !== '1') {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  const doScan = req.query.scan === 'true';
  const doTest = req.query.test === 'true';

  try {
    // Quick diagnostic: fetch 1 tile with full debug
    if (doTest) {
      const token = await getAccessToken();
      const testTile = { lat_sw: 48.8, lon_sw: 2.2, lat_ne: 48.9, lon_ne: 2.5 };

      // Direct API call (bypass fetchTile to see HTTP response)
      const directRes = await fetch('https://api.netatmo.com/api/getpublicdata', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          lat_ne: '48.9', lon_ne: '2.5',
          lat_sw: '48.8', lon_sw: '2.2',
        }).toString(),
      });

      const directBody = await directRes.text();
      let stationCount = 0;
      try { stationCount = JSON.parse(directBody).body?.length || 0; } catch (e) {}

      return res.json({
        status: 'test',
        tokenPrefix: token?.slice(0, 20) + '...',
        tokenLength: token?.length,
        httpStatus: directRes.status,
        stationCount,
        responsePreview: directBody.slice(0, 200),
      });
    }

    if (doScan) {
      const stations = await fullScan();
      return res.json({
        status: 'ok',
        mode: 'full-scan',
        stations: stations.length,
        timestamp: new Date().toISOString(),
      });
    }

    // Prevent overlapping snapshot runs (1-min cron)
    const locked = await acquireLock();
    if (!locked) {
      return res.json({ status: 'skipped', reason: 'Previous snapshot still running' });
    }

    try {
      const result = await snapshotHistory();
      return res.json({ status: 'ok', ...result, timestamp: new Date().toISOString() });
    } finally {
      await releaseLock();
    }

  } catch (e) {
    console.error('Netatmo cron error:', e);
    await releaseLock();
    return res.status(500).json({ error: e.message });
  }
}
