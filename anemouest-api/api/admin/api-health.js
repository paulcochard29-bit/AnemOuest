// API Health Check — tests all data sources and returns status/timing/errors
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

const SOURCES = [
  { id: 'meteofrance', name: 'Météo France (Atlantic)', url: '/api/meteofrance', key: 'METEOFRANCE_API_KEY' },
  { id: 'mf2', name: 'Météo France (Nord+Med)', url: '/api/mf2-stations', key: 'METEOFRANCE_API_KEY_2' },
  { id: 'gowind', name: 'GoWind (Holfuy)', url: '/api/gowind' },
  { id: 'gowind-native', name: 'GoWind Native', url: '/api/gowind-native' },
  { id: 'pioupiou', name: 'Pioupiou', url: '/api/pioupiou' },
  { id: 'windcornouaille', name: 'Wind France', url: '/api/windcornouaille' },
  { id: 'diabox', name: 'Diabox', url: '/api/diabox' },
  { id: 'ndbc', name: 'NDBC', url: '/api/ndbc' },
  { id: 'netatmo', name: 'Netatmo', url: '/api/netatmo', key: 'NETATMO_CLIENT_ID' },
  { id: 'candhis', name: 'CANDHIS (Bouées)', url: '/api/candhis' },
  { id: 'webcams', name: 'Webcams', url: '/api/webcams' },
  { id: 'tide', name: 'Marées', url: '/api/tide?lat=48.38&lon=-4.49' },
  { id: 'wind-raster', name: 'Vent animé (GFS)', url: '/api/wind-raster' },
  { id: 'skaping', name: 'Skaping (S3)', url: '/api/skaping?path=test', expectError: true },
  { id: 'vision', name: 'Vision-Environnement', url: '/api/vision?slug=brest-port', expectError: true },
  { id: 'viewsurf', name: 'Viewsurf', url: '/api/viewsurf?id=654' },
];

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (!isAuthorized(req)) return res.status(401).json({ error: 'Unauthorized' });

  const baseUrl = `http://localhost:${process.env.PORT || 3001}`;
  const apiKey = process.env.API_KEY || '';

  const results = await Promise.all(
    SOURCES.map(async (source) => {
      const start = Date.now();
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 15000);

        const r = await fetch(`${baseUrl}${source.url}`, {
          headers: { 'X-Api-Key': apiKey },
          signal: controller.signal,
        });
        clearTimeout(timeout);

        const elapsed = Date.now() - start;
        const contentType = r.headers.get('content-type') || '';
        let body = null;
        let stationCount = null;
        let error = null;

        if (contentType.includes('json')) {
          try {
            body = await r.json();
            // Extract station/data count
            if (body.stations) stationCount = body.stations.length;
            else if (body.buoys) stationCount = body.buoys.length;
            else if (body.webcams) stationCount = body.webcams.length;
            else if (body.ports) stationCount = body.ports.length;
            else if (body.count !== undefined) stationCount = body.count;
            if (body.error) error = body.error;
          } catch {}
        }

        // Check env key presence
        const keyPresent = source.key ? !!process.env[source.key] : null;

        return {
          id: source.id,
          name: source.name,
          status: r.status,
          ok: r.ok || source.expectError,
          elapsed,
          count: stationCount,
          error: error || (r.ok ? null : `HTTP ${r.status}`),
          keyConfigured: keyPresent,
          cached: body?.cached || body?.fromCache || false,
          lastUpdate: body?.lastUpdate || body?.timestamp || null,
        };
      } catch (err) {
        return {
          id: source.id,
          name: source.name,
          status: 0,
          ok: false,
          elapsed: Date.now() - start,
          count: null,
          error: err.name === 'AbortError' ? 'Timeout (15s)' : err.message,
          keyConfigured: source.key ? !!process.env[source.key] : null,
          cached: false,
          lastUpdate: null,
        };
      }
    })
  );

  const healthy = results.filter(r => r.ok).length;
  const total = results.length;

  // Webcam stats
  let webcamStats = null;
  try {
    const wcRes = await fetch(`${baseUrl}/api/webcams`, { headers: { 'X-Api-Key': apiKey } });
    if (wcRes.ok) {
      const wcData = await wcRes.json();
      const webcams = Array.isArray(wcData) ? wcData : wcData.webcams || [];
      const bySource = {};
      let withStream = 0;
      let withLastCapture = 0;
      for (const w of webcams) {
        bySource[w.source] = (bySource[w.source] || 0) + 1;
        if (w.streamUrl) withStream++;
        if (w.lastCapture) withLastCapture++;
      }
      webcamStats = {
        total: webcams.length,
        bySource,
        withStream,
        withLastCapture,
        withoutCapture: webcams.length - withLastCapture,
      };
    }
  } catch {}

  res.json({
    timestamp: new Date().toISOString(),
    summary: { healthy, total, percent: Math.round((healthy / total) * 100) },
    sources: results,
    webcamStats,
  });
}
