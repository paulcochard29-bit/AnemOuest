// Météo France History API
// Uses official Météo France API with date range (like iOS app)
//
// Usage:
//   GET /api/history?stationId=ID&hours=6

const MF_API_BASE = 'https://public-api.meteofrance.fr/public/DPPaquetObs/v1';
const MF_API_KEY = process.env.METEOFRANCE_API_KEY;
const MS_TO_KNOTS = 1.94384;

const historyCache = new Map();
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=30');

  const { stationId, hours = '6' } = req.query;

  if (!stationId) {
    return res.status(400).json({ error: 'stationId required' });
  }

  const hoursNum = Math.min(parseInt(hours) || 6, 168);
  const now = Date.now();
  const cacheKey = `${stationId}_${hoursNum}`;
  const cached = historyCache.get(cacheKey);

  if (cached && (now - cached.ts) < CACHE_DURATION) {
    return res.json({ observations: cached.data, cached: true, count: cached.data.length });
  }

  try {
    // Try with date range first (more reliable for longer periods)
    let observations = await fetchWithDateRange(stationId, hoursNum);

    // Fallback to simple call if date range fails
    if (!observations || observations.length === 0) {
      observations = await fetchSimple(stationId, hoursNum);
    }

    if (observations && observations.length > 0) {
      historyCache.set(cacheKey, { data: observations, ts: now });
    }

    return res.json({
      observations: observations || [],
      cached: false,
      count: observations?.length || 0,
      hours: hoursNum
    });
  } catch (e) {
    console.error('MF History error:', e);

    if (cached) {
      return res.json({
        observations: cached.data,
        cached: true,
        stale: true,
        count: cached.data.length
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch history',
      details: e.message
    });
  }
}

async function fetchWithDateRange(stationId, hours) {
  const endDate = new Date();
  const startDate = new Date(Date.now() - hours * 60 * 60 * 1000);

  const startStr = startDate.toISOString();
  const endStr = endDate.toISOString();

  const url = `${MF_API_BASE}/paquet/infrahoraire-6m?id_station=${stationId}&format=json` +
    `&date_deb_periode=${encodeURIComponent(startStr)}` +
    `&date_fin_periode=${encodeURIComponent(endStr)}`;

  const response = await fetch(url, {
    headers: { 'apikey': MF_API_KEY }
  });

  if (!response.ok) {
    console.log(`MF API date range: HTTP ${response.status} for ${stationId}`);
    return null;
  }

  const data = await response.json();

  if (!Array.isArray(data) || data.length === 0) {
    return null;
  }

  return data.map(d => ({
    ts: d.validity_time,
    wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
    gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
    dir: d.dd || 0
  })).sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());
}

async function fetchSimple(stationId, hours) {
  const url = `${MF_API_BASE}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`;

  const response = await fetch(url, {
    headers: { 'apikey': MF_API_KEY }
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const data = await response.json();

  if (!Array.isArray(data)) {
    return [];
  }

  const cutoff = Date.now() - (hours * 60 * 60 * 1000);

  return data
    .map(d => ({
      ts: d.validity_time,
      wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
      gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
      dir: d.dd || 0
    }))
    .filter(o => new Date(o.ts).getTime() >= cutoff)
    .sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());
}
