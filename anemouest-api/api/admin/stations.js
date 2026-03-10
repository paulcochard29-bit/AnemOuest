// Admin API for wind station management
// CRUD operations on station overrides/additions stored in Vercel KV
// Aggregates live data from all 10 sources + KV overrides + custom stations
//
// Usage:
//   GET /api/admin/stations              - Returns all stations (live + KV merged)
//   GET /api/admin/stations?action=export - Clean export without flags
//   GET /api/admin/stations?action=stats  - Per-source statistics
//   PUT /api/admin/stations?id=stableId   - Update override for station
//   POST /api/admin/stations              - Add custom station
//   DELETE /api/admin/stations?id=stableId - Hide base station or delete custom

import { kv } from '@vercel/kv';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const API_BASE = 'https://anemouest-api.vercel.app/api';
const API2_BASE = 'https://anemouest-api-2.vercel.app/api';
const FFVL_API = 'https://data.ffvl.fr/json/balises.json';

const KV_OVERRIDES = 'station_overrides';
const KV_ADDITIONS = 'station_additions';

const KMH_TO_KNOTS = 0.539957;

// ============================================================
// AUTH
// ============================================================

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

// ============================================================
// DATA SOURCES
// ============================================================

// France bounding box
function isInFrance(lat, lon) {
  return lat >= 41.3 && lat <= 51.2 && lon >= -5.5 && lon <= 9.7;
}

// Fetch with timeout
async function fetchWithTimeout(url, options = {}, timeout = 8000) {
  try {
    const response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(timeout)
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

// Fetch all sources in parallel
async function fetchAllLiveSources() {
  const sources = [
    // API-1 endpoints
    { url: `${API_BASE}/gowind`, transform: transformGoWind },
    { url: `${API_BASE}/pioupiou`, transform: transformPioupiou },
    { url: `${API_BASE}/windcornouaille`, transform: transformWindCornouaille },
    { url: `${API_BASE}/diabox`, transform: transformDiabox },
    { url: `${API_BASE}/stations`, transform: transformMFStations }, // Meteo France Atlantic
    // API-2 endpoint (Nord + Mediterranean)
    { url: `${API2_BASE}/stations`, transform: transformMFStations },
    // Direct FFVL fetch
    { url: FFVL_API, transform: transformFFVL },
    // NDBC offshore buoys
    { url: `${API_BASE}/ndbc`, transform: transformNDBC },
    // Netatmo community stations (large dataset, longer timeout)
    { url: `${API_BASE}/netatmo`, transform: transformNetatmo, timeout: 15000 },
  ];

  const results = await Promise.allSettled(
    sources.map(async ({ url, transform, timeout }) => {
      const data = await fetchWithTimeout(url, {}, timeout || 8000);
      return data ? transform(data) : [];
    })
  );

  const allStations = [];
  const seenIds = new Set();

  for (const result of results) {
    if (result.status === 'fulfilled') {
      for (const station of result.value) {
        if (!seenIds.has(station.stableId)) {
          seenIds.add(station.stableId);
          allStations.push(station);
        }
      }
    }
  }

  return allStations;
}

// Transform functions for each source

function transformGoWind(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `${s.source}_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: s.source,
        ts: s.ts || null,
      });
    }
  }
  return stations;
}

function transformPioupiou(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `pioupiou_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: 'pioupiou',
        ts: s.ts || null,
        description: s.description || null,
        picture: s.picture || null,
        pressure: s.pressure || null,
      });
    }
  }
  return stations;
}

function transformWindCornouaille(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `windcornouaille_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: 'windcornouaille',
        ts: s.ts || null,
      });
    }
  }
  return stations;
}

function transformDiabox(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `diabox_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: 'diabox',
        ts: s.ts || null,
        temperature: s.temperature || null,
        pressure: s.pressure || null,
        humidity: s.humidity || null,
      });
    }
  }
  return stations;
}

function transformMFStations(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: `meteofrance_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: Math.round((s.wind || 0) * 10) / 10,
        gust: Math.round((s.gust || 0) * 10) / 10,
        direction: s.dir || 0,
        isOnline: s.ts ? (Date.now() - new Date(s.ts).getTime() < 30 * 60 * 1000) : false,
        source: 'meteofrance',
        ts: s.ts || null,
        temperature: s.temperature || null,
        pressure: s.pressure || null,
        humidity: s.humidity || null,
      });
    }
  }
  return stations;
}

function transformNDBC(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `ndbc_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: 'ndbc',
        ts: s.ts || null,
        temperature: s.temperature || null,
        waterTemp: s.waterTemp || null,
        pressure: s.pressure || null,
      });
    }
  }
  return stations;
}

function transformNetatmo(data) {
  const stations = [];
  if (data.stations && Array.isArray(data.stations)) {
    for (const s of data.stations) {
      stations.push({
        stableId: s.stableId || `netatmo_${s.id}`,
        id: String(s.id),
        name: s.name,
        latitude: s.lat,
        longitude: s.lon,
        wind: s.wind || 0,
        gust: s.gust || 0,
        direction: s.direction || 0,
        isOnline: s.isOnline || false,
        source: 'netatmo',
        ts: s.ts || null,
        temperature: s.temperature || null,
        humidity: s.humidity || null,
        pressure: s.pressure || null,
        altitude: s.altitude || null,
      });
    }
  }
  return stations;
}

function transformFFVL(data) {
  const stations = [];
  if (Array.isArray(data)) {
    for (const s of data) {
      const lat = parseFloat(s.lat);
      const lon = parseFloat(s.lon);
      if (!lat || !lon || !isInFrance(lat, lon)) continue;

      const windKmh = parseFloat(s.vitesse) || 0;
      const gustKmh = parseFloat(s.vitesseMax) || 0;
      const direction = parseFloat(s.direction) || 0;

      // Parse date: "2026-02-05 10:30:00"
      let ts = null;
      let isOnline = false;
      if (s.date) {
        const d = new Date(s.date.replace(' ', 'T') + '+01:00');
        if (!isNaN(d.getTime())) {
          ts = d.toISOString();
          isOnline = (Date.now() - d.getTime()) < 60 * 60 * 1000;
        }
      }

      stations.push({
        stableId: `ffvl_${s.idBalise}`,
        id: String(s.idBalise),
        name: s.nom || `FFVL ${s.idBalise}`,
        latitude: lat,
        longitude: lon,
        wind: Math.round(windKmh * KMH_TO_KNOTS * 10) / 10,
        gust: Math.round(gustKmh * KMH_TO_KNOTS * 10) / 10,
        direction,
        isOnline,
        source: 'ffvl',
        ts,
        altitude: s.altitude ? parseInt(s.altitude) : null,
      });
    }
  }
  return stations;
}

// ============================================================
// MERGE WITH KV
// ============================================================

async function getMergedStations(liveStations) {
  let merged = [...liveStations];

  try {
    const [overrides, additions] = await Promise.all([
      kv.hgetall(KV_OVERRIDES),
      kv.hgetall(KV_ADDITIONS)
    ]);

    // Apply overrides
    if (overrides) {
      merged = merged.map(s => {
        const ov = overrides[s.stableId];
        if (!ov) return s;
        const parsed = typeof ov === 'string' ? JSON.parse(ov) : ov;
        if (parsed._hidden) return null;
        return { ...s, ...parsed, _hasOverride: true };
      }).filter(Boolean);
    }

    // Add custom stations
    if (additions) {
      for (const [stableId, data] of Object.entries(additions)) {
        const parsed = typeof data === 'string' ? JSON.parse(data) : data;
        // Custom stations have no live data
        merged.push({
          stableId,
          id: parsed.id || stableId.replace('custom_', ''),
          name: parsed.name || 'Custom Station',
          latitude: parsed.latitude || 0,
          longitude: parsed.longitude || 0,
          wind: 0,
          gust: 0,
          direction: 0,
          isOnline: false,
          source: 'custom',
          ts: null,
          ...parsed,
          _isAddition: true,
        });
      }
    }
  } catch (e) {
    console.error('KV read error:', e.message);
  }

  return merged;
}

// ============================================================
// STATISTICS
// ============================================================

function computeStats(stations) {
  const sources = {};
  let online = 0;
  let offline = 0;
  let withOverride = 0;
  let additions = 0;

  for (const s of stations) {
    sources[s.source] = (sources[s.source] || 0) + 1;
    if (s.isOnline) online++;
    else offline++;
    if (s._hasOverride) withOverride++;
    if (s._isAddition) additions++;
  }

  return { total: stations.length, online, offline, withOverride, additions, sources };
}

// ============================================================
// HANDLER
// ============================================================

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();

  // Auth
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // GET requests
    if (req.method === 'GET') {
      const { action } = req.query;

      const liveStations = await fetchAllLiveSources();
      const merged = await getMergedStations(liveStations);

      // Statistics
      if (action === 'stats') {
        return res.json(computeStats(merged));
      }

      // Export (clean, no flags)
      if (action === 'export') {
        const clean = merged.map(s => {
          const { _hasOverride, _isAddition, ...rest } = s;
          return rest;
        });
        return res.json({
          stations: clean,
          count: clean.length,
          exportedAt: new Date().toISOString()
        });
      }

      // Default: full list
      const stats = computeStats(merged);
      return res.json({
        stations: merged,
        count: merged.length,
        ...stats,
        timestamp: new Date().toISOString()
      });
    }

    // PUT - Update override
    if (req.method === 'PUT') {
      const { id } = req.query;
      if (!id) {
        return res.status(400).json({ error: 'Missing id parameter' });
      }

      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      if (!body || Object.keys(body).length === 0) {
        return res.status(400).json({ error: 'Empty body' });
      }

      // Check if this is a custom station
      const additions = await kv.hgetall(KV_ADDITIONS) || {};
      if (additions[id]) {
        // Update the addition directly
        const existing = typeof additions[id] === 'string' ? JSON.parse(additions[id]) : additions[id];
        const updated = { ...existing, ...body };
        await kv.hset(KV_ADDITIONS, { [id]: JSON.stringify(updated) });
        return res.json({ success: true, station: updated, type: 'addition' });
      }

      // Otherwise, create/update override for base station
      const overrides = await kv.hgetall(KV_OVERRIDES) || {};
      const existing = overrides[id] ? (typeof overrides[id] === 'string' ? JSON.parse(overrides[id]) : overrides[id]) : {};
      const updated = { ...existing, ...body };
      await kv.hset(KV_OVERRIDES, { [id]: JSON.stringify(updated) });

      return res.json({ success: true, station: updated, type: 'override' });
    }

    // POST - Add custom station
    if (req.method === 'POST') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;

      if (!body.name || body.latitude === undefined || body.longitude === undefined) {
        return res.status(400).json({ error: 'Missing required fields: name, latitude, longitude' });
      }

      // Generate stableId if not provided
      const stableId = body.stableId || `custom_${Date.now()}`;
      const id = body.id || String(Date.now());

      const station = {
        stableId,
        id,
        name: body.name,
        latitude: body.latitude,
        longitude: body.longitude,
        source: 'custom',
        altitude: body.altitude || null,
        description: body.description || null,
        picture: body.picture || null,
        region: body.region || null,
        tags: body.tags || null,
        _notes: body._notes || null,
        _priority: body._priority || 0,
        _associatedWebcamId: body._associatedWebcamId || null,
        _associatedKiteSpotId: body._associatedKiteSpotId || null,
      };

      await kv.hset(KV_ADDITIONS, { [stableId]: JSON.stringify(station) });

      return res.json({ success: true, station: { ...station, _isAddition: true } });
    }

    // DELETE - Hide or remove station
    if (req.method === 'DELETE') {
      const { id } = req.query;
      if (!id) {
        return res.status(400).json({ error: 'Missing id parameter' });
      }

      // Check if it's a custom station
      const additions = await kv.hgetall(KV_ADDITIONS) || {};
      if (additions[id]) {
        await kv.hdel(KV_ADDITIONS, id);
        return res.json({ success: true, deleted: true });
      }

      // Otherwise, hide via override
      const overrides = await kv.hgetall(KV_OVERRIDES) || {};
      const existing = overrides[id] ? (typeof overrides[id] === 'string' ? JSON.parse(overrides[id]) : overrides[id]) : {};
      const updated = { ...existing, _hidden: true };
      await kv.hset(KV_OVERRIDES, { [id]: JSON.stringify(updated) });

      return res.json({ success: true, hidden: true });
    }

    return res.status(405).json({ error: 'Method not allowed' });

  } catch (e) {
    console.error('Admin stations error:', e);
    return res.status(500).json({ error: e.message });
  }
}
