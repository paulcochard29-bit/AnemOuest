// Météo France API - Official weather stations
// Uses direct API with date range for history (like iOS app)
//
// Usage:
//   GET /api/meteofrance              - Returns all coastal stations (current data)
//   GET /api/meteofrance?history=ID   - Returns history for station ID
//   GET /api/meteofrance?hours=6      - Filter history by hours (default 6)

const MF_API = 'https://public-api.meteofrance.fr/public/DPPaquetObs/v1';
const API_KEY = process.env.METEOFRANCE_API_KEY || 'eyJ4NXQiOiJZV0kxTTJZNE1qWTNOemsyTkRZeU5XTTRPV014TXpjek1UVmhNbU14T1RSa09ETXlOVEE0Tnc9PSIsImtpZCI6ImdhdGV3YXlfY2VydGlmaWNhdGVfYWxpYXMiLCJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJQYXVsMjlAY2FyYm9uLnN1cGVyIiwiYXBwbGljYXRpb24iOnsib3duZXIiOiJQYXVsMjkiLCJ0aWVyUXVvdGFUeXBlIjpudWxsLCJ0aWVyIjoiVW5saW1pdGVkIiwibmFtZSI6IkRlZmF1bHRBcHBsaWNhdGlvbiIsImlkIjozNTY0MiwidXVpZCI6IjcyZGQ5NmM0LTdlZWUtNDVmZS04ZWJkLTA0ZDFlZjBmYzE0NCJ9LCJpc3MiOiJodHRwczpcL1wvcG9ydGFpbC1hcGkubWV0ZW9mcmFuY2UuZnI6NDQzXC9vYXV0aDJcL3Rva2VuIiwidGllckluZm8iOnsiNTBQZXJNaW4iOnsidGllclF1b3RhVHlwZSI6InJlcXVlc3RDb3VudCIsImdyYXBoUUxNYXhDb21wbGV4aXR5IjowLCJncmFwaFFMTWF4RGVwdGgiOjAsInN0b3BPblF1b3RhUmVhY2giOnRydWUsInNwaWtlQXJyZXN0TGltaXQiOjAsInNwaWtlQXJyZXN0VW5pdCI6InNlYyJ9fSwia2V5dHlwZSI6IlBST0RVQ1RJT04iLCJzdWJzY3JpYmVkQVBJcyI6W3sic3Vic2NyaWJlclRlbmFudERvbWFpbiI6ImNhcmJvbi5zdXBlciIsIm5hbWUiOiJEb25uZWVzUHVibGlxdWVzUGFxdWV0T2JzZXJ2YXRpb24iLCJjb250ZXh0IjoiXC9wdWJsaWNcL0RQUGFxdWV0T2JzXC92MSIsInB1Ymxpc2hlciI6ImJhc3RpZW5nIiwidmVyc2lvbiI6InYxIiwic3Vic2NyaXB0aW9uVGllciI6IjUwUGVyTWluIn1dLCJleHAiOjE3OTkyMjg3MTEsInRva2VuX3R5cGUiOiJhcGlLZXkiLCJpYXQiOjE3Njc2OTI3MTEsImp0aSI6IjY4ZmM3ZTllLThjMmMtNGMzNy04ZjAzLTFhNGYzMzEyOWIxYSJ9.ID7FoyA0NGuyaSK929PLHAMnqB_o1k-iqUp3VV7ewQLhjVxNTz61k4AASRayUKg7e0pEORxdBMKeQoFxMVaMvuuLwnafETRoNpYrrcjdnrDe1WA9jASRXG_dHmXLjLCmhpY0ezq50JKcEHuGKRlr16bZIsE6L_sdEIbJNASlQv-WjIyQ8x_Qnn661b38O-f2FLoddW9QGt9xhDhxuLKHWJqvLLB0_QoyTGwwv0rFsSy5PgBaDCD-7dmsn9CchPHkc-OPv4GIofsMt-4GmDGGfOnSNrn-VurkTVfS3Wecf5oOshgyRpiU0h9i_QpK3lpvRQCYDLozP-NluYBjcFkKxg==';

const MS_TO_KNOTS = 1.94384;

// Coastal stations with names
const STATIONS = {
  // Finistère (29)
  "29021001": "Brignogan", "29022001": "Camaret", "29058003": "Beg Meil",
  "29075001": "Brest", "29082001": "Ile de Batz", "29120001": "Lanveoc",
  "29155005": "Ouessant", "29158001": "Penmarch", "29168001": "Pointe du Raz",
  "29178001": "Ploudalmezeau", "29190001": "Plougonvelin", "29214001": "Plovan",
  "29216001": "Quimper", "29293001": "Tregunc",
  // Côtes d'Armor (22)
  "22016001": "Ile-de-Brehat", "22113006": "Lannion", "22168001": "Ploumanac'h",
  "22282001": "Saint-Cast", "22372001": "Saint-Brieuc",
  // Morbihan (56)
  "56007001": "Auray", "56009001": "Belle-Ile", "56069001": "Groix",
  "56185001": "Lorient", "56186003": "Quiberon", "56240003": "Sarzeau", "56243001": "Vannes",
  // Ille-et-Vilaine (35)
  "35228001": "Dinard",
  // Loire-Atlantique (44)
  "44020001": "Nantes", "44103001": "Saint-Nazaire", "44131002": "Pornic", "44184001": "Pointe de Chemoulin",
  // Vendée (85)
  "85060002": "Chateau-d'Olonne", "85104001": "Grues", "85113001": "Ile d'Yeu",
  "85163001": "Noirmoutier", "85172001": "Le Perrier", "85191003": "La Roche-sur-Yon",
  // Charente-Maritime (17)
  "17093002": "Chateau d'Oleron", "17300009": "La Rochelle", "17306004": "Royan",
  "17318001": "Saint-Clement", "17323001": "Chassiron",
  // Gironde (33)
  "33236002": "Cap Ferret", "33529001": "Cazaux",
  // Landes (40)
  "40046001": "Biscarrosse", "40065002": "Capbreton",
  // Pyrénées-Atlantiques (64)
  "64024001": "Biarritz", "64189001": "Socoa"
};

let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000;

// Fetch history with date range (like iOS app)
async function fetchHistoryWithDateRange(stationId, hours) {
  const endDate = new Date();
  const startDate = new Date(Date.now() - hours * 60 * 60 * 1000);

  const startStr = startDate.toISOString();
  const endStr = endDate.toISOString();

  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json` +
    `&date_deb_periode=${encodeURIComponent(startStr)}` +
    `&date_fin_periode=${encodeURIComponent(endStr)}`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json();
  if (!Array.isArray(data) || data.length === 0) {
    return null;
  }

  const cutoff = Date.now() - (hours * 60 * 60 * 1000);
  return data.map(d => ({
    ts: d.validity_time,
    wind: Math.round((d.ff || 0) * MS_TO_KNOTS * 10) / 10,
    gust: Math.round((d.fxi10 || 0) * MS_TO_KNOTS * 10) / 10,
    dir: d.dd || 0
  }))
    .filter(o => new Date(o.ts).getTime() >= cutoff)
    .sort((a, b) => new Date(a.ts).getTime() - new Date(b.ts).getTime());
}

// Fallback: simple fetch without date range
async function fetchHistorySimple(stationId, hours) {
  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

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
  const url = `${MF_API}/paquet/infrahoraire-6m?id_station=${stationId}&format=json`;

  const response = await fetch(url, {
    headers: { 'apikey': API_KEY, 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`MF API error: ${response.status}`);
  }

  return response.json();
}

async function fetchAllStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const stations = [];
  const stationIds = Object.keys(STATIONS);

  // 100 req/min budget — 44 stations fit in a single parallel batch
  const results = await Promise.allSettled(
    stationIds.map(async (stationId) => {
      try {
        const data = await fetchStationData(stationId);
        if (!Array.isArray(data) || data.length === 0) return null;

        const latest = data.reduce((best, d) =>
          !best || new Date(d.validity_time) > new Date(best.validity_time) ? d : best
        , null);
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
          ts: latest.validity_time,
          temperature: latest.t != null ? Math.round((latest.t - 273.15) * 10) / 10 : null,
          pressure: latest.pmer != null ? Math.round(latest.pmer / 10) / 10 : null,
          humidity: latest.u != null ? Math.round(latest.u) : null,
        };
      } catch (err) {
        return null;
      }
    })
  );

  for (const result of results) {
    if (result.status === 'fulfilled' && result.value) {
      stations.push(result.value);
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
    // If history requested, fetch directly from MF API with date range
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 6, 168);
      const stationId = history.replace('meteofrance_', '');

      // Try with date range first
      let observations = await fetchHistoryWithDateRange(stationId, hoursNum);

      // Fallback to simple call
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

    // Return all stations
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
