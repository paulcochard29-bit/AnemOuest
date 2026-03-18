// SHOM Tide API
// Returns tide data (high/low times, heights, coefficients) from SHOM
// Data source: maree.shom.fr (official French hydrographic service)

export const config = {
  maxDuration: 30,
};

// Main tide ports for France (Atlantic coast focus)
// cst = SHOM internal code
const TIDE_PORTS = [
  // Bretagne Nord
  { cst: "ROSCOFF", name: "Roscoff", lat: 48.7267, lon: -3.9833, region: "bretagne" },
  { cst: "MORLAIX", name: "Morlaix", lat: 48.5833, lon: -3.8333, region: "bretagne" },
  { cst: "BREST", name: "Brest", lat: 48.3825, lon: -4.4947, region: "bretagne" },
  { cst: "CAMARET-SUR-MER", name: "Camaret-sur-Mer", lat: 48.2783, lon: -4.5900, region: "bretagne" },
  { cst: "DOUARNENEZ", name: "Douarnenez", lat: 48.1000, lon: -4.3333, region: "bretagne" },
  { cst: "AUDIERNE", name: "Audierne", lat: 48.0216, lon: -4.5376, region: "bretagne" },

  // Bretagne Sud
  { cst: "CONCARNEAU", name: "Concarneau", lat: 47.8733, lon: -3.9067, region: "bretagne" },
  { cst: "LORIENT", name: "Lorient", lat: 47.7333, lon: -3.3667, region: "bretagne" },
  { cst: "PORT-LOUIS", name: "Port-Louis", lat: 47.7083, lon: -3.3583, region: "bretagne" },
  { cst: "PORT-NAVALO", name: "Port-Navalo", lat: 47.5483, lon: -2.9183, region: "bretagne" },
  { cst: "VANNES", name: "Vannes", lat: 47.6500, lon: -2.7500, region: "bretagne" },
  { cst: "LE_CROISIC", name: "Le Croisic", lat: 47.2917, lon: -2.5083, region: "bretagne" },

  // Loire / Vendée
  { cst: "SAINT-NAZAIRE", name: "Saint-Nazaire", lat: 47.2667, lon: -2.2000, region: "loire" },
  { cst: "PORNIC", name: "Pornic", lat: 47.1167, lon: -2.1000, region: "loire" },
  { cst: "ILE_D_YEU_PORT-JOINVILLE", name: "Île d'Yeu", lat: 46.7333, lon: -2.3500, region: "vendee" },
  { cst: "SAINT-GILLES-CROIX-DE-VIE", name: "St-Gilles-Croix-de-Vie", lat: 46.6917, lon: -1.9333, region: "vendee" },
  { cst: "LES_SABLES-D_OLONNE", name: "Les Sables-d'Olonne", lat: 46.4967, lon: -1.7850, region: "vendee" },

  // Charentes
  { cst: "LA_ROCHELLE-PALLICE", name: "La Rochelle", lat: 46.1583, lon: -1.2200, region: "charentes" },
  { cst: "ILE_D_AIX", name: "Île d'Aix", lat: 46.0133, lon: -1.1750, region: "charentes" },
  { cst: "ROCHEFORT", name: "Rochefort", lat: 45.9333, lon: -0.9667, region: "charentes" },
  { cst: "ROYAN", name: "Royan", lat: 45.6167, lon: -1.0333, region: "charentes" },

  // Aquitaine
  { cst: "PORT-BLOC", name: "Port-Bloc", lat: 45.5667, lon: -1.0667, region: "aquitaine" },
  { cst: "ARCACHON_EYRAC", name: "Arcachon", lat: 44.6643, lon: -1.1637, region: "aquitaine" },
  { cst: "CAPBRETON", name: "Capbreton", lat: 43.6537, lon: -1.4372, region: "aquitaine" },
  { cst: "SOCOA", name: "Socoa (St-Jean-de-Luz)", lat: 43.3953, lon: -1.6889, region: "aquitaine" },
  { cst: "HENDAYE", name: "Hendaye", lat: 43.3700, lon: -1.7883, region: "aquitaine" },

  // Normandie
  { cst: "CHERBOURG", name: "Cherbourg", lat: 49.6512, lon: -1.6355, region: "normandie" },
  { cst: "SAINT-MALO", name: "Saint-Malo", lat: 48.6500, lon: -2.0000, region: "bretagne" },
  { cst: "GRANVILLE", name: "Granville", lat: 48.8333, lon: -1.6000, region: "normandie" },
  { cst: "LE_HAVRE", name: "Le Havre", lat: 49.4833, lon: 0.1167, region: "normandie" },
  { cst: "DIEPPE", name: "Dieppe", lat: 49.9333, lon: 1.0833, region: "normandie" },

  // Nord
  { cst: "BOULOGNE-SUR-MER", name: "Boulogne-sur-Mer", lat: 50.7275, lon: 1.5777, region: "nord" },
  { cst: "CALAIS", name: "Calais", lat: 50.9693, lon: 1.8675, region: "nord" },
  { cst: "DUNKERQUE", name: "Dunkerque", lat: 51.0500, lon: 2.3667, region: "nord" },
];

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=7200');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { port, region, date, duration, list } = req.query;

  // Return list of available ports
  if (list === 'true') {
    return res.json({
      ports: TIDE_PORTS,
      count: TIDE_PORTS.length
    });
  }

  // Get tide data for a specific port
  if (port) {
    const portInfo = TIDE_PORTS.find(p =>
      p.cst.toLowerCase() === port.toLowerCase() ||
      p.name.toLowerCase() === port.toLowerCase()
    );

    if (!portInfo) {
      return res.status(404).json({ error: 'Port not found', availablePorts: TIDE_PORTS.map(p => p.cst) });
    }

    const tideData = await fetchTideData(portInfo.cst, date, duration);
    return res.json({
      port: portInfo,
      ...tideData
    });
  }

  // Get all ports for a region
  if (region) {
    const regionPorts = TIDE_PORTS.filter(p => p.region === region.toLowerCase());
    if (regionPorts.length === 0) {
      return res.status(404).json({ error: 'Region not found', availableRegions: [...new Set(TIDE_PORTS.map(p => p.region))] });
    }
    return res.json({
      region,
      ports: regionPorts,
      count: regionPorts.length
    });
  }

  // Default: return all ports grouped by region
  const regions = {};
  for (const port of TIDE_PORTS) {
    if (!regions[port.region]) {
      regions[port.region] = [];
    }
    regions[port.region].push(port);
  }

  return res.json({
    regions,
    totalPorts: TIDE_PORTS.length
  });
}

// SHOM API has a maximum of 11 days per request
const SHOM_MAX_DURATION = 11;

// Fetch tide data from SHOM API (handles periods > 11 days via multiple requests)
async function fetchTideData(cst, date, duration = 7) {
  try {
    const startDate = date ? new Date(date) : new Date();
    const requestedDuration = Math.min(parseInt(duration) || 7, 35); // Max 35 days (about a month)

    // Calculate how many requests we need
    const numRequests = Math.ceil(requestedDuration / SHOM_MAX_DURATION);
    const allData = {};

    // Make parallel requests for each chunk
    const requests = [];
    console.log(`Tide API: Fetching ${requestedDuration} days in ${numRequests} chunks`);

    for (let i = 0; i < numRequests; i++) {
      const chunkDate = new Date(startDate);
      chunkDate.setDate(chunkDate.getDate() + (i * SHOM_MAX_DURATION));
      const chunkDuration = Math.min(SHOM_MAX_DURATION, requestedDuration - (i * SHOM_MAX_DURATION));

      console.log(`Chunk ${i}: date=${chunkDate.toISOString().split('T')[0]}, duration=${chunkDuration}`);

      if (chunkDuration > 0) {
        requests.push(fetchSHOMChunk(cst, chunkDate.toISOString().split('T')[0], chunkDuration));
      }
    }

    const results = await Promise.all(requests);
    console.log(`Tide API: Got ${results.filter(r => r && !r.error).length} successful chunks`);

    // Merge all results
    for (const result of results) {
      if (result && !result.error) {
        Object.assign(allData, result);
      }
    }

    if (Object.keys(allData).length === 0) {
      return { error: 'Failed to fetch tide data' };
    }

    // Parse the merged SHOM data
    const tides = [];
    const nextHighTide = { time: null, height: null, coefficient: null };
    const nextLowTide = { time: null, height: null };
    const now = new Date();

    // Sort dates to process in order
    const sortedDates = Object.keys(allData).sort();

    for (const dateStr of sortedDates) {
      const dayTides = allData[dateStr];
      for (const tide of dayTides) {
        const [type, time, height, coeff] = tide;

        if (type === 'tide.none' || time === '--:--') continue;

        const tideTime = new Date(`${dateStr}T${time}:00`);
        const isHigh = type === 'tide.high';
        const heightNum = parseFloat(height);
        const coeffNum = coeff !== '---' ? parseInt(coeff) : null;

        const tideEntry = {
          type: isHigh ? 'high' : 'low',
          date: dateStr,
          time,
          datetime: tideTime.toISOString(),
          height: heightNum,
          coefficient: coeffNum
        };

        tides.push(tideEntry);

        // Find next tides
        if (tideTime > now) {
          if (isHigh && !nextHighTide.time) {
            nextHighTide.time = tideTime.toISOString();
            nextHighTide.height = heightNum;
            nextHighTide.coefficient = coeffNum;
          } else if (!isHigh && !nextLowTide.time) {
            nextLowTide.time = tideTime.toISOString();
            nextLowTide.height = heightNum;
          }
        }
      }
    }

    // Get today's coefficient (from today's high tide)
    const todayStr = new Date().toISOString().split('T')[0];
    const todayCoeff = tides.find(t => t.date === todayStr && t.coefficient)?.coefficient;

    return {
      tides,
      nextHighTide: nextHighTide.time ? nextHighTide : null,
      nextLowTide: nextLowTide.time ? nextLowTide : null,
      todayCoefficient: todayCoeff || null,
      fetchedAt: new Date().toISOString()
    };

  } catch (error) {
    console.log(`Error fetching tide data for ${cst}:`, error.message);
    return { error: error.message };
  }
}

// Fetch a single chunk from SHOM API (max 11 days)
async function fetchSHOMChunk(cst, date, duration) {
  try {
    const url = `https://services.data.shom.fr/b2q8lrcdl4s04cbabsj4nhcb/hdm/spm/hlt?harborName=${cst}&duration=${duration}&date=${date}&utc=standard&correlation=1`;

    const response = await fetch(url, {
      headers: {
        'Referer': 'https://maree.shom.fr/',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      }
    });

    if (!response.ok) {
      console.log(`SHOM API error for ${cst} (${date}): ${response.status}`);
      return null;
    }

    const data = await response.json();

    // Check for error response
    if (data.error_code) {
      console.log(`SHOM API error for ${cst} (${date}): ${data.error_message}`);
      return null;
    }

    console.log(`SHOM chunk ${date}: got ${Object.keys(data).length} days`);
    return data;
  } catch (error) {
    console.log(`Error fetching SHOM chunk for ${cst} (${date}):`, error.message);
    return null;
  }
}
