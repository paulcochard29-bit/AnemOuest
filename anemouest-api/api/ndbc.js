// NDBC (National Data Buoy Center) wind stations
// Fetches real-time meteorological data from NOAA NDBC buoys
//
// Usage:
//   GET /api/ndbc              - Returns latest data for all configured stations
//   GET /api/ndbc?history=ID   - Returns history for a station (up to 48h)

const NDBC_REALTIME_URL = 'https://www.ndbc.noaa.gov/data/realtime2';

const MS_TO_KNOTS = 1.94384;

// Configured NDBC stations (add more here as needed)
const STATIONS = [
  { id: '62163', name: 'Bouée Bretagne', lat: 47.550, lon: -8.470 },
  { id: '62107', name: 'Sevenstones Lightship', lat: 50.102, lon: -6.100 },
  { id: '62050', name: 'E1 Buoy', lat: 50.000, lon: -4.400 },
  { id: '62103', name: 'Channel Lightship', lat: 49.900, lon: -2.900 },
  { id: '62305', name: 'Greenwich Lightship', lat: 50.400, lon: 0.000 },
  { id: '62304', name: 'Sandettie Lightship', lat: 51.102, lon: 1.800 },
  { id: '62170', name: 'F3 Light Vessel', lat: 51.240, lon: 2.000 },
];

// In-memory cache
let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes (NDBC data is hourly)

function parseLine(headers, line) {
  const parts = line.trim().split(/\s+/);
  if (parts.length < headers.length) return null;

  const obj = {};
  for (let i = 0; i < headers.length; i++) {
    obj[headers[i]] = parts[i] === 'MM' ? null : parts[i];
  }
  return obj;
}

function parseTimestamp(row) {
  if (!row['#YY'] || !row['MM'] || !row['DD'] || !row['hh'] || !row['mm']) return null;
  const y = parseInt(row['#YY']);
  const mo = parseInt(row['MM']) - 1;
  const d = parseInt(row['DD']);
  const h = parseInt(row['hh']);
  const mi = parseInt(row['mm']);
  return new Date(Date.UTC(y, mo, d, h, mi));
}

function rowToStation(row, stationConfig, timestamp) {
  const wspd = row['WSPD'] ? parseFloat(row['WSPD']) : null;
  const gst = row['GST'] ? parseFloat(row['GST']) : null;
  const wdir = row['WDIR'] ? parseFloat(row['WDIR']) : null;

  if (wspd === null) return null;

  const windKnots = wspd * MS_TO_KNOTS;
  const gustKnots = gst !== null ? gst * MS_TO_KNOTS : windKnots;
  const isOnline = timestamp && (Date.now() - timestamp.getTime() < 3 * 60 * 60 * 1000); // 3h (hourly data)

  return {
    id: stationConfig.id,
    stableId: `ndbc_${stationConfig.id}`,
    name: stationConfig.name,
    lat: stationConfig.lat,
    lon: stationConfig.lon,
    wind: Math.round(windKnots * 10) / 10,
    gust: Math.round(gustKnots * 10) / 10,
    direction: wdir || 0,
    isOnline: !!isOnline,
    source: 'ndbc',
    ts: timestamp ? timestamp.toISOString() : null,
    temperature: row['ATMP'] ? parseFloat(row['ATMP']) : null,
    waterTemp: row['WTMP'] ? parseFloat(row['WTMP']) : null,
    pressure: row['PRES'] ? parseFloat(row['PRES']) : null,
    dewPoint: row['DEWP'] ? parseFloat(row['DEWP']) : null,
  };
}

async function fetchStationData(stationId) {
  const url = `${NDBC_REALTIME_URL}/${stationId}.txt`;
  const res = await fetch(url, { headers: { 'User-Agent': 'AnemOuest/1.0' } });
  if (!res.ok) {
    console.warn(`NDBC fetch failed for ${stationId}: HTTP ${res.status}`);
    return null;
  }

  const text = await res.text();
  const lines = text.trim().split('\n');
  if (lines.length < 3) return null;

  // Parse headers from first line
  const headers = lines[0].trim().split(/\s+/);
  // Skip units line (line 1), data starts at line 2
  const dataLines = lines.slice(2);

  return { headers, dataLines };
}

async function getLatestStations() {
  const now = Date.now();
  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const stations = [];
  for (const config of STATIONS) {
    try {
      const data = await fetchStationData(config.id);
      if (!data || data.dataLines.length === 0) continue;

      const row = parseLine(data.headers, data.dataLines[0]);
      if (!row) continue;

      const timestamp = parseTimestamp(row);
      const station = rowToStation(row, config, timestamp);
      if (station) stations.push(station);
    } catch (e) {
      console.warn(`NDBC error for ${config.id}:`, e.message);
    }
  }

  if (stations.length > 0) {
    stationsCache = { data: stations, timestamp: now };
  }

  return { stations, cached: false };
}

async function getHistory(stationId, hours) {
  const config = STATIONS.find(s => s.id === stationId);
  if (!config) return [];

  const data = await fetchStationData(stationId);
  if (!data || data.dataLines.length === 0) return [];

  const cutoff = Date.now() - hours * 60 * 60 * 1000;
  const observations = [];

  for (const line of data.dataLines) {
    const row = parseLine(data.headers, line);
    if (!row) continue;

    const timestamp = parseTimestamp(row);
    if (!timestamp || timestamp.getTime() < cutoff) break; // Data is newest-first

    const wspd = row['WSPD'] ? parseFloat(row['WSPD']) : null;
    if (wspd === null) continue;

    const gst = row['GST'] ? parseFloat(row['GST']) : null;
    const wdir = row['WDIR'] ? parseFloat(row['WDIR']) : null;

    observations.push({
      ts: timestamp.toISOString(),
      wind: Math.round(wspd * MS_TO_KNOTS * 10) / 10,
      gust: gst !== null ? Math.round(gst * MS_TO_KNOTS * 10) / 10 : null,
      dir: wdir || 0,
      temperature: row['ATMP'] ? parseFloat(row['ATMP']) : null,
      waterTemp: row['WTMP'] ? parseFloat(row['WTMP']) : null,
      pressure: row['PRES'] ? parseFloat(row['PRES']) : null,
    });
  }

  return observations.reverse(); // Return chronological order
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');

  const { history, hours = '48' } = req.query;

  try {
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 48, 120);
      const observations = await getHistory(history, hoursNum);
      return res.json({
        stationId: history,
        source: 'ndbc',
        observations,
        count: observations.length,
        hours: hoursNum,
      });
    }

    const { stations, cached } = await getLatestStations();
    return res.json({
      stations,
      cached,
      count: stations.length,
      timestamp: new Date().toISOString(),
    });
  } catch (e) {
    console.error('NDBC error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message,
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch NDBC data',
      details: e.message,
    });
  }
}
