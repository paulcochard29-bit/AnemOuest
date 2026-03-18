// Netatmo Public Weather API - Wind stations
// Stations are discovered by the cron job (unfiltered scan) and stored in Blob.
// This API reads from Blob + does a fast filtered pass for fresh wind data.
//
// Usage:
//   GET /api/netatmo              - Returns all wind stations
//   GET /api/netatmo?history=ID   - Returns history for a station
//
// Required env vars:
//   NETATMO_CLIENT_ID
//   NETATMO_CLIENT_SECRET
//   NETATMO_REFRESH_TOKEN

import { list } from '../lib/storage.js';

const NETATMO_TOKEN_URL = 'https://api.netatmo.com/oauth2/token';
const NETATMO_API_URL = 'https://api.netatmo.com/api/getpublicdata';

// France métropolitaine + Corse bounding box
const FRANCE_BBOX = {
  lat_sw: 41.3, lon_sw: -5.2,
  lat_ne: 51.1, lon_ne: 9.6,
};

// In-memory cache
let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 2 * 60 * 1000; // 2 minutes (data refreshed every 5min by cron)

// Token cache
let tokenCache = { accessToken: null, refreshToken: null, expiresAt: 0 };
let tokenRefreshPromise = null; // Prevents concurrent token refreshes

const KMH_TO_KNOTS = 0.539957;

export async function getAccessToken(forceRefresh = false) {
  const now = Date.now();
  if (!forceRefresh && tokenCache.accessToken && tokenCache.expiresAt > now + 60000) {
    return tokenCache.accessToken;
  }

  // If another call is already refreshing, wait for it instead of duplicating
  if (tokenRefreshPromise) {
    return tokenRefreshPromise;
  }

  tokenRefreshPromise = _doRefreshToken(now, forceRefresh).finally(() => {
    tokenRefreshPromise = null;
  });
  return tokenRefreshPromise;
}

// Invalidate cached token (call when API returns 403)
export function invalidateToken() {
  tokenCache = { accessToken: null, refreshToken: tokenCache.refreshToken, expiresAt: 0 };
}

async function _doRefreshToken(now, forceRefresh = false) {

  // Try to load cached access token from Blob (avoids refresh token rotation on cold starts)
  if (!forceRefresh) {
    try {
      const { list: blobList } = await import('../lib/storage.js');
      const blobs = await blobList({ prefix: 'netatmo-token/access.json' });
      if (blobs.blobs.length > 0) {
        const r = await fetch(blobs.blobs[0].url);
        if (r.ok) {
          const cached = await r.json();
          if (cached.accessToken && cached.expiresAt > now + 60000) {
            tokenCache = cached;
            console.log('Netatmo: reusing access token from Blob (no refresh needed)');
            return cached.accessToken;
          }
        }
      }
    } catch (e) { /* no cached access token */ }
  } else {
    console.log('Netatmo: force refresh — skipping Blob access token cache');
  }

  const clientId = process.env.NETATMO_CLIENT_ID;
  const clientSecret = process.env.NETATMO_CLIENT_SECRET;

  // Get the latest refresh token: try Blob first (shared across instances), then env var
  let refreshToken = tokenCache.refreshToken;
  if (!refreshToken) {
    try {
      const { list: blobList } = await import('../lib/storage.js');
      const blobs = await blobList({ prefix: 'netatmo-token/refresh.txt' });
      if (blobs.blobs.length > 0) {
        const res = await fetch(blobs.blobs[0].url);
        if (res.ok) {
          refreshToken = (await res.text()).trim();
          console.log('Netatmo: loaded refresh token from Blob');
        }
      }
    } catch (e) { /* first run, no blob */ }
  }
  if (!refreshToken) {
    refreshToken = process.env.NETATMO_REFRESH_TOKEN;
  }

  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error('Missing Netatmo credentials');
  }

  let res = await fetch(NETATMO_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
    }).toString(),
  });

  // If Blob token failed, fallback to env var token
  if (!res.ok && refreshToken !== process.env.NETATMO_REFRESH_TOKEN) {
    console.warn('Netatmo: Blob token failed, trying env var token');
    refreshToken = process.env.NETATMO_REFRESH_TOKEN;
    res = await fetch(NETATMO_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
      }).toString(),
    });
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Netatmo token error: ${res.status} - ${text}`);
  }

  const data = await res.json();
  const newRefreshToken = data.refresh_token || refreshToken;

  tokenCache = {
    accessToken: data.access_token,
    refreshToken: newRefreshToken,
    expiresAt: now + (data.expires_in || 10800) * 1000,
  };

  // Persist both access token and refresh token to Blob
  try {
    const { put } = await import('../lib/storage.js');
    await Promise.all([
      put('netatmo-token/refresh.txt', newRefreshToken, {
        access: 'public', addRandomSuffix: false, contentType: 'text/plain',
      }),
      put('netatmo-token/access.json', JSON.stringify({
        accessToken: tokenCache.accessToken,
        expiresAt: tokenCache.expiresAt,
      }), {
        access: 'public', addRandomSuffix: false, contentType: 'application/json',
      }),
    ]);
  } catch (e) {
    console.warn('Failed to persist tokens:', e.message);
  }

  return tokenCache.accessToken;
}

export function generateTiles(bbox, latStep, lonStep) {
  const tiles = [];
  for (let lat = bbox.lat_sw; lat < bbox.lat_ne; lat += latStep) {
    for (let lon = bbox.lon_sw; lon < bbox.lon_ne; lon += lonStep) {
      tiles.push({
        lat_sw: lat, lon_sw: lon,
        lat_ne: Math.min(lat + latStep, bbox.lat_ne),
        lon_ne: Math.min(lon + lonStep, bbox.lon_ne),
      });
    }
  }
  return tiles;
}

export async function fetchTile(token, tile) {
  // NO required_data filter — fetch ALL stations, we filter for NAModule2 ourselves
  const res = await fetch(NETATMO_API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      lat_ne: String(tile.lat_ne),
      lon_ne: String(tile.lon_ne),
      lat_sw: String(tile.lat_sw),
      lon_sw: String(tile.lon_sw),
    }).toString(),
  });

  if (!res.ok) {
    console.warn(`Netatmo tile HTTP ${res.status} [${tile.lat_sw.toFixed(1)},${tile.lon_sw.toFixed(1)}]`);
    if (res.status === 429) {
      throw new Error('NETATMO_RATE_LIMITED');
    }
    if (res.status === 403) {
      throw new Error('NETATMO_TOKEN_INVALID');
    }
    return [];
  }

  const data = await res.json();
  return data.body || [];
}

export function parseStation(raw) {
  const id = raw._id;
  if (!id) return null;

  const location = raw.place?.location;
  if (!location || location.length < 2) return null;

  const lon = location[0];
  const lat = location[1];
  if (!lat || !lon) return null;

  // Only keep French stations
  const country = raw.place?.country;
  if (country && country !== 'FR') return null;

  // Find wind data from ANY module — don't rely on NAModule2 flag, just check actual data
  const measures = raw.measures || {};
  let windData = null;
  for (const moduleInfo of Object.values(measures)) {
    if (moduleInfo.wind_strength !== undefined || moduleInfo.wind_angle !== undefined) {
      windData = moduleInfo;
      break;
    }
  }
  // No wind data at all → skip this station
  if (!windData) return null;

  const windKmh = windData?.wind_strength || 0;
  const gustKmh = windData?.gust_strength || 0;
  const direction = windData?.wind_angle || 0;
  const windTimestamp = windData?.wind_timeutc ? windData.wind_timeutc * 1000 : null;

  const wind = windKmh * KMH_TO_KNOTS;
  const gust = gustKmh * KMH_TO_KNOTS;
  const isOnline = windTimestamp && (Date.now() - windTimestamp < 30 * 60 * 1000);

  // Temperature, humidity, pressure from other modules
  let temperature = null;
  let humidity = null;
  let pressure = null;
  for (const moduleInfo of Object.values(measures)) {
    if (moduleInfo.res && moduleInfo.type) {
      const resEntries = Object.values(moduleInfo.res);
      if (resEntries.length > 0) {
        const values = resEntries[0];
        const tempIdx = moduleInfo.type.indexOf('temperature');
        if (tempIdx !== -1 && values[tempIdx] !== undefined) temperature = values[tempIdx];
        const humIdx = moduleInfo.type.indexOf('humidity');
        if (humIdx !== -1 && values[humIdx] !== undefined) humidity = values[humIdx];
        const pressIdx = moduleInfo.type.indexOf('pressure');
        if (pressIdx !== -1 && values[pressIdx] !== undefined) pressure = values[pressIdx];
      }
    }
  }

  const city = raw.place?.city || raw.place?.street || null;
  const name = city || `Netatmo ${id.slice(-5)}`;
  const cleanId = id.replace(/:/g, '');

  return {
    id: cleanId,
    stableId: `netatmo_${cleanId}`,
    name,
    lat,
    lon,
    wind: Math.round(wind * 10) / 10,
    gust: Math.round(gust * 10) / 10,
    direction,
    isOnline: !!isOnline,
    source: 'netatmo',
    ts: windTimestamp ? new Date(windTimestamp).toISOString() : null,
    temperature,
    humidity,
    pressure,
    altitude: raw.place?.altitude || null,
  };
}

// Main API: reads stations from Blob (populated by cron)
async function getStationsFromBlob() {
  try {
    const blobs = await list({ prefix: 'netatmo-stations/all.json' });
    if (blobs.blobs.length > 0) {
      const blobUrl = new URL(blobs.blobs[0].url);
      blobUrl.searchParams.set('_t', Date.now());
      const res = await fetch(blobUrl.toString(), { cache: 'no-store' });
      if (res.ok) {
        return await res.json();
      }
    }
  } catch (e) {
    console.warn('Failed to load stations from Blob:', e.message);
  }
  return null;
}

async function refreshStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  // Read all stations from Blob (populated by cron's unfiltered scan)
  const blobStations = await getStationsFromBlob();

  if (blobStations && blobStations.length > 0) {
    console.log(`Netatmo: loaded ${blobStations.length} stations from Blob`);
    stationsCache = { data: blobStations, timestamp: now };
    return { stations: blobStations, cached: false };
  }

  // Fallback: if no Blob data yet, do a quick filtered scan
  console.log('Netatmo: no Blob data, doing fallback filtered scan');
  const token = await getAccessToken();
  const tiles = generateTiles(FRANCE_BBOX, 3.3, 3.8);
  const allRaw = [];

  for (let i = 0; i < tiles.length; i += 3) {
    const batch = tiles.slice(i, i + 3);
    const results = await Promise.all(batch.map(async t => {
      const res = await fetch(NETATMO_API_URL, {
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
      if (!res.ok) return [];
      const data = await res.json();
      return data.body || [];
    }));
    for (const r of results) allRaw.push(...r);
  }

  const stationMap = new Map();
  for (const raw of allRaw) {
    const station = parseStation(raw);
    if (station && !stationMap.has(station.id)) {
      stationMap.set(station.id, station);
    }
  }

  const stations = Array.from(stationMap.values());
  stationsCache = { data: stations, timestamp: now };
  return { stations, cached: false };
}

// Fetch history from Vercel Blob
async function fetchHistory(stationId, hours) {
  const blobs = await list({ prefix: 'netatmo-history/data.json' });
  if (blobs.blobs.length === 0) return [];

  const res = await fetch(blobs.blobs[0].url);
  if (!res.ok) return [];

  const allHistory = await res.json();
  const stationData = allHistory[stationId];
  if (!stationData) return [];

  const cutoff = Date.now() - hours * 60 * 60 * 1000;

  return stationData.observations
    .filter(o => o.t > cutoff)
    .map(o => ({
      ts: new Date(o.t).toISOString(),
      wind: o.w,
      gust: o.g,
      dir: o.d,
      temperature: o.tp,
    }));
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=300');

  const { history, hours = '24', lat_sw, lon_sw, lat_ne, lon_ne } = req.query;

  try {
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 24, 48);
      const observations = await fetchHistory(history, hoursNum);
      return res.json({
        stationId: history,
        source: 'netatmo',
        observations,
        count: observations.length,
        hours: hoursNum,
      });
    }

    const { stations: allStations, cached } = await refreshStations();

    // Viewport filtering: only return stations in bounding box
    let stations = allStations;
    if (lat_sw && lon_sw && lat_ne && lon_ne) {
      const sw = { lat: parseFloat(lat_sw), lon: parseFloat(lon_sw) };
      const ne = { lat: parseFloat(lat_ne), lon: parseFloat(lon_ne) };
      stations = allStations.filter(s =>
        s.lat >= sw.lat && s.lat <= ne.lat &&
        s.lon >= sw.lon && s.lon <= ne.lon
      );
    }

    return res.json({
      stations,
      cached,
      count: stations.length,
      total: allStations.length,
      timestamp: new Date().toISOString(),
    });
  } catch (e) {
    console.error('Netatmo error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message,
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch Netatmo data',
      details: e.message,
    });
  }
}
