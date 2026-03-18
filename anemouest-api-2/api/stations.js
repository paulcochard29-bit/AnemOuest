// Météo France Stations - Nord & Méditerranée
// Second API project with separate MF API key
// No duplicates with API-1 (which covers Atlantic coast: depts 29,22,56,35,44,85,17,33,40,64)

const MF_API_BASE = 'https://public-api.meteofrance.fr/public/DPPaquetObs/v1';
const MF_API_KEY = process.env.METEOFRANCE_API_KEY;

const STATION_IDS = [
  // === CÔTE NORD (Manche / Mer du Nord) ===
  // Nord (59)
  "59183001",
  // Pas-de-Calais (62)
  "62160001", "62054001", "62826001",
  // Somme (80)
  "80001001", "80182003",
  // Seine-Maritime (76)
  "76217001", "76552001", "76259001",
  // Calvados (14)
  "14137001", "14239001", "14047002", "14515001", "14066001",
  // Manche (50)
  "50129001", "50218001", "50147001", "50020001", "50031001",
  "50196001", "50215002", "50509002", "50562001", "50277001",

  // === CÔTE MÉDITERRANÉE ===
  // Pyrénées-Orientales (66)
  "66136001",
  // Aude (11)
  "11262005", "11202001",
  // Hérault (34)
  "34154001", "34301002",
  // Gard (30)
  "30003001", "30133005",
  // Bouches-du-Rhône (13)
  "13054001", "13055001", "13028001", "13047001", "13056002",
  // Var (83)
  "83137001", "83069001", "83061001", "83153001", "83069002", "83069003",
  "83101001", "83118002",
  // Alpes-Maritimes (06)
  "06088001", "06004002", "06029001",

  // === CORSE ===
  "20004002", "20160001", "20041001", "20272001", "20004003",
  "20247001", "20281001"
];

const STATION_NAMES = {
  // Nord
  "59183001": "Dunkerque",
  // Pas-de-Calais
  "62160001": "Boulogne-sur-Mer",
  "62054001": "Cap-Gris-Nez",
  "62826001": "Le Touquet",
  // Somme
  "80001001": "Abbeville",
  "80182003": "Cayeux-sur-Mer",
  // Seine-Maritime
  "76217001": "Dieppe",
  "76552001": "Cap de la Hève",
  "76259001": "Fécamp",
  // Calvados
  "14137001": "Caen-Carpiquet",
  "14239001": "Douvres-la-Délivrande",
  "14047002": "Bayeux",
  "14515001": "Port-en-Bessin",
  "14066001": "Bernières",
  // Manche
  "50129001": "Cherbourg",
  "50218001": "Granville",
  "50147001": "Coutances",
  "50020001": "Pointe de la Hague",
  "50031001": "Barneville-Carteret",
  "50196001": "Gatteville",
  "50215002": "Gouville",
  "50509002": "Sainte-Marie-du-Mont",
  "50562001": "Saint-Vaast-la-Hougue",
  "50277001": "Longueville",
  // Pyrénées-Orientales
  "66136001": "Perpignan",
  // Aude
  "11262005": "Narbonne",
  "11202001": "Leucate",
  // Hérault
  "34154001": "Montpellier",
  "34301002": "Sète",
  // Gard
  "30003001": "Aigues-Mortes",
  "30133005": "L'Espiguette",
  // Bouches-du-Rhône
  "13054001": "Marignane (Marseille)",
  "13055001": "Marseille",
  "13028001": "Cassis",
  "13047001": "Istres",
  "13056002": "Cap Couronne",
  // Var
  "83137001": "Toulon",
  "83069001": "Hyères",
  "83061001": "Fréjus",
  "83153001": "Le Castellet",
  "83069002": "Bormes-les-Mimosas",
  "83069003": "Cogolin",
  "83101001": "Cap Camarat",
  "83118002": "Le Dramont",
  // Alpes-Maritimes
  "06088001": "Nice",
  "06004002": "Antibes (Cap d'Antibes)",
  "06029001": "Cannes",
  // Corse
  "20004002": "Ajaccio",
  "20160001": "Bastia",
  "20041001": "Figari",
  "20272001": "Solenzara",
  "20004003": "Ajaccio (Campo dell'Oro)",
  "20247001": "La Chiappa",
  "20281001": "Cap Sagro"
};

const MS_TO_KNOTS = 1.94384;

let cache = { data: null, timestamp: 0 };
const CACHE_DURATION = 60 * 1000; // 1 min — 54 stations = ~54 req/min, well within 100 req/min budget

// Fetch with date range (last 1 hour) to get truly recent data
async function fetchStation(stationId) {
  try {
    const endDate = new Date();
    const startDate = new Date(Date.now() - 60 * 60 * 1000);

    const url = `${MF_API_BASE}/paquet/infrahoraire-6m?id_station=${stationId}&format=json` +
      `&date_deb_periode=${encodeURIComponent(startDate.toISOString())}` +
      `&date_fin_periode=${encodeURIComponent(endDate.toISOString())}`;

    const res = await fetch(url, { headers: { 'apikey': MF_API_KEY } });

    if (!res.ok) {
      // Fallback: try without date range
      return await fetchStationSimple(stationId);
    }

    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) {
      return await fetchStationSimple(stationId);
    }

    // Get the most recent observation
    const sorted = data.sort((a, b) =>
      new Date(b.validity_time).getTime() - new Date(a.validity_time).getTime()
    );
    const d = sorted[0];

    return buildStation(stationId, d);
  } catch (e) {
    return null;
  }
}

// Fallback: simple fetch without date range
async function fetchStationSimple(stationId) {
  try {
    const res = await fetch(
      `${MF_API_BASE}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`,
      { headers: { 'apikey': MF_API_KEY } }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data || !data.length) return null;
    const d = data[0];
    return buildStation(stationId, d);
  } catch (e) {
    return null;
  }
}

function buildStation(stationId, d) {
  return {
    id: stationId,
    stableId: `meteofrance_${stationId}`,
    name: STATION_NAMES[stationId] || stationId,
    lat: d.lat,
    lon: d.lon,
    wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
    gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
    dir: d.dd || 0,
    isOnline: (Date.now() - new Date(d.validity_time).getTime()) < 20 * 60 * 1000,
    source: 'meteofrance',
    ts: d.validity_time,
    temperature: d.t != null ? Math.round((d.t - 273.15) * 10) / 10 : null,
    pressure: d.pmer != null ? Math.round(d.pmer / 10) / 10 : null,
    humidity: d.u != null ? Math.round(d.u) : null,
  };
}

async function fetchAll() {
  const results = [];
  for (let i = 0; i < STATION_IDS.length; i += 15) {
    const batch = STATION_IDS.slice(i, i + 15);
    const batchResults = await Promise.all(batch.map(fetchStation));
    results.push(...batchResults.filter(Boolean));
    if (i + 15 < STATION_IDS.length) await new Promise(r => setTimeout(r, 50));
  }
  return results;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=15');

  const now = Date.now();

  if (cache.data && (now - cache.timestamp) < CACHE_DURATION) {
    return res.json({ stations: cache.data, cached: true, age: Math.round((now - cache.timestamp) / 1000) });
  }

  try {
    const stations = await fetchAll();
    cache = { data: stations, timestamp: now };
    return res.json({ stations, cached: false, count: stations.length });
  } catch (e) {
    if (cache.data) {
      return res.json({ stations: cache.data, cached: true, stale: true });
    }
    return res.status(500).json({ error: 'Failed' });
  }
}
