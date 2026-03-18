// Diabox API - Wind stations from data.diabox.com
// Fetches real-time data via dataUpdate.php, history via dataPartGeneration.php
//
// Usage:
//   GET /api/diabox              - Returns all stations (current data)
//   GET /api/diabox?history=ID   - Returns history for station ID
//   GET /api/diabox?hours=6      - Filter history by hours (default 6)

const DIABOX_BASE = 'https://data.diabox.com';

// Known Diabox stations with coordinates (from survey page)
const DIABOX_STATIONS = [
  { id: '101', name: 'Camping des Abers', lat: 48.5933, lon: -4.60245 },
  { id: '105', name: 'Pacific Palissades', lat: 43.2456, lon: 5.36924 },
  { id: '106', name: 'Archipel des Glénan', lat: 47.723, lon: -4.0031 },
  { id: '108', name: 'Port de Saint-Cast', lat: 48.6405, lon: -2.24764 },
  { id: '109', name: 'Club Nautique Plouguerneau', lat: 48.6288, lon: -4.50709 },
  { id: '110', name: 'Capitainerie de Crozon Morgat', lat: 48.2257, lon: -4.49354 },
  { id: '114', name: 'Port de Ouistreham', lat: 49.2897, lon: -0.248777 },
  { id: '115', name: 'Port de Concarneau', lat: 47.8704, lon: -3.9135 },
  { id: '9000', name: 'Brest Centre', lat: 48.3916, lon: -4.4801 },
];

// In-memory cache
let stationsCache = { data: null, timestamp: 0 };
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

// Fetch real-time data + latest gust for a single station
// Makes 2 parallel requests: real-time JSON + short history HTML for gust
async function fetchStationData(station) {
  const rtUrl = `${DIABOX_BASE}/dataUpdate.php?dbx_id=${station.id}` +
    `&dataNameList[]=wind_rt&dataNameList[]=temperature&dataNameList[]=pressure&dataNameList[]=humidity`;
  const histUrl = `${DIABOX_BASE}/dataPartGeneration.php?id=${station.id}&interval=hour&period=15`;

  try {
    // Fetch real-time and short history in parallel
    const [rtResponse, histResponse] = await Promise.all([
      fetch(rtUrl, {
        headers: { 'User-Agent': 'AnemOuest/1.0' },
        signal: AbortSignal.timeout(8000)
      }),
      fetch(histUrl, {
        headers: { 'User-Agent': 'AnemOuest/1.0' },
        signal: AbortSignal.timeout(8000)
      }).catch(() => null) // History is optional, don't fail if unavailable
    ]);

    if (!rtResponse.ok) return null;
    const data = await rtResponse.json();

    if (!data.wind_rt || !data.wind_rt.date) return null;

    const windDate = new Date(data.wind_rt.date * 1000);
    const isOnline = (Date.now() - windDate.getTime()) < 30 * 60 * 1000;

    // Extract latest gust from short history
    let gust = 0;
    let lastWind = Math.round((data.wind_rt.force || 0) * 10) / 10;
    let lastDir = data.wind_rt.dir || 0;
    let lastTs = windDate;

    if (histResponse && histResponse.ok) {
      const html = await histResponse.text();
      const obs = parseHistoryHtml(html);
      if (obs.length > 0) {
        const last = obs[obs.length - 1];
        gust = last.gust || 0;
        // Use the last complete observation values
        lastWind = last.wind;
        lastDir = last.dir;
        lastTs = new Date(last.ts);
      }
    }

    return {
      id: station.id,
      stableId: `diabox_${station.id}`,
      name: station.name,
      lat: station.lat,
      lon: station.lon,
      wind: lastWind,
      gust,
      direction: lastDir,
      isOnline,
      source: 'diabox',
      ts: lastTs.toISOString(),
      temperature: data.temperature?.val ?? null,
      pressure: data.pressure?.val ?? null,
      humidity: data.humidity?.val ?? null,
    };
  } catch (e) {
    return null;
  }
}

// Fetch all stations concurrently
async function fetchAllStations() {
  const now = Date.now();

  if (stationsCache.data && (now - stationsCache.timestamp) < CACHE_DURATION) {
    return { stations: stationsCache.data, cached: true };
  }

  const results = await Promise.allSettled(
    DIABOX_STATIONS.map(s => fetchStationData(s))
  );

  const stations = results
    .filter(r => r.status === 'fulfilled' && r.value !== null)
    .map(r => r.value);

  if (stations.length > 0) {
    stationsCache = { data: stations, timestamp: now };
  }

  return { stations, cached: false };
}

// Parse HTML history from dataPartGeneration.php
// The table is transposed: rows = data types, columns = time points
// Header row 1: dates (DD/MM), Header row 2: times (HHhMMm)
// Body rows: "Average wind (knots)", "Gusts (knots)", "Wind direction (°N)"
function parseHistoryHtml(html) {
  // Extract all <tr> rows
  const rows = [];
  const trRe = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let trMatch;
  while ((trMatch = trRe.exec(html)) !== null) {
    rows.push(trMatch[1]);
  }

  if (rows.length < 5) return [];

  // Extract text after > from split parts (for dates and times)
  function getTexts(rowHtml, tag) {
    const texts = [];
    const parts = rowHtml.split(new RegExp('<' + tag, 'gi'));
    for (let i = 1; i < parts.length; i++) {
      const m = parts[i].match(/>([^<]*)</);
      if (m) texts.push(m[1].trim());
    }
    return texts;
  }

  // Extract last number from each <td> cell (handles nested HTML like <div><span>)
  function getNumbers(rowHtml) {
    const nums = [];
    const cells = rowHtml.split(/<td/gi);
    for (let i = 1; i < cells.length; i++) {
      const tdEnd = cells[i].indexOf('</td>');
      const cellContent = tdEnd >= 0 ? cells[i].substring(0, tdEnd) : cells[i];
      const allNums = cellContent.match(/[\d.]+/g);
      if (allNums && allNums.length > 0) {
        nums.push(parseFloat(allNums[allNums.length - 1]));
      } else {
        nums.push(NaN);
      }
    }
    return nums;
  }

  // Parse timezone offset from header: "(UTC+0100)" or "(UTC-0500)"
  // Row 0 header contains something like: Start<br/>2026-02-01 10:35:00<br/>(UTC+0100)
  let tzOffsetMinutes = 60; // Default to UTC+1 (France)
  const tzMatch = rows[0].match(/UTC([+-])(\d{2})(\d{2})/);
  if (tzMatch) {
    const sign = tzMatch[1] === '+' ? 1 : -1;
    tzOffsetMinutes = sign * (parseInt(tzMatch[2]) * 60 + parseInt(tzMatch[3]));
  }

  // Row 0: dates in <td> cells, Row 1: times in <th> cells
  const dates = getTexts(rows[0], 'td');
  const times = getTexts(rows[1], 'th');
  const colCount = Math.min(dates.length, times.length);
  if (colCount === 0) return [];

  // Find data rows (must start with <th> to exclude graph table rows)
  let windRow = '', gustRow = '', dirRow = '';
  for (const row of rows) {
    if (!row.trimStart().startsWith('<th>')) continue;
    const lower = row.toLowerCase();
    if (!windRow && lower.includes('average wind')) windRow = row;
    else if (!gustRow && lower.includes('gusts')) gustRow = row;
    else if (!dirRow && lower.includes('wind direction')) dirRow = row;
  }

  if (!windRow || !gustRow || !dirRow) return [];

  const winds = getNumbers(windRow);
  const gusts = getNumbers(gustRow);
  const dirs = getNumbers(dirRow);

  const currentYear = new Date().getFullYear();
  const observations = [];

  for (let i = 0; i < colCount; i++) {
    if (isNaN(winds[i])) continue;

    const dm = dates[i].match(/(\d{2})\/(\d{2})/);
    const tm = times[i].match(/(\d{1,2})h(\d{2})m/);
    if (!dm || !tm) continue;

    // Build ISO string with timezone offset to get correct UTC time
    const day = dm[1].padStart(2, '0');
    const month = dm[2].padStart(2, '0');
    const hour = tm[1].padStart(2, '0');
    const minute = tm[2].padStart(2, '0');
    const sign = tzOffsetMinutes >= 0 ? '+' : '-';
    const absOffset = Math.abs(tzOffsetMinutes);
    const tzH = String(Math.floor(absOffset / 60)).padStart(2, '0');
    const tzM = String(absOffset % 60).padStart(2, '0');
    const isoStr = `${currentYear}-${month}-${day}T${hour}:${minute}:00${sign}${tzH}:${tzM}`;
    const ts = new Date(isoStr);

    if (ts > Date.now() + 86400000) ts.setFullYear(currentYear - 1);

    observations.push({
      ts: ts.toISOString(),
      wind: Math.round(winds[i] * 10) / 10,
      gust: Math.round((isNaN(gusts[i]) ? winds[i] : gusts[i]) * 10) / 10,
      dir: isNaN(dirs[i]) ? 0 : Math.round(dirs[i]),
    });
  }

  return observations;
}

// Fetch history for a station
// Diabox API: interval=hour gives 1h window, interval=day gives 24h window.
// period = seconds between data points (resolution).
// Always use interval=day to get full 24h, then filter client-side.
async function fetchHistory(stationId, hours) {
  // Adjust resolution based on requested duration
  let period;
  if (hours <= 2) period = 120;       // 2 min spacing → ~60 pts for 2h
  else if (hours <= 6) period = 360;  // 6 min spacing → ~60 pts for 6h
  else if (hours <= 24) period = 720; // 12 min spacing → ~121 pts for 24h
  else period = 1440;                 // 24 min spacing → ~61 pts (max 24h available)

  const url = `${DIABOX_BASE}/dataPartGeneration.php?id=${stationId}&interval=day&period=${period}`;

  const response = await fetch(url, {
    headers: { 'User-Agent': 'AnemOuest/1.0' }
  });

  if (!response.ok) {
    throw new Error(`Diabox history: HTTP ${response.status}`);
  }

  const html = await response.text();
  const observations = parseHistoryHtml(html);

  const cutoff = Date.now() - (hours * 60 * 60 * 1000);
  return observations.filter(o => new Date(o.ts).getTime() >= cutoff);
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=300');

  const { history, hours = '6' } = req.query;

  try {
    // History mode
    if (history) {
      const hoursNum = Math.min(parseInt(hours) || 6, 168);
      const rawId = history.replace(/^diabox_/, '');

      try {
        const observations = await fetchHistory(rawId, hoursNum);
        return res.json({
          stationId: history,
          source: 'diabox',
          observations,
          count: observations.length,
          hours: hoursNum,
        });
      } catch (e) {
        return res.json({
          stationId: history,
          observations: [],
          error: e.message,
          hours: hoursNum,
        });
      }
    }

    // All stations mode
    const { stations, cached } = await fetchAllStations();

    return res.json({
      stations,
      cached,
      count: stations.length,
      timestamp: new Date().toISOString(),
    });

  } catch (e) {
    console.error('Diabox error:', e);

    if (stationsCache.data) {
      return res.json({
        stations: stationsCache.data,
        cached: true,
        stale: true,
        error: e.message,
      });
    }

    return res.status(500).json({
      error: 'Failed to fetch Diabox data',
      details: e.message,
    });
  }
}
