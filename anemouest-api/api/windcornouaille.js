// WindCornouaille API - Fetches from backend.windmorbihan.com
//
// Usage:
//   GET /api/windcornouaille              - Returns all stations (current data)
//   GET /api/windcornouaille?history=ID   - Returns history for station ID
//   GET /api/windcornouaille?hours=6      - Filter history by hours (default 24)

const WC_CHART = 'https://backend.windmorbihan.com/observations/chart.json';
const WC_HISTORY = 'https://backend.windmorbihan.com/observations/history.json';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept': 'application/json',
  'Referer': 'https://windmorbihan.com/'
};

// WindCornouaille sensors — GPS from backend.windmorbihan.com/capteurs/list.json
const SENSORS = [
  { id: "1", name: "École de voile Océane", lat: 47.567, lon: -3.004 },
  { id: "2", name: "Sémaphore St Gildas", lat: 47.1337, lon: -2.24585 },
  { id: "3", name: "Noirmoutier", lat: 47.02458, lon: -2.3067 },
  { id: "4", name: "Île Dumet", lat: 47.411505, lon: -2.620043 },
  { id: "5", name: "Phare de la Teignouse", lat: 47.457333, lon: -3.0458 },
  { id: "6", name: "Glénan", lat: 47.71791, lon: -4.0088 },
  { id: "7", name: "Pointe de Trévignon", lat: 47.79325, lon: -3.85535 },
  { id: "8", name: "Pornichet", lat: 47.258259, lon: -2.35234 },
  { id: "9", name: "Île d'Arz", lat: 47.595, lon: -2.81044 },
  { id: "10", name: "Phare de Port Navalo", lat: 47.5478, lon: -2.9183 },
  { id: "73091264", name: "Phare des Cardinaux", lat: 47.321217, lon: -2.834867 },
  { id: "73091265", name: "Isthme", lat: 47.550833, lon: -3.134722 },
  { id: "73091277", name: "Sémaphore d'Etel", lat: 47.646112, lon: -3.214433 },
  { id: "73091286", name: "Feu de Kerroch", lat: 47.699518, lon: -3.46097 },
  { id: "73091300", name: "Pen Men", lat: 47.647736, lon: -3.509733 },
  { id: "73091304", name: "Phare du Four", lat: 47.2978046, lon: -2.63425627 },
  { id: "73091305", name: "Phare du Grand Charpentier", lat: 47.222515, lon: -2.315754 },
  { id: "73091306", name: "Jetée Est St Nazaire", lat: 47.268821, lon: -2.200842 },
  { id: "10438252", name: "ENVSN Quiberon", lat: 47.5095, lon: -3.1194 }
];

// In-memory caches
let stationsCache = { data: null, timestamp: 0 };
let historyCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 2 * 60 * 1000; // 2 minutes
const HISTORY_CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

// --- chart.json (sensors 1-10) ---

async function fetchChartData(sensorId, timeFrame = 60) {
  const url = `${WC_CHART}?sensor=${sensorId}&time_frame=${timeFrame}`;
  const response = await fetch(url, { headers: HEADERS });
  if (!response.ok) throw new Error(`chart.json ${response.status}`);
  return response.json();
}

function parseChartObservations(data) {
  if (!Array.isArray(data)) return [];
  return data.map(obs => {
    const ts = obs.ts ? new Date(obs.ts * 1000).toISOString() : null;
    const wind = obs.ws?.moy?.value ?? obs.ws?.moy ?? null;
    const gust = obs.ws?.max?.value ?? obs.ws?.max ?? null;
    const dir = obs.wd?.moy?.value ?? obs.wd?.moy ?? null;
    return { ts, wind, gust, dir };
  }).filter(o => o.ts && (o.wind !== null || o.gust !== null));
}

// --- history.json (all sensors, ~3MB, ~5 days of 10-min data) ---

async function fetchHistoryJson() {
  const now = Date.now();
  if (historyCache.data && (now - historyCache.timestamp) < HISTORY_CACHE_DURATION) {
    return historyCache.data;
  }

  const response = await fetch(WC_HISTORY, { headers: HEADERS });
  if (!response.ok) throw new Error(`history.json ${response.status}`);
  const json = await response.json();

  // Parse into { sensorId: [{ ts, wind, gust, dir }] }
  const bySensor = {};
  for (const [, sensors] of Object.entries(json)) {
    if (typeof sensors !== 'object' || sensors === null) continue;
    for (const [sid, entry] of Object.entries(sensors)) {
      if (!entry || typeof entry !== 'object') continue;
      const ts = entry.ts;
      const wind = entry.wind_pow_knot ?? null;
      const gust = entry.wind_pow_knot_max ?? null;
      const dir = entry.wind_dir_true ?? null;
      if (wind === null && gust === null) continue;

      if (!bySensor[sid]) bySensor[sid] = [];
      bySensor[sid].push({
        ts: new Date(ts * 1000).toISOString(),
        wind,
        gust,
        dir
      });
    }
  }

  // Sort each sensor's observations by timestamp
  for (const sid of Object.keys(bySensor)) {
    bySensor[sid].sort((a, b) => new Date(a.ts) - new Date(b.ts));
  }

  historyCache = { data: bySensor, timestamp: now };
  return bySensor;
}

// --- Fetch all stations (chart.json + history.json fallback) ---

async function fetchAllStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const stations = [];
  const missingSensorIds = new Set();

  // 1) Try chart.json for all sensors in parallel
  const results = await Promise.allSettled(
    SENSORS.map(async (sensor) => {
      try {
        const data = await fetchChartData(sensor.id, 60);
        const observations = parseChartObservations(data);
        if (observations.length === 0) return null;

        const latest = observations[observations.length - 1];
        const lastUpdate = new Date(latest.ts);
        const isOnline = (now - lastUpdate.getTime()) < 30 * 60 * 1000;

        return {
          id: sensor.id,
          stableId: `windcornouaille_${sensor.id}`,
          name: sensor.name,
          lat: sensor.lat,
          lon: sensor.lon,
          wind: latest.wind ?? 0,
          gust: latest.gust ?? latest.wind ?? 0,
          direction: latest.dir ?? 0,
          isOnline,
          source: 'windcornouaille',
          ts: latest.ts
        };
      } catch (err) {
        return null;
      }
    })
  );

  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    if (result.status === 'fulfilled' && result.value) {
      stations.push(result.value);
    } else {
      missingSensorIds.add(SENSORS[i].id);
    }
  }

  // 2) Fallback to history.json for missing sensors
  if (missingSensorIds.size > 0) {
    try {
      const bySensor = await fetchHistoryJson();

      for (const sensor of SENSORS) {
        if (!missingSensorIds.has(sensor.id)) continue;

        const observations = bySensor[sensor.id];
        if (!observations || observations.length === 0) continue;

        const latest = observations[observations.length - 1];
        const lastUpdate = new Date(latest.ts);
        const isOnline = (now - lastUpdate.getTime()) < 30 * 60 * 1000;

        stations.push({
          id: sensor.id,
          stableId: `windcornouaille_${sensor.id}`,
          name: sensor.name,
          lat: sensor.lat,
          lon: sensor.lon,
          wind: latest.wind ?? 0,
          gust: latest.gust ?? latest.wind ?? 0,
          direction: latest.dir ?? 0,
          isOnline,
          source: 'windcornouaille',
          ts: latest.ts
        });
      }
    } catch (err) {
      console.error('history.json fallback error:', err.message);
    }
  }

  stationsCache = { data: stations, timestamp: now };
  return { stations, cached: false };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=60');

  const { history, hours = '24' } = req.query;

  try {
    if (history) {
      const hoursNum = parseInt(hours) || 24;
      const sensor = SENSORS.find(s => s.id === history || `windcornouaille_${s.id}` === history);
      if (!sensor) {
        return res.status(404).json({ error: 'Station not found', availableStations: SENSORS.map(s => s.id) });
      }

      const rawId = sensor.id;

      // Try chart.json first
      let observations = [];
      try {
        const timeFrame = hoursNum <= 2 ? 60 : hoursNum <= 6 ? 36 : hoursNum <= 24 ? 144 : 288;
        const data = await fetchChartData(rawId, timeFrame);
        observations = parseChartObservations(data);
      } catch (err) {
        // chart.json failed, will try history.json
      }

      // Fallback to history.json if chart.json returned nothing or insufficient span
      let needsHistoryFallback = observations.length === 0;
      if (!needsHistoryFallback && hoursNum > 2 && observations.length >= 2) {
        const first = new Date(observations[0].ts).getTime();
        const last = new Date(observations[observations.length - 1].ts).getTime();
        const spanHours = (last - first) / (3600 * 1000);
        needsHistoryFallback = spanHours < hoursNum * 0.3;
      }

      if (needsHistoryFallback) {
        try {
          const bySensor = await fetchHistoryJson();
          const histObs = bySensor[rawId] || [];
          if (histObs.length > observations.length) {
            observations = histObs;
          }
        } catch (err) {
          console.error(`history.json fallback for ${rawId}:`, err.message);
        }
      }

      // Filter by requested hours
      const cutoff = Date.now() - (hoursNum * 60 * 60 * 1000);
      const filtered = observations.filter(o => new Date(o.ts).getTime() >= cutoff);

      return res.json({
        stationId: history,
        name: sensor.name,
        source: 'windcornouaille',
        observations: filtered,
        count: filtered.length,
        hours: hoursNum
      });
    }

    // Return all stations (current data)
    const { stations, cached } = await fetchAllStations();

    return res.json({
      stations,
      cached,
      count: stations.length,
      timestamp: new Date().toISOString()
    });

  } catch (e) {
    console.error('WindCornouaille error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch WindCornouaille data',
      details: e.message
    });
  }
}
