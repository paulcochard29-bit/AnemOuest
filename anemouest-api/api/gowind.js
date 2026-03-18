// GoWind API - Combined stations and history endpoint
// Fetches Holfuy & Windguru from GoWind
// Uses direct Holfuy scraping for history (like iOS app)
//
// Usage:
//   GET /api/gowind              - Returns all stations (current data)
//   GET /api/gowind?history=ID   - Returns history for station ID (scrapes Holfuy)
//   GET /api/gowind?hours=6      - Filter history by hours (default 6)

const GOWIND_API = 'https://gowind.fr/php/anemo/carte_des_vents.json';
const HOLFUY_GRAPH_BASE = 'https://holfuy.com/dynamic/graphs/tdarr';

// In-memory cache for current stations
let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

// France bounding box
function isInFrance(lat, lon) {
  return lat >= 41.3 && lat <= 51.2 && lon >= -5.5 && lon <= 9.7;
}

// Parse date from GoWind format: "07/01/2026 14:30:00" (French time CET/CEST)
function parseGoWindDate(dateStr) {
  if (!dateStr) return null;
  const parts = dateStr.split(' ');
  if (parts.length !== 2) return null;
  const [datePart, timePart] = parts;
  const dateParts = datePart.split('/');
  if (dateParts.length !== 3) return null;
  const [day, month, year] = dateParts;
  const monthNum = parseInt(month);
  const isDST = monthNum >= 4 && monthNum <= 9;
  const offset = isDST ? '+02:00' : '+01:00';
  const isoStr = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}T${timePart}${offset}`;
  const date = new Date(isoStr);
  return isNaN(date.getTime()) ? null : date;
}

// Parse Holfuy date format: "2026/01/13 14:30:00" (French time CET/CEST)
function parseHolfuyDate(dateStr) {
  if (!dateStr) return null;
  // Format: "YYYY/MM/DD HH:mm:ss"
  const [datePart, timePart] = dateStr.split(' ');
  if (!datePart || !timePart) return null;

  const [year, month, day] = datePart.split('/');
  const monthNum = parseInt(month);
  const isDST = monthNum >= 4 && monthNum <= 9;
  const offset = isDST ? '+02:00' : '+01:00';
  const isoStr = `${year}-${month}-${day}T${timePart}${offset}`;
  const date = new Date(isoStr);
  return isNaN(date.getTime()) ? null : date;
}

function parseStation(station, source) {
  const id = String(station.id || '');
  const lat = parseFloat(station.lat) || 0;
  const lon = parseFloat(station.lon) || 0;

  if (!id || lat === 0 || lon === 0 || !isInFrance(lat, lon)) {
    return null;
  }

  const wind = parseFloat(station.vmoy) || 0;
  const gust = parseFloat(station.vmax) || 0;

  let direction = parseFloat(station.ordegre) || 0;
  if (direction < 0 || direction > 360) {
    direction = 0;
  }

  const lastUpdate = parseGoWindDate(station.now);
  const isOnline = station.mode !== 'OFF' && lastUpdate && (Date.now() - lastUpdate.getTime() < 60 * 60 * 1000);

  return {
    id,
    stableId: `${source}_${id}`,
    name: station.nom || `${source} ${id}`,
    lat,
    lon,
    wind,
    gust,
    direction,
    isOnline,
    source,
    ts: lastUpdate ? lastUpdate.toISOString() : null
  };
}

// Fetch history from Holfuy by scraping their JS graph data
async function fetchHolfuyHistory(stationId, hours) {
  // Extract numeric ID
  const numericId = stationId.replace(/^holfuy_/, '');

  const url = `${HOLFUY_GRAPH_BASE}${numericId}.js`;

  const response = await fetch(url, {
    headers: { 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`Holfuy fetch error: ${response.status}`);
  }

  const jsContent = await response.text();

  // Parse JavaScript arrays
  const timestamps = parseJSStringArray(jsContent, 'unt');
  const speeds = parseJSNumberArray(jsContent, 'gd_speed');
  const gusts = parseJSNumberArray(jsContent, 'gd_gust');
  const directions = parseJSNumberArray(jsContent, 'gd_direction');

  if (timestamps.length === 0) {
    return [];
  }

  // Build observations
  const observations = [];
  const cutoffDate = Date.now() - (hours * 60 * 60 * 1000);
  const kmhToKnots = 0.539957;

  for (let i = 0; i < timestamps.length; i++) {
    const date = parseHolfuyDate(timestamps[i]);
    if (!date) continue;
    if (date.getTime() < cutoffDate) continue;

    const speed = i < speeds.length ? speeds[i] : 0;
    const gust = i < gusts.length ? gusts[i] : 0;
    const direction = i < directions.length ? directions[i] : 0;

    observations.push({
      ts: date.toISOString(),
      wind: Math.round(speed * kmhToKnots * 10) / 10,
      gust: Math.round(gust * kmhToKnots * 10) / 10,
      dir: direction
    });
  }

  return observations.sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());
}

// Parse JavaScript string array: var name = ['val1','val2',...]
function parseJSStringArray(js, variableName) {
  const regex = new RegExp(`var ${variableName}\\s*=\\s*\\[([^\\]]+)\\]`);
  const match = js.match(regex);
  if (!match) return [];

  const values = [];
  const content = match[1];
  let current = '';
  let inString = false;

  for (const char of content) {
    if (char === "'") {
      if (inString) {
        values.push(current);
        current = '';
      }
      inString = !inString;
    } else if (inString) {
      current += char;
    }
  }

  return values;
}

// Parse JavaScript number array: var name = [1,2,3,...]
function parseJSNumberArray(js, variableName) {
  const regex = new RegExp(`var ${variableName}\\s*=\\s*\\[([^\\]]+)\\]`);
  const match = js.match(regex);
  if (!match) return [];

  return match[1]
    .split(',')
    .map(s => parseFloat(s.trim()))
    .filter(n => !isNaN(n));
}

async function fetchGoWind() {
  const response = await fetch(GOWIND_API, {
    headers: { 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`GoWind API error: ${response.status}`);
  }

  return response.json();
}

async function refreshStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const data = await fetchGoWind();
  const stations = [];

  if (data.holfuy && Array.isArray(data.holfuy)) {
    for (const s of data.holfuy) {
      const station = parseStation(s, 'holfuy');
      if (station) stations.push(station);
    }
  }

  if (data.windguru && Array.isArray(data.windguru)) {
    for (const s of data.windguru) {
      const station = parseStation(s, 'windguru');
      if (station) stations.push(station);
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
    // If history requested, fetch from Holfuy direct
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 6, 168); // Max 7 days

      // Check if it's a Holfuy station (only Holfuy has direct history)
      const isHolfuy = history.startsWith('holfuy_') || !history.startsWith('windguru_');

      if (isHolfuy) {
        try {
          const observations = await fetchHolfuyHistory(history, hoursNum);

          return res.json({
            stationId: history,
            source: 'holfuy',
            observations,
            count: observations.length,
            hours: hoursNum
          });
        } catch (historyError) {
          return res.json({
            stationId: history,
            observations: [],
            error: historyError.message,
            hours: hoursNum
          });
        }
      } else {
        // Windguru doesn't have direct history API
        return res.json({
          stationId: history,
          observations: [],
          error: 'Windguru history not available',
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
    console.error('GoWind error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch GoWind data',
      details: e.message
    });
  }
}
