const MF_API_BASE = 'https://public-api.meteofrance.fr/public/DPPaquetObs/v1';
const MF_API_KEY = process.env.METEOFRANCE_API_KEY;

const STATION_IDS = [
  "29021001", "29022001", "29058003", "29075001", "29082001",
  "29120001", "29155005", "29158001", "29168001", "29178001",
  "29190001", "29214001", "29216001", "29293001",
  "22016001", "22113006", "22168001", "22282001", "22372001",
  "56007001", "56009001", "56069001", "56185001", "56186003",
  "56240003", "56243001", "35228001",
  "44020001", "44103001", "44131002", "44184001",
  "85060002", "85104001", "85113001", "85163001", "85172001", "85191003",
  "17093002", "17300009", "17306004", "17318001", "17323001",
  "33236002", "33529001", "40046001", "40065002",
  "64024001", "64189001"
];

const STATION_NAMES = {
  "29021001": "Brignogan", "29022001": "Camaret", "29058003": "Beg Meil",
  "29075001": "Brest", "29082001": "Île de Batz", "29120001": "Lanvéoc",
  "29155005": "Ouessant", "29158001": "Penmarch", "29168001": "Pointe du Raz",
  "29178001": "Ploudalmézeau", "29190001": "Plougonvelin", "29214001": "Plovan",
  "29216001": "Quimper", "29293001": "Trégunc",
  "22016001": "Île-de-Bréhat", "22113006": "Lannion", "22168001": "Ploumanac'h",
  "22282001": "Saint-Cast", "22372001": "Saint-Brieuc",
  "56007001": "Auray", "56009001": "Belle-Île", "56069001": "Groix",
  "56185001": "Lorient", "56186003": "Quiberon", "56240003": "Sarzeau",
  "56243001": "Vannes", "35228001": "Dinard",
  "44020001": "Nantes", "44103001": "Saint-Nazaire", "44131002": "Pornic",
  "44184001": "Pointe de Chemoulin",
  "85060002": "Château-d'Olonne", "85104001": "Grues", "85113001": "Île d'Yeu",
  "85163001": "Noirmoutier", "85172001": "Le Perrier", "85191003": "La Roche-sur-Yon",
  "17093002": "Château d'Oléron", "17300009": "La Rochelle", "17306004": "Royan",
  "17318001": "Saint-Clément", "17323001": "Chassiron",
  "33236002": "Cap Ferret", "33529001": "Cazaux",
  "40046001": "Biscarrosse", "40065002": "Capbreton",
  "64024001": "Biarritz", "64189001": "Socoa"
};

const MS_TO_KNOTS = 1.94384;

let cache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000; // 5 min — all 47 stations fetched in parallel, well within 100 req/min budget

async function fetchStation(stationId) {
  try {
    // Use date range (last 1 hour) to get recent data reliably
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

    // Get most recent observation
    const sorted = data.sort((a, b) =>
      new Date(b.validity_time).getTime() - new Date(a.validity_time).getTime()
    );
    const d = sorted[0];
    return buildStation(stationId, d);
  } catch (e) {
    return null;
  }
}

async function fetchStationSimple(stationId) {
  try {
    const res = await fetch(
      `${MF_API_BASE}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`,
      { headers: { 'apikey': MF_API_KEY } }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data || !data.length) return null;
    return buildStation(stationId, data[0]);
  } catch (e) {
    return null;
  }
}

function buildStation(stationId, d) {
  return {
    id: stationId,
    name: STATION_NAMES[stationId] || stationId,
    lat: d.lat,
    lon: d.lon,
    wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
    gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
    dir: d.dd || 0,
    ts: d.validity_time,
    temperature: d.t != null ? Math.round((d.t - 273.15) * 10) / 10 : null,
    pressure: d.pmer != null ? Math.round(d.pmer / 10) / 10 : null,
    humidity: d.u != null ? Math.round(d.u) : null,
  };
}

async function fetchAll() {
  // 100 req/min budget — 47 stations fit in a single parallel batch
  const batchResults = await Promise.all(STATION_IDS.map(fetchStation));
  return batchResults.filter(Boolean);
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=300');

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
