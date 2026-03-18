// Météo France API - Nord & Méditerranée stations
// Second API project with separate MF API key
//
// Usage:
//   GET /api/meteofrance              - Returns all North+Med stations (current data)
//   GET /api/meteofrance?history=ID   - Returns history for station ID
//   GET /api/meteofrance?hours=6      - Filter history by hours (default 6)

const MF_API = 'https://public-api.meteofrance.fr/public/DPPaquetObs/v1';
const API_KEY = process.env.METEOFRANCE_API_KEY;

const MS_TO_KNOTS = 1.94384;

// Nord & Méditerranée coastal stations (no overlap with API-1 Atlantic stations)
const STATIONS = {
  // === CÔTE NORD ===
  // Nord (59)
  "59183001": "Dunkerque",
  // Pas-de-Calais (62)
  "62160001": "Boulogne-sur-Mer",
  "62054001": "Cap-Gris-Nez",
  "62826001": "Le Touquet",
  // Somme (80)
  "80001001": "Abbeville",
  "80182003": "Cayeux-sur-Mer",
  // Seine-Maritime (76)
  "76217001": "Dieppe",
  "76552001": "Cap de la Hève",
  "76259001": "Fécamp",
  // Calvados (14)
  "14137001": "Caen-Carpiquet",
  "14515001": "Port-en-Bessin",
  "14066001": "Bernières",
  // Manche (50)
  "50129001": "Cherbourg",
  "50218001": "Granville",
  "50020001": "Pointe de la Hague",
  "50031001": "Barneville-Carteret",
  "50196001": "Gatteville",
  "50215002": "Gouville",
  "50509002": "Sainte-Marie-du-Mont",
  "50562001": "Saint-Vaast-la-Hougue",
  "50277001": "Longueville",

  // === CÔTE MÉDITERRANÉE ===
  // Pyrénées-Orientales (66)
  "66136001": "Perpignan",
  // Aude (11)
  "11262005": "Narbonne",
  "11202001": "Leucate",
  // Hérault (34)
  "34154001": "Montpellier",
  "34301002": "Sète",
  // Gard (30)
  "30003001": "Aigues-Mortes",
  "30133005": "L'Espiguette",
  // Bouches-du-Rhône (13)
  "13054001": "Marignane (Marseille)",
  "13055001": "Marseille",
  "13056002": "Cap Couronne",
  // Var (83)
  "83137001": "Toulon",
  "83069001": "Hyères",
  "83101001": "Cap Camarat",
  "83118002": "Le Dramont",
  // Alpes-Maritimes (06)
  "06088001": "Nice",
  "06004002": "Antibes (Cap d'Antibes)",

  // === CORSE ===
  "20004002": "Ajaccio",
  "20160001": "Bastia",
  "20247001": "La Chiappa",
  "20281001": "Cap Sagro"
};

let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000;

async function fetchHistoryWithDateRange(stationId, hours) {
  const endDate = new Date();
  const startDate = new Date(Date.now() - hours * 60 * 60 * 1000);

  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json` +
    `&date_deb_periode=${encodeURIComponent(startDate.toISOString())}` +
    `&date_fin_periode=${encodeURIComponent(endDate.toISOString())}`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) return null;

  const data = await response.json();
  if (!Array.isArray(data) || data.length === 0) return null;

  return data.map(d => ({
    ts: d.validity_time,
    wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
    gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
    dir: d.dd || 0
  })).sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());
}

async function fetchHistorySimple(stationId, hours) {
  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);

  const data = await response.json();
  if (!Array.isArray(data)) return [];

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

async function fetchStationData(stationId) {
  const endDate = new Date();
  const startDate = new Date(Date.now() - 60 * 60 * 1000);

  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json` +
    `&date_deb_periode=${encodeURIComponent(startDate.toISOString())}` +
    `&date_fin_periode=${encodeURIComponent(endDate.toISOString())}`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) throw new Error(`MF API error: ${response.status}`);

  return response.json();
}

async function fetchAllStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const stations = [];
  const stationIds = Object.keys(STATIONS);
  const batchSize = 5;

  for (let i = 0; i < stationIds.length; i += batchSize) {
    const batch = stationIds.slice(i, i + batchSize);

    const results = await Promise.allSettled(
      batch.map(async (stationId) => {
        try {
          const data = await fetchStationData(stationId);
          if (!Array.isArray(data) || data.length === 0) return null;

          // Sort by time descending to get most recent observation
          const sorted = data.sort((a, b) =>
            new Date(b.validity_time).getTime() - new Date(a.validity_time).getTime()
          );
          const latest = sorted[0];
          const lastUpdate = new Date(latest.validity_time);
          const isOnline = (now - lastUpdate.getTime()) < 20 * 60 * 1000;

          return {
            id: stationId,
            stableId: `meteofrance_${stationId}`,
            name: STATIONS[stationId] || `Station ${stationId}`,
            lat: latest.lat,
            lon: latest.lon,
            wind: Math.round((latest.ff || 0) * MS_TO_KNOTS * 10) / 10,
            gust: Math.round((latest.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
            direction: latest.dd || 0,
            isOnline,
            source: 'meteofrance',
            ts: latest.validity_time
          };
        } catch (err) {
          console.error(`MF fetch error for ${stationId}:`, err.message);
          return null;
        }
      })
    );

    for (const result of results) {
      if (result.status === 'fulfilled' && result.value) {
        stations.push(result.value);
      }
    }

    if (i + batchSize < stationIds.length) {
      await new Promise(r => setTimeout(r, 200));
    }
  }

  stationsCache = { data: stations, timestamp: now };
  return { stations, cached: false };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=30');

  const { history, hours = '6' } = req.query;

  try {
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 6, 72);
      const stationId = history.replace('meteofrance_', '');

      let observations = await fetchHistoryWithDateRange(stationId, hoursNum);

      if (!observations || observations.length === 0) {
        observations = await fetchHistorySimple(stationId, hoursNum);
      }

      return res.json({
        stationId: history,
        name: STATIONS[stationId] || stationId,
        source: 'meteofrance',
        observations: observations || [],
        count: observations?.length || 0,
        hours: hoursNum
      });
    }

    const { stations, cached } = await fetchAllStations();

    return res.json({
      stations,
      cached,
      count: stations.length,
      timestamp: new Date().toISOString()
    });

  } catch (e) {
    console.error('MeteoFrance error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch MeteoFrance data',
      details: e.message
    });
  }
}
