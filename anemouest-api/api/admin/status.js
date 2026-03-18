// Admin API Status - Aggregates server-side health from all wind data endpoints
// No auth required (read-only, no sensitive data)
//
// GET /api/admin/status → { sources: [...], timestamp }

const API_BASE = 'http://localhost:3001';

const SOURCES = [
  { key: 'windcornouaille', endpoint: '/api/windcornouaille', label: 'Wind France' },
  { key: 'meteofrance', endpoint: '/api/meteofrance', label: 'Météo France' },
  { key: 'pioupiou', endpoint: '/api/pioupiou', label: 'Pioupiou' },
  { key: 'gowind', endpoint: '/api/gowind', label: 'GoWind (Holfuy+Windguru)' },
  { key: 'diabox', endpoint: '/api/diabox', label: 'Diabox' },
  { key: 'netatmo', endpoint: '/api/netatmo', label: 'Netatmo' },
  { key: 'candhis', endpoint: '/api/candhis', label: 'CANDHIS (bouées)' },
  { key: 'webcams', endpoint: '/api/webcams', label: 'Webcams' },
];

async function pingSource(source) {
  const url = `${API_BASE}${source.endpoint}`;
  const start = Date.now();

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);

    const res = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'AnemOuest-Status/1.0' },
    });
    clearTimeout(timeout);

    const ms = Date.now() - start;

    if (!res.ok) {
      return {
        key: source.key,
        label: source.label,
        endpoint: source.endpoint,
        status: 'error',
        httpStatus: res.status,
        durationMs: ms,
        error: `HTTP ${res.status}`,
      };
    }

    const json = await res.json();

    // Extract common fields from API responses
    const count = json.count ?? json.stations?.length ?? json.buoys?.length ?? json.webcams?.length ?? null;
    const cached = json.cached ?? false;
    const stale = json.stale ?? false;
    const serverTimestamp = json.timestamp ?? json.cacheTimestamp ?? null;
    const serverError = json.error ?? null;

    return {
      key: source.key,
      label: source.label,
      endpoint: source.endpoint,
      status: serverError ? 'degraded' : 'ok',
      count,
      cached,
      stale,
      durationMs: ms,
      serverTimestamp,
      serverError,
    };
  } catch (e) {
    return {
      key: source.key,
      label: source.label,
      endpoint: source.endpoint,
      status: 'error',
      durationMs: Date.now() - start,
      error: e.name === 'AbortError' ? 'Timeout (8s)' : e.message,
    };
  }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=30, stale-while-revalidate=60');

  try {
    // Ping all sources in parallel
    const results = await Promise.all(SOURCES.map(pingSource));

    return res.json({
      sources: results,
      timestamp: new Date().toISOString(),
      totalMs: results.reduce((sum, r) => Math.max(sum, r.durationMs), 0),
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
