// AI-powered wind station analysis and quality control
// Detects duplicates, offline stations, data anomalies, quality issues
// Protected by ADMIN_PASSWORD

import { kv } from '../../lib/kv.js';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const API_BASE = 'http://localhost:3001/api';
const KV_KEY = 'station_ai_suggestions';
const KV_REJECTED_KEY = 'station_ai_rejected';

// ============================================================
// AUTH
// ============================================================

function isAuthorized(req) {
  if (req.headers['x-vercel-cron'] === '1') return true;
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

// ============================================================
// HELPERS
// ============================================================

async function fetchStations() {
  try {
    const res = await fetch(`${API_BASE}/admin/stations`, {
      headers: { Authorization: `Bearer ${ADMIN_PASSWORD}` }
    });
    if (!res.ok) return [];
    const data = await res.json();
    return data.stations || [];
  } catch { return []; }
}

// Calculate distance in km between two points
function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Check if coordinates are in the sea (simplified check for France)
function isInSea(lat, lon) {
  // Atlantic ocean west of France
  if (lon < -5 && lat > 43 && lat < 50) return true;
  // Mediterranean far from coast
  if (lon > 6 && lat < 43 && lon > 8) return true;
  return false;
}

// Detect wind direction name
function directionName(deg) {
  const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  return dirs[Math.round(deg / 22.5) % 16];
}

// ============================================================
// DETECTION FUNCTIONS
// ============================================================

// Find duplicate stations (within 200m, different sources)
function detectDuplicates(stations) {
  const issues = [];
  const checked = new Set();

  for (let i = 0; i < stations.length; i++) {
    for (let j = i + 1; j < stations.length; j++) {
      const s1 = stations[i];
      const s2 = stations[j];

      // Skip if same source
      if (s1.source === s2.source) continue;

      const key = [s1.stableId, s2.stableId].sort().join('|');
      if (checked.has(key)) continue;
      checked.add(key);

      const dist = haversineKm(s1.latitude, s1.longitude, s2.latitude, s2.longitude);
      if (dist < 0.2) { // < 200m
        issues.push({
          type: 'duplicate',
          severity: dist < 0.05 ? 'high' : 'medium',
          stableId: s1.stableId,
          stationName: s1.name,
          description: `Station "${s1.name}" (${s1.source}) et "${s2.name}" (${s2.source}) sont a ${Math.round(dist * 1000)}m l'une de l'autre`,
          suggestion: { action: 'merge_or_hide', keepStation: s1.isOnline ? s1.stableId : s2.stableId },
          currentValues: {
            station1: { stableId: s1.stableId, name: s1.name, source: s1.source, isOnline: s1.isOnline },
            station2: { stableId: s2.stableId, name: s2.name, source: s2.source, isOnline: s2.isOnline },
            distance: Math.round(dist * 1000)
          },
          analysis: `Doublon detecte: les deux stations mesurent probablement le meme point. ${s1.isOnline && s2.isOnline ? 'Les deux sont online, comparer la qualite des donnees.' : s1.isOnline ? `Garder ${s1.source}.` : s2.isOnline ? `Garder ${s2.source}.` : 'Les deux sont offline.'}`
        });
      }
    }
  }
  return issues;
}

// Find chronically offline stations
function detectChronicOffline(stations) {
  const issues = [];
  const now = Date.now();
  const ONE_DAY = 24 * 60 * 60 * 1000;
  const ONE_WEEK = 7 * ONE_DAY;

  for (const s of stations) {
    if (s._hidden) continue;
    if (s._isAddition && !s.ts) continue; // Custom stations don't have ts

    if (!s.ts) {
      issues.push({
        type: 'chronic_offline',
        severity: 'medium',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" (${s.source}) n'a jamais renvoye de donnees`,
        suggestion: { action: 'hide', _hidden: true },
        currentValues: { source: s.source, isOnline: false, ts: null },
        analysis: 'Cette station n\'a aucun timestamp, elle n\'a probablement jamais fonctionne.'
      });
      continue;
    }

    const lastUpdate = new Date(s.ts).getTime();
    const age = now - lastUpdate;

    if (age > ONE_WEEK) {
      issues.push({
        type: 'chronic_offline',
        severity: 'high',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" offline depuis ${Math.round(age / ONE_DAY)} jours`,
        suggestion: { action: 'hide', _hidden: true, _notes: `Offline depuis ${new Date(s.ts).toLocaleDateString('fr')}` },
        currentValues: { source: s.source, isOnline: false, lastTs: s.ts, daysOffline: Math.round(age / ONE_DAY) },
        analysis: `Station offline depuis plus d'une semaine. Derniere donnee: ${new Date(s.ts).toLocaleString('fr')}.`
      });
    } else if (age > ONE_DAY && !s.isOnline) {
      issues.push({
        type: 'chronic_offline',
        severity: 'low',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" offline depuis ${Math.round(age / (60 * 60 * 1000))} heures`,
        suggestion: { action: 'monitor' },
        currentValues: { source: s.source, isOnline: false, lastTs: s.ts, hoursOffline: Math.round(age / (60 * 60 * 1000)) },
        analysis: `Station offline depuis plus de 24h. A surveiller.`
      });
    }
  }
  return issues;
}

// Detect suspicious/invalid data
function detectSuspiciousData(stations) {
  const issues = [];

  for (const s of stations) {
    if (s._hidden || !s.isOnline) continue;

    // Check for impossible values
    if (s.wind < 0 || s.gust < 0 || s.direction < 0 || s.direction > 360) {
      issues.push({
        type: 'suspicious_data',
        severity: 'high',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" a des valeurs negatives ou invalides`,
        suggestion: { action: 'flag', _notes: 'Valeurs invalides detectees' },
        currentValues: { wind: s.wind, gust: s.gust, direction: s.direction },
        analysis: `Valeurs impossibles: vent=${s.wind}, rafale=${s.gust}, direction=${s.direction}. Capteur defaillant?`
      });
      continue;
    }

    // Check for unrealistic wind (>100 knots is very rare in France)
    if (s.wind > 100 || s.gust > 150) {
      issues.push({
        type: 'suspicious_data',
        severity: 'high',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" rapporte un vent de ${s.wind} nds (rafale ${s.gust} nds)`,
        suggestion: { action: 'flag', _notes: 'Valeurs extremes suspectes' },
        currentValues: { wind: s.wind, gust: s.gust, direction: s.direction },
        analysis: `Vent >100 nds est exceptionnel en France. Verifier si c'est une tempete reelle ou un capteur defaillant.`
      });
      continue;
    }

    // Check for gust < wind (physically impossible)
    if (s.gust < s.wind && s.gust > 0) {
      issues.push({
        type: 'suspicious_data',
        severity: 'medium',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}": rafale (${s.gust}) < vent moyen (${s.wind})`,
        suggestion: { action: 'flag', _notes: 'Rafale inferieure au vent moyen' },
        currentValues: { wind: s.wind, gust: s.gust },
        analysis: `Physiquement impossible que la rafale soit inferieure au vent moyen. Erreur de calcul ou capteur defaillant.`
      });
    }
  }
  return issues;
}

// Cross-validate data between nearby stations
function detectDataAnomalies(stations) {
  const issues = [];
  const onlineStations = stations.filter(s => s.isOnline && !s._hidden && s.wind > 0);

  for (const s of onlineStations) {
    // Find nearby stations (within 20km)
    const nearby = onlineStations.filter(other =>
      other.stableId !== s.stableId &&
      haversineKm(s.latitude, s.longitude, other.latitude, other.longitude) < 20
    );

    if (nearby.length < 2) continue; // Need at least 2 neighbors for validation

    // Calculate average wind of neighbors
    const avgNeighborWind = nearby.reduce((sum, n) => sum + n.wind, 0) / nearby.length;
    const avgNeighborDir = nearby.reduce((sum, n) => sum + n.direction, 0) / nearby.length;

    // Check if this station is an outlier (>300% or <33% of neighbors)
    if (s.wind > avgNeighborWind * 3 && avgNeighborWind > 5) {
      issues.push({
        type: 'data_anomaly',
        severity: 'medium',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" rapporte ${s.wind} nds alors que les voisines ont ~${Math.round(avgNeighborWind)} nds`,
        suggestion: { action: 'investigate' },
        currentValues: {
          wind: s.wind,
          neighborAvg: Math.round(avgNeighborWind),
          neighbors: nearby.slice(0, 3).map(n => ({ name: n.name, wind: n.wind }))
        },
        analysis: `Cette station mesure 3x plus que la moyenne des ${nearby.length} stations voisines. Position exposee ou capteur amplifie?`
      });
    } else if (s.wind < avgNeighborWind * 0.33 && avgNeighborWind > 10) {
      issues.push({
        type: 'data_anomaly',
        severity: 'low',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" rapporte ${s.wind} nds alors que les voisines ont ~${Math.round(avgNeighborWind)} nds`,
        suggestion: { action: 'investigate' },
        currentValues: {
          wind: s.wind,
          neighborAvg: Math.round(avgNeighborWind),
          neighbors: nearby.slice(0, 3).map(n => ({ name: n.name, wind: n.wind }))
        },
        analysis: `Cette station mesure 3x moins que la moyenne des ${nearby.length} stations voisines. Position abritee ou capteur defaillant?`
      });
    }

    // Check direction consistency (>90 degrees difference from neighbors average)
    const dirDiff = Math.abs(s.direction - avgNeighborDir);
    const normalizedDiff = dirDiff > 180 ? 360 - dirDiff : dirDiff;
    if (normalizedDiff > 90 && avgNeighborWind > 8) {
      issues.push({
        type: 'data_anomaly',
        severity: 'low',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" indique ${directionName(s.direction)} alors que les voisines indiquent ${directionName(avgNeighborDir)}`,
        suggestion: { action: 'investigate' },
        currentValues: {
          direction: s.direction,
          neighborAvgDir: Math.round(avgNeighborDir),
          difference: Math.round(normalizedDiff)
        },
        analysis: `Direction opposee aux stations voisines (${Math.round(normalizedDiff)} deg de difference). Capteur de direction decale ou effet local?`
      });
    }
  }

  return issues;
}

// Detect location issues
function detectLocationIssues(stations) {
  const issues = [];

  for (const s of stations) {
    if (s._hidden) continue;

    // Check if in sea
    if (isInSea(s.latitude, s.longitude)) {
      issues.push({
        type: 'location_anomaly',
        severity: 'medium',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" semble etre en mer (${s.latitude.toFixed(4)}, ${s.longitude.toFixed(4)})`,
        suggestion: { action: 'fix_location' },
        currentValues: { latitude: s.latitude, longitude: s.longitude },
        analysis: 'Coordonnees en pleine mer. Station sur bateau/bouee ou erreur de coordonnees?'
      });
    }

    // Check for null island (0, 0) or other suspicious coords
    if ((s.latitude === 0 && s.longitude === 0) || (Math.abs(s.latitude) < 0.1 && Math.abs(s.longitude) < 0.1)) {
      issues.push({
        type: 'location_anomaly',
        severity: 'high',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" a des coordonnees nulles ou invalides`,
        suggestion: { action: 'fix_location' },
        currentValues: { latitude: s.latitude, longitude: s.longitude },
        analysis: 'Coordonnees (0,0) ou proches indiquent une erreur de saisie.'
      });
    }

    // Check if outside France bounds
    if (s.latitude < 41 || s.latitude > 51.5 || s.longitude < -5.5 || s.longitude > 10) {
      if (!s._isAddition) { // Custom stations might be intentionally outside
        issues.push({
          type: 'location_anomaly',
          severity: 'low',
          stableId: s.stableId,
          stationName: s.name,
          description: `Station "${s.name}" est en dehors de la France metropolitaine`,
          suggestion: { action: 'verify' },
          currentValues: { latitude: s.latitude, longitude: s.longitude },
          analysis: 'Coordonnees hors limites France metropolitaine. Station DOM-TOM ou erreur?'
        });
      }
    }
  }

  return issues;
}

// Detect missing metadata
function detectMissingMetadata(stations) {
  const issues = [];

  for (const s of stations) {
    if (s._hidden || s._isAddition) continue;

    if (!s.region) {
      issues.push({
        type: 'missing_metadata',
        severity: 'low',
        stableId: s.stableId,
        stationName: s.name,
        description: `Station "${s.name}" n'a pas de region assignee`,
        suggestion: { action: 'assign_region' },
        currentValues: { latitude: s.latitude, longitude: s.longitude, source: s.source },
        analysis: 'Region manquante. Peut etre deduite des coordonnees.'
      });
    }
  }

  return issues;
}

// ============================================================
// ANALYSIS ORCHESTRATOR
// ============================================================

async function runAnalysis(scope = 'all') {
  const startTime = Date.now();
  const stations = await fetchStations();

  if (stations.length === 0) {
    return { error: 'No stations found', elapsed: '0s' };
  }

  // Get existing suggestions and rejected IDs
  const [existingSuggestionsRaw, rejectedIdsRaw] = await Promise.all([
    kv.hgetall(KV_KEY),
    kv.smembers(KV_REJECTED_KEY)
  ]);
  const existingSuggestions = existingSuggestionsRaw || {};
  const rejectedIds = rejectedIdsRaw || [];
  const rejectedSet = new Set(rejectedIds);
  const existingIds = new Set(Object.keys(existingSuggestions));

  let issues = [];

  // Run appropriate detectors based on scope
  if (scope === 'all' || scope === 'duplicates') {
    issues.push(...detectDuplicates(stations));
  }
  if (scope === 'all' || scope === 'offline') {
    issues.push(...detectChronicOffline(stations));
  }
  if (scope === 'all' || scope === 'suspicious') {
    issues.push(...detectSuspiciousData(stations));
  }
  if (scope === 'all' || scope === 'quality') {
    issues.push(...detectDataAnomalies(stations));
  }
  if (scope === 'all' || scope === 'location') {
    issues.push(...detectLocationIssues(stations));
  }
  if (scope === 'all' || scope === 'metadata') {
    issues.push(...detectMissingMetadata(stations));
  }

  // Filter out already processed and rejected
  const newIssues = issues.filter(issue => {
    const id = `${issue.type}_${issue.stableId}`;
    return !existingIds.has(id) && !rejectedSet.has(id);
  });

  // Save new suggestions to KV
  if (newIssues.length > 0) {
    const toSave = {};
    for (const issue of newIssues) {
      const id = `${issue.type}_${issue.stableId}`;
      toSave[id] = JSON.stringify({
        id,
        ...issue,
        status: 'pending',
        createdAt: new Date().toISOString(),
        analyzedBy: 'station-ai'
      });
    }
    await kv.hset(KV_KEY, toSave);
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1) + 's';
  return {
    stationsAnalyzed: stations.length,
    issuesFound: issues.length,
    newSuggestions: newIssues.length,
    skipped: issues.length - newIssues.length,
    elapsed
  };
}

// ============================================================
// HANDLER
// ============================================================

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // GET - List suggestions
    if (req.method === 'GET') {
      const { action } = req.query;

      if (action === 'stats') {
        const suggestions = await kv.hgetall(KV_KEY) || {};
        const parsed = Object.values(suggestions).map(s => typeof s === 'string' ? JSON.parse(s) : s);
        const byType = {};
        const bySeverity = { high: 0, medium: 0, low: 0 };
        for (const s of parsed) {
          byType[s.type] = (byType[s.type] || 0) + 1;
          bySeverity[s.severity] = (bySeverity[s.severity] || 0) + 1;
        }
        return res.json({ total: parsed.length, byType, bySeverity });
      }

      const suggestions = await kv.hgetall(KV_KEY) || {};
      const parsed = Object.values(suggestions).map(s => {
        const p = typeof s === 'string' ? JSON.parse(s) : s;
        return p;
      }).filter(s => s.status === 'pending');

      // Sort by severity
      const severityOrder = { high: 0, medium: 1, low: 2 };
      parsed.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

      return res.json({ suggestions: parsed, count: parsed.length });
    }

    // POST - Run analysis
    if (req.method === 'POST') {
      const { scope = 'all' } = req.query;
      const result = await runAnalysis(scope);
      return res.json(result);
    }

    // PUT - Handle suggestion action
    if (req.method === 'PUT') {
      const { id, action } = req.query;
      if (!id || !action) {
        return res.status(400).json({ error: 'Missing id or action parameter' });
      }

      const suggestions = await kv.hgetall(KV_KEY) || {};
      const suggestion = suggestions[id] ? (typeof suggestions[id] === 'string' ? JSON.parse(suggestions[id]) : suggestions[id]) : null;

      if (!suggestion) {
        return res.status(404).json({ error: 'Suggestion not found' });
      }

      if (action === 'approve') {
        // Apply the suggestion
        if (suggestion.suggestion && Object.keys(suggestion.suggestion).length > 0) {
          const applyData = { ...suggestion.suggestion };
          delete applyData.action;

          if (Object.keys(applyData).length > 0) {
            await fetch(`${API_BASE}/admin/stations?id=${encodeURIComponent(suggestion.stableId)}`, {
              method: 'PUT',
              headers: {
                'Authorization': `Bearer ${ADMIN_PASSWORD}`,
                'Content-Type': 'application/json'
              },
              body: JSON.stringify(applyData)
            });
          }
        }

        // Mark as approved and remove
        await kv.hdel(KV_KEY, id);
        return res.json({ success: true, action: 'approved' });
      }

      if (action === 'reject') {
        // Add to rejected set and remove suggestion
        await Promise.all([
          kv.sadd(KV_REJECTED_KEY, id),
          kv.hdel(KV_KEY, id)
        ]);
        return res.json({ success: true, action: 'rejected' });
      }

      if (action === 'dismiss') {
        // Just remove without adding to rejected (can come back)
        await kv.hdel(KV_KEY, id);
        return res.json({ success: true, action: 'dismissed' });
      }

      return res.status(400).json({ error: 'Invalid action. Use: approve, reject, dismiss' });
    }

    // DELETE - Clear all suggestions
    if (req.method === 'DELETE') {
      const { clear } = req.query;
      if (clear === 'all') {
        await kv.del(KV_KEY);
        return res.json({ success: true, cleared: 'all' });
      }
      if (clear === 'rejected') {
        await kv.del(KV_REJECTED_KEY);
        return res.json({ success: true, cleared: 'rejected' });
      }
      return res.status(400).json({ error: 'Use ?clear=all or ?clear=rejected' });
    }

    return res.status(405).json({ error: 'Method not allowed' });

  } catch (e) {
    console.error('Station AI error:', e);
    return res.status(500).json({ error: e.message });
  }
}
