// Pioupiou API - Stations and history endpoint
// Fetches from Pioupiou API, uses archive API for history
//
// Usage:
//   GET /api/pioupiou              - Returns all stations (current data)
//   GET /api/pioupiou?history=ID   - Returns history for station ID
//   GET /api/pioupiou?hours=6      - Filter history by hours (default 6)

const PIOUPIOU_API = 'https://api.pioupiou.fr/v1/live-with-meta/all';
const PIOUPIOU_ARCHIVE_API = 'https://api.pioupiou.fr/v1/archive';

// In-memory cache for current stations
let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

// France bounding box
function isInFrance(lat, lon) {
  return lat >= 41.3 && lat <= 51.2 && lon >= -5.5 && lon <= 9.7;
}

// km/h to knots
const KMH_TO_KNOTS = 0.539957;

function parseStation(station) {
  const id = String(station.id || '');
  const lat = station.location?.latitude || 0;
  const lon = station.location?.longitude || 0;

  if (!id || lat === 0 || lon === 0 || !isInFrance(lat, lon)) {
    return null;
  }

  const windKmh = station.measurements?.wind_speed_avg || 0;
  const gustKmh = station.measurements?.wind_speed_max || 0;
  const direction = station.measurements?.wind_heading || 0;

  const wind = windKmh * KMH_TO_KNOTS;
  const gust = gustKmh * KMH_TO_KNOTS;

  const lastUpdate = station.measurements?.date ? new Date(station.measurements.date) : null;
  const isOnline = lastUpdate && (Date.now() - lastUpdate.getTime() < 30 * 60 * 1000);

  // Extract additional metadata
  const description = station.meta?.description || null;
  const picture = station.meta?.picture || null;
  const pressure = station.measurements?.pressure || null; // hPa
  const state = station.status?.state || null; // "on", "off"

  return {
    id,
    stableId: `pioupiou_${id}`,
    name: station.meta?.name || `Pioupiou ${id}`,
    lat,
    lon,
    wind: Math.round(wind * 10) / 10,
    gust: Math.round(gust * 10) / 10,
    direction,
    isOnline,
    source: 'pioupiou',
    ts: lastUpdate ? lastUpdate.toISOString() : null,
    // Additional metadata
    description,
    picture,
    pressure,
    state
  };
}

// Fetch history from Pioupiou archive API
async function fetchArchive(stationId, hours) {
  const now = new Date();
  const start = new Date(now.getTime() - hours * 60 * 60 * 1000);

  const startStr = start.toISOString();
  const stopStr = now.toISOString();

  // Remove pioupiou_ prefix if present
  const rawId = stationId.replace(/^pioupiou_/, '');

  const url = `${PIOUPIOU_ARCHIVE_API}/${rawId}?start=${startStr}&stop=${stopStr}`;

  const response = await fetch(url, {
    headers: { 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`Archive API error: ${response.status}`);
  }

  const data = await response.json();

  if (data.error_code) {
    throw new Error(data.error_message || 'Archive error');
  }

  // Transform archive data to observations format
  // Legend: ["time","latitude","longitude","wind_speed_min","wind_speed_avg","wind_speed_max","wind_heading","pressure"]
  const observations = (data.data || []).map(row => ({
    ts: row[0],
    wind: Math.round((row[4] || 0) * KMH_TO_KNOTS * 10) / 10, // wind_speed_avg
    gust: Math.round((row[5] || 0) * KMH_TO_KNOTS * 10) / 10, // wind_speed_max
    dir: row[6] || 0 // wind_heading
  }));

  return observations;
}

async function fetchPioupiou() {
  const response = await fetch(PIOUPIOU_API, {
    headers: { 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`Pioupiou API error: ${response.status}`);
  }

  return response.json();
}

async function refreshStations() {
  const now = Date.now();

  // Return cached if fresh
  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const data = await fetchPioupiou();
  const stations = [];

  if (data.data && Array.isArray(data.data)) {
    for (const s of data.data) {
      const station = parseStation(s);
      if (station) {
        stations.push(station);
      }
    }
  }

  stationsCache = { data: stations, timestamp: now };
  return { stations, cached: false };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=300');

  const { history, hours = '6' } = req.query;

  try {
    // If history requested, fetch from archive API
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 6, 168); // Max 7 days

      try {
        const observations = await fetchArchive(history, hoursNum);

        return res.json({
          stationId: history,
          source: 'pioupiou',
          observations,
          count: observations.length,
          hours: hoursNum
        });
      } catch (archiveError) {
        return res.json({
          stationId: history,
          observations: [],
          error: archiveError.message,
          hours: hoursNum
        });
      }
    }

    // Return all stations (current data)
    const { stations, cached } = await refreshStations();

    return res.json({
      stations,
      cached,
      count: stations.length,
      timestamp: new Date().toISOString()
    });

  } catch (e) {
    console.error('Pioupiou error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch Pioupiou data',
      details: e.message
    });
  }
}
