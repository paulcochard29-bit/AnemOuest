// Winds-Up API - Authenticated access to wind data
// Requires paid Winds-Up subscription
//
// Usage:
//   POST /api/windsup { action: 'login', email: '...', password: '...' }
//   GET /api/windsup?token=... - Returns all stations
//   GET /api/windsup?token=...&history=ID&hours=6 - Returns history

const WINDSUP_BASE = 'https://www.winds-up.com';

// Simple encryption for storing session cookies in token (XOR with key)
const TOKEN_KEY = process.env.WINDSUP_TOKEN_KEY || 'anemouest-windsup-2024';

function encryptToken(data) {
  const json = JSON.stringify(data);
  const encoded = Buffer.from(json).toString('base64');
  // Simple XOR obfuscation
  let result = '';
  for (let i = 0; i < encoded.length; i++) {
    result += String.fromCharCode(encoded.charCodeAt(i) ^ TOKEN_KEY.charCodeAt(i % TOKEN_KEY.length));
  }
  return Buffer.from(result).toString('base64');
}

function decryptToken(token) {
  try {
    const decoded = Buffer.from(token, 'base64').toString();
    let result = '';
    for (let i = 0; i < decoded.length; i++) {
      result += String.fromCharCode(decoded.charCodeAt(i) ^ TOKEN_KEY.charCodeAt(i % TOKEN_KEY.length));
    }
    const json = Buffer.from(result, 'base64').toString();
    return JSON.parse(json);
  } catch (e) {
    return null;
  }
}

// All Winds-Up stations (from iOS app)
const STATIONS = [
  // Bretagne
  { id: 7, name: "La Baule", slug: "la-baule", lat: 47.2811, lon: -2.38417 },
  { id: 12, name: "Chèvre", slug: "chyivre", lat: 48.2283, lon: -4.50141 },
  { id: 15, name: "Dossen", slug: "dossen", lat: 48.7023, lon: -4.05348 },
  { id: 19, name: "Fort Bloqué", slug: "fort-bloque", lat: 47.7336, lon: -3.49892 },
  { id: 28, name: "Lancieux", slug: "lancieux-le-briantais", lat: 48.6084, lon: -2.15619 },
  { id: 33, name: "Pont-Mahé", slug: "pont-mahyo", lat: 47.4463, lon: -2.45405 },
  { id: 34, name: "Saint Malo", slug: "saint-malo", lat: 48.6531, lon: -2.01313 },
  { id: 37, name: "Brest - Keraliou", slug: "brest-keraliou", lat: 48.3812, lon: -4.40727 },
  { id: 41, name: "Quiberon", slug: "quiberon", lat: 47.5511, lon: -3.13268 },
  { id: 55, name: "Val André", slug: "val-andre", lat: 48.5878, lon: -2.55751 },
  { id: 62, name: "Mazerolles", slug: "mazerolles", lat: 47.3621, lon: -1.50899 },
  { id: 66, name: "Douarnenez Pentrez", slug: "douarnenez-pentrez", lat: 48.1828, lon: -4.29253 },
  { id: 89, name: "Guissény", slug: "guisseny", lat: 48.6392, lon: -4.44662 },
  { id: 108, name: "Brignogan", slug: "brignogan", lat: 48.6729, lon: -4.32752 },
  { id: 116, name: "Penvins", slug: "penvins", lat: 47.495, lon: -2.68223 },
  { id: 132, name: "Plouescat", slug: "plouescat", lat: 48.6505, lon: -4.21309 },
  { id: 134, name: "Le Rohu", slug: "le-rohu-st-gildas-de-rhuys", lat: 47.5188, lon: -2.85707 },
  { id: 1524, name: "Le Steir Penmarc'h", slug: "le-steir-penmarch-", lat: 47.7998, lon: -4.3311 },
  { id: 1559, name: "Brest - Pôle France", slug: "brest-pyele-france", lat: 48.3874, lon: -4.43451 },
  { id: 1566, name: "Bénodet Dune", slug: "benodet-dune", lat: 47.8623, lon: -4.08461 },
  { id: 1667, name: "La Torche", slug: "la-torche-st-jean-trolimon", lat: 47.8525, lon: -4.34792 },
  { id: 1674, name: "Saint Pierre Quiberon", slug: "saint-pierre-quiberon-", lat: 47.5369, lon: -3.14 },
  { id: 1683, name: "Sainte-Marguerite", slug: "sainte-marguerite", lat: 48.5935, lon: -4.60594 },
  { id: 1697, name: "Treompan Dunes", slug: "treompan-dunes-3-moutons", lat: 48.5715, lon: -4.66336 },
  { id: 1705, name: "Kersidan", slug: "kersidan", lat: 47.7973, lon: -3.82717 },
  // Vendée / Charente
  { id: 9, name: "Saint Brévin", slug: "saint-bryovin-", lat: 47.225, lon: -2.173 },
  { id: 43, name: "La Rochelle", slug: "la-rochelle", lat: 46.1428, lon: -1.17177 },
  { id: 53, name: "La Tranche - Le Phare", slug: "la-tranche-sur-mer-le-phare", lat: 46.3439, lon: -1.43073 },
  { id: 59, name: "La Palmyre", slug: "la-palmyre-accrokite", lat: 45.6886, lon: -1.19039 },
  { id: 80, name: "Ile de Ré - Albeau", slug: "ile-de-ryo-ecole-a-albeau", lat: 46.2000, lon: -1.5333 },
  { id: 91, name: "Ile Oléron", slug: "ile-oleron", lat: 45.9333, lon: -1.3167 },
  { id: 105, name: "Brétignolles", slug: "bretignolles-sur-mer", lat: 46.6333, lon: -1.8667 },
  { id: 106, name: "Fromentine", slug: "fromentine", lat: 46.886, lon: -2.15371 },
  { id: 133, name: "Saint Gilles Croix de Vie", slug: "saint-gilles-croix-de-vie", lat: 46.6833, lon: -1.9333 },
  { id: 1529, name: "Saint Jean de Monts", slug: "saint-jean-de-monts-", lat: 46.8000, lon: -2.0667 },
  { id: 1611, name: "Noirmoutier - Barbâtre", slug: "noirmoutier-barbyctre-", lat: 46.9423, lon: -2.1733 },
  { id: 1658, name: "Les Sables d'Olonne", slug: "les-sables-dolonne", lat: 46.5000, lon: -1.7833 },
  // Manche / Nord
  { id: 13, name: "Le Crotoy", slug: "le-crotoy", lat: 50.2141, lon: 1.62614 },
  { id: 16, name: "Dunkerque", slug: "dunkerque", lat: 51.0543, lon: 2.41481 },
  { id: 40, name: "Wissant", slug: "wissant", lat: 50.8876, lon: 1.65834 },
  { id: 56, name: "Wimereux", slug: "wimereux", lat: 50.7641, lon: 1.60559 },
  { id: 57, name: "Berck", slug: "berck", lat: 50.4053, lon: 1.55768 },
  { id: 100, name: "Le Touquet", slug: "le-touquet", lat: 50.5172, lon: 1.57857 },
  { id: 101, name: "Calais", slug: "calais", lat: 50.9762, lon: 1.89672 },
  // Aquitaine
  { id: 4, name: "Arcachon", slug: "arcachon", lat: 44.6481, lon: -1.19855 },
  { id: 25, name: "Hourtin Lac", slug: "hourtin-lac", lat: 45.1833, lon: -1.0833 },
  { id: 27, name: "Lacanau - Lac", slug: "lacanau-lac", lat: 44.9667, lon: -1.1333 },
  { id: 46, name: "Sanguinet", slug: "sanguinet", lat: 44.4833, lon: -1.0833 },
  // Méditerranée
  { id: 1, name: "Agde", slug: "agde", lat: 43.2723, lon: 3.50471 },
  { id: 2, name: "Almanarre", slug: "almanarre-salin-des-pesquiers", lat: 43.0667, lon: 6.13491 },
  { id: 22, name: "Port Camargue", slug: "port-camargue", lat: 43.5182, lon: 4.12238 },
  { id: 23, name: "Gruissan", slug: "gruissan-", lat: 43.11, lon: 3.125 },
  { id: 39, name: "Leucate", slug: "leucate-", lat: 42.8728, lon: 3.03635 },
  { id: 44, name: "Marseille - Pointe Rouge", slug: "marseille-pointe-rouge-digue", lat: 43.2463, lon: 5.36383 },
  { id: 58, name: "Barcarès", slug: "barcares-", lat: 42.8324, lon: 3.03459 },
];

// Direction text to degrees
function directionToDegrees(dir) {
  const map = {
    'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
    'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
    'S': 180, 'SSO': 202.5, 'SO': 225, 'OSO': 247.5,
    'O': 270, 'ONO': 292.5, 'NO': 315, 'NNO': 337.5,
    'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
    'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5
  };
  return map[dir?.toUpperCase()] ?? 0;
}

// Login to Winds-Up
async function login(email, password) {
  console.log('WindsUp: Starting login for', email);

  // First get login page to establish session
  const loginPageRes = await fetch(`${WINDSUP_BASE}/index.php?p=connexion`, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
    }
  });

  // Extract cookies from response
  const cookies = loginPageRes.headers.getSetCookie?.() || [];
  let phpSessionId = null;
  for (const cookie of cookies) {
    const match = cookie.match(/PHPSESSID=([^;]+)/);
    if (match) phpSessionId = match[1];
  }
  console.log('WindsUp: Got PHPSESSID:', phpSessionId ? 'yes' : 'no');

  // Use application/x-www-form-urlencoded instead of multipart (simpler and works)
  const formData = new URLSearchParams();
  formData.append('login_pseudo', email);
  formData.append('login_passwd', password);
  formData.append('action', 'post_login');
  formData.append('p', 'connexion');
  formData.append('id', '');
  formData.append('cat', '');
  formData.append('aff', '');
  formData.append('rester_log', '1');
  formData.append('MAX_FILE_SIZE', '10000000');

  // POST login
  const loginRes = await fetch(`${WINDSUP_BASE}/index.php`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      'Referer': `${WINDSUP_BASE}/index.php?p=connexion`,
      'Cookie': phpSessionId ? `PHPSESSID=${phpSessionId}` : '',
      'Origin': WINDSUP_BASE,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    },
    body: formData.toString(),
    redirect: 'manual'
  });

  console.log('WindsUp: Login response status:', loginRes.status);

  // Collect all cookies from login response
  const loginCookies = loginRes.headers.getSetCookie?.() || [];
  const sessionCookies = {};

  // Add initial session cookie
  if (phpSessionId) {
    sessionCookies.PHPSESSID = phpSessionId;
  }

  // Parse new cookies
  for (const cookie of loginCookies) {
    const parts = cookie.split(';')[0].split('=');
    if (parts.length >= 2) {
      const name = parts[0];
      const value = parts.slice(1).join('=');
      sessionCookies[name] = value;
      console.log('WindsUp: Got cookie:', name);
    }
  }

  // Check for auth cookies
  const hasAutolog = 'autolog' in sessionCookies;
  const hasCodeCnx = 'codeCnx' in sessionCookies;
  console.log('WindsUp: hasAutolog:', hasAutolog, 'hasCodeCnx:', hasCodeCnx);

  if (hasAutolog || hasCodeCnx) {
    return { success: true, cookies: sessionCookies };
  }

  // Check response body for success indicators
  const html = await loginRes.text();
  console.log('WindsUp: Response length:', html.length);

  // Debug: check what's in the response
  const hasDeconnexion = html.includes('Déconnexion') || html.includes('deconnexion') || html.includes('D\u00e9connexion');
  const hasMonCompte = html.includes('Mon compte') || html.includes('mon-compte');
  const hasMonEspace = html.includes('Mon espace') || html.includes('mon-espace');
  const hasLoginForm = html.includes('login_pseudo') && html.includes('login_passwd');
  const hasError = html.includes('Identifiant ou mot de passe incorrect') || html.includes('incorrect');

  console.log('WindsUp: hasDeconnexion:', hasDeconnexion);
  console.log('WindsUp: hasMonCompte:', hasMonCompte);
  console.log('WindsUp: hasLoginForm:', hasLoginForm);
  console.log('WindsUp: hasError:', hasError);

  if (hasDeconnexion || hasMonCompte || hasMonEspace) {
    return { success: true, cookies: sessionCookies };
  }

  // If we still see the login form, login failed
  if (hasLoginForm || hasError) {
    return { success: false, error: 'Identifiants incorrects' };
  }

  // Last resort: check for redirect (302/303)
  if (loginRes.status === 302 || loginRes.status === 303) {
    const location = loginRes.headers.get('location');
    console.log('WindsUp: Redirect to:', location);
    if (location && !location.includes('connexion')) {
      return { success: true, cookies: sessionCookies };
    }
  }

  return { success: false, error: 'Login failed' };
}

// Parse Highcharts data from station HTML
function parseStationHTML(html, station) {
  // Check if broken
  if (html.includes('Spot en panne')) {
    return { ...station, isBroken: true };
  }

  // Match ONLY observation data points (must have abo: field to exclude forecast/range series)
  // Observation: {x:TS, y:WIND, o:"DIR", color:"...", img:"...", min:"X", max:"Y", abo:""}
  // Forecast (previs): {x:TS, y:WIND, o:"DIR", img:"/fleches/...", now:""}  — NO abo field
  // Range: {x:TS, low:X, high:Y, color:"..."} — NO y, NO o, NO abo
  const dataPattern = /\{x:(\d+),\s*y:(\d+(?:\.\d+)?),\s*o:"([^"]*)"[^}]*?abo:"([^"]*)"[^}]*?\}/g;
  const maxPattern = /max:"(\d+(?:\.\d+)?)"/;
  const dirFromImgPattern = /anemo_\d+-([A-Z]+)\.gif/;
  const observations = [];
  let hasGatedData = false;

  let match;
  while ((match = dataPattern.exec(html)) !== null) {
    const [fullMatch, timestamp, wind, dir, abo] = match;

    // Check subscription gating (abo:"no" = not authenticated)
    const isGated = abo === 'no';
    if (isGated) hasGatedData = true;

    // Extract gust from max field
    const maxMatch = fullMatch.match(maxPattern);
    const gustVal = maxMatch && parseFloat(maxMatch[1]) > 0
      ? parseFloat(maxMatch[1])
      : parseFloat(wind);

    // For gated data with empty direction, extract from image filename
    let direction = dir;
    if (!direction) {
      const imgMatch = fullMatch.match(dirFromImgPattern);
      if (imgMatch) direction = imgMatch[1];
    }

    observations.push({
      ts: new Date(parseInt(timestamp) - 3600000).toISOString(),
      wind: parseFloat(wind),
      gust: gustVal,
      dir: directionToDegrees(direction),
      dirText: direction || '?',
      isGated: !!isGated
    });
  }

  observations.sort((a, b) => new Date(b.ts) - new Date(a.ts));

  const latest = observations[0];
  const isOnline = latest && (Date.now() - new Date(latest.ts).getTime()) < 30 * 60 * 1000;

  return {
    id: String(station.id),
    stableId: `windsup_${station.id}`,
    name: station.name,
    lat: station.lat,
    lon: station.lon,
    wind: latest?.wind || 0,
    gust: latest?.gust || 0,
    direction: latest?.dir || 0,
    isOnline,
    source: 'windsup',
    ts: latest?.ts,
    observations,
    hasGatedData // true = session cookies don't work, data is partial
  };
}

// Check if HTML indicates a dead/expired session
function isSessionDead(html) {
  const hasLoginForm = html.includes('login_pseudo') && html.includes('login_passwd');
  const hasConnexion = html.includes('p=connexion');
  const noData = !html.includes('{x:');
  // abo:"no" means subscription-gated = cookies not authenticating properly
  const hasGatedData = html.includes('abo:"no"');
  return hasLoginForm || (hasConnexion && noData) || hasGatedData;
}

// Fetch station HTML with cookies
async function fetchStationHTML(station, cookies) {
  const url = `${WINDSUP_BASE}/spot-${station.slug}-windsurf-kitesurf-${station.id}-observations-releves-vent.html`;
  const cookieHeader = Object.entries(cookies)
    .map(([k, v]) => `${k}=${v}`)
    .join('; ');

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
      'Cookie': cookieHeader,
      'Referer': WINDSUP_BASE
    }
  });

  if (!res.ok) return null;
  return res.text();
}

// Fetch station data with session validation and auto-relogin
async function fetchStation(station, cookies, session) {
  const html = await fetchStationHTML(station, cookies);
  if (!html) return null;

  // Detect dead session (login form, no data, or subscription-gated recent data)
  if (isSessionDead(html) && session?.email && session?.password && !session._reloginAttempted) {
    console.log('WindsUp: Session dead (abo:"no" or login form), attempting re-login...');
    session._reloginAttempted = true;
    const relogin = await login(session.email, session.password);
    if (relogin.success) {
      console.log('WindsUp: Re-login successful');
      Object.assign(cookies, relogin.cookies);
      session._newCookies = relogin.cookies;
      // Retry with new cookies
      const retryHtml = await fetchStationHTML(station, relogin.cookies);
      if (retryHtml) {
        const retryData = parseStationHTML(retryHtml, station);
        if (retryData.hasGatedData) {
          console.log('WindsUp: Still gated after re-login — subscription may be expired');
          session._subscriptionExpired = true;
        }
        return retryData;
      }
    } else {
      console.log('WindsUp: Re-login failed');
      session._sessionExpired = true;
    }
    // Fall through to parse the original (gated) HTML anyway
    return parseStationHTML(html, station);
  }

  return parseStationHTML(html, station);
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Cache-Control', 's-maxage=120, stale-while-revalidate=300');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  try {
    // POST: Login
    if (req.method === 'POST') {
      const { action, email, password } = req.body || {};

      if (action === 'login' && email && password) {
        const result = await login(email, password);

        if (result.success) {
          const token = encryptToken({
            cookies: result.cookies,
            email,
            password,
            exp: Date.now() + 7 * 24 * 60 * 60 * 1000 // 7 days
          });

          return res.json({
            success: true,
            token,
            message: 'Connexion réussie'
          });
        }

        return res.status(401).json({
          success: false,
          error: 'Identifiants incorrects'
        });
      }

      return res.status(400).json({ error: 'Invalid action' });
    }

    // GET: Fetch stations or history
    const { token, history, hours = '6' } = req.query;

    if (!token) {
      return res.status(401).json({
        error: 'Token requis',
        needsLogin: true
      });
    }

    const session = decryptToken(token);
    if (!session || !session.cookies || Date.now() > session.exp) {
      return res.status(401).json({
        error: 'Session expirée',
        needsLogin: true
      });
    }

    // History for specific station
    if (history) {
      const stationId = parseInt(history.replace('windsup_', ''));
      const station = STATIONS.find(s => s.id === stationId);

      if (!station) {
        return res.json({
          stationId: history,
          observations: [],
          error: 'Station not found'
        });
      }

      const data = await fetchStation(station, session.cookies, session);

      // Session expired and re-login failed
      if (session._sessionExpired) {
        return res.status(401).json({
          error: 'Session WindsUp expirée',
          sessionExpired: true,
          needsLogin: true
        });
      }

      const hoursNum = parseInt(hours) || 6;
      const now = Date.now();
      const cutoff = now - hoursNum * 60 * 60 * 1000;

      const filtered = (data?.observations || [])
        .filter(o => {
          const t = new Date(o.ts).getTime();
          return t >= cutoff && t <= now;
        })
        .sort((a, b) => new Date(a.ts) - new Date(b.ts))
        .map(o => ({ ts: o.ts, wind: o.wind, gust: o.gust, dir: o.dir }));

      // If re-login succeeded, return new token
      const response = {
        stationId: history,
        name: station.name,
        source: 'windsup',
        observations: filtered,
        count: filtered.length,
        hours: hoursNum
      };

      if (session._newCookies) {
        response.newToken = encryptToken({
          cookies: session._newCookies,
          email: session.email,
          password: session.password,
          exp: Date.now() + 7 * 24 * 60 * 60 * 1000
        });
      }

      return res.json(response);
    }

    // Fetch first station to validate session
    const testStation = STATIONS[0];
    const testData = await fetchStation(testStation, session.cookies, session);

    // Session expired and re-login failed
    if (session._sessionExpired) {
      return res.status(401).json({
        error: 'Session WindsUp expirée — reconnectez-vous',
        sessionExpired: true,
        needsLogin: true
      });
    }

    // Use potentially refreshed cookies for remaining stations
    const activeCookies = session._newCookies || session.cookies;

    // Fetch all stations (skip the test station, we already have it)
    const remainingStations = STATIONS.filter(s => s.id !== testStation.id);
    const results = await Promise.allSettled(
      remainingStations.map(s => fetchStation(s, activeCookies, session))
    );

    const allResults = [
      testData,
      ...results.filter(r => r.status === 'fulfilled').map(r => r.value)
    ];

    const stations = allResults
      .filter(s => s && !s.isBroken && s.isOnline)
      .map(s => ({
        id: s.id,
        stableId: s.stableId,
        name: s.name,
        lat: s.lat,
        lon: s.lon,
        wind: s.wind,
        gust: s.gust,
        direction: s.direction,
        isOnline: s.isOnline,
        source: 'windsup',
        ts: s.ts
      }));

    const hasAnyGated = allResults.some(s => s?.hasGatedData);

    const response = {
      stations,
      count: stations.length,
      timestamp: new Date().toISOString(),
    };

    if (hasAnyGated) {
      response.warning = 'Données partielles — abonnement WindsUp non reconnu';
      response.hasGatedData = true;
    }

    // If re-login succeeded, return new token so frontend can update localStorage
    if (session._newCookies) {
      response.newToken = encryptToken({
        cookies: session._newCookies,
        email: session.email,
        password: session.password,
        exp: Date.now() + 7 * 24 * 60 * 60 * 1000
      });
    }

    return res.json(response);

  } catch (e) {
    console.error('WindsUp error:', e);
    return res.status(500).json({
      error: 'Failed to fetch WindsUp data',
      details: e.message
    });
  }
}
