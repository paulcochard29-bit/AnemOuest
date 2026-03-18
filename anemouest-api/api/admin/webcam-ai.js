// AI-powered webcam analysis and correction suggestions
// Uses Claude Vision + Mapbox Geocoding to detect issues
// Protected by ADMIN_PASSWORD or CRON_SECRET

import { kv } from '../../lib/kv.js';
import { head } from '../../lib/storage.js';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN || process.env.MAPBOX_TOKEN;
const API_BASE = 'http://localhost:3001/api';
const KV_KEY = 'webcam_ai_suggestions';
const KV_REJECTED_KEY = 'webcam_ai_rejected';
const MODEL = 'claude-sonnet-4-5-20250929';

// ============================================================
// AUTH
// ============================================================

function isAuthorized(req) {
  // Cron jobs from Vercel
  if (req.headers['x-vercel-cron'] === '1') return true;
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

// ============================================================
// HELPERS
// ============================================================

async function fetchWebcams() {
  try {
    const res = await fetch(`${API_BASE}/webcams?includeAll=true`);
    return res.ok ? await res.json() : [];
  } catch { return []; }
}

async function getHealthStatus() {
  try {
    const blobInfo = await head('webcam-health.json');
    if (blobInfo) {
      const url = new URL(blobInfo.url);
      url.searchParams.set('_t', Date.now());
      const response = await fetch(url.toString(), { cache: 'no-store' });
      const data = await response.json();
      return data.webcams || data;
    }
  } catch {}
  return {};
}

// Geocode a location name and return coordinates
async function geocode(query) {
  if (!MAPBOX_TOKEN) return null;
  try {
    const res = await fetch(
      `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(query)}.json?country=fr&limit=1&language=fr&access_token=${MAPBOX_TOKEN}`,
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await res.json();
    if (data.features?.length > 0) {
      const [lon, lat] = data.features[0].center;
      return { lat, lon, name: data.features[0].place_name, confidence: data.features[0].relevance || 0.5 };
    }
  } catch {}
  return null;
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

// Fetch a webcam image and return base64
async function captureImage(imageUrl) {
  try {
    const res = await fetch(imageUrl, {
      signal: AbortSignal.timeout(10000),
      headers: { 'User-Agent': 'AnemOuest-AI/1.0' }
    });
    if (!res.ok) return null;
    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('image')) return null;
    const buffer = Buffer.from(await res.arrayBuffer());
    if (buffer.length < 1000) return null;
    const mediaType = contentType.includes('png') ? 'image/png' : 'image/jpeg';
    return { base64: buffer.toString('base64'), mediaType, size: buffer.length };
  } catch { return null; }
}

// Find duplicate webcams (within 100m)
function findDuplicates(webcams) {
  const dupes = [];
  for (let i = 0; i < webcams.length; i++) {
    for (let j = i + 1; j < webcams.length; j++) {
      const dist = haversineKm(
        webcams[i].latitude, webcams[i].longitude,
        webcams[j].latitude, webcams[j].longitude
      );
      if (dist < 0.1) { // < 100m
        dupes.push({ webcam1: webcams[i], webcam2: webcams[j], distance: Math.round(dist * 1000) });
      }
    }
  }
  return dupes;
}

// Call Claude Vision API
async function analyzeWithClaude(webcamBatch) {
  if (!ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY not set');

  const content = [];

  for (const item of webcamBatch) {
    // Add image if available
    if (item.image) {
      content.push({
        type: 'image',
        source: { type: 'base64', media_type: item.image.mediaType, data: item.image.base64 }
      });
    }

    // Add metadata text
    content.push({
      type: 'text',
      text: `Webcam "${item.webcam.name}" (ID: ${item.webcam.id}):
- Location: ${item.webcam.location}, Region: ${item.webcam.region || 'N/A'}
- Coordinates: ${item.webcam.latitude}, ${item.webcam.longitude}
- Source: ${item.webcam.source}
- Health: ${item.health?.online ? 'Online' : 'Offline'}, consecutive failures: ${item.health?.consecutiveFailures || 0}, last error: ${item.health?.lastError || 'none'}
- Geocoding result: ${item.geocode ? `${item.geocode.name} (${item.geocode.lat}, ${item.geocode.lon}), distance: ${item.geoDistance}km` : 'N/A'}
- Image captured: ${item.image ? `yes (${Math.round(item.image.size / 1024)}KB)` : 'no (fetch failed)'}
---`
    });
  }

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 4096,
      system: `Tu es un expert en analyse de webcams cotieres et meteo francaises. Tu analyses des webcams et detectes les problemes.

Pour chaque webcam analysee, reponds UNIQUEMENT en JSON valide (pas de texte avant/apres) avec cette structure:
{
  "analyses": [
    {
      "id": "webcam_id",
      "issues": [
        {
          "type": "location_mismatch|image_broken|image_mismatch|duplicate|offline_chronic|url_fix|ok",
          "severity": "high|medium|low",
          "description": "Description du probleme en francais",
          "suggestion": { "field": "value" }
        }
      ]
    }
  ]
}

Types de problemes:
- location_mismatch: Les coordonnees ne correspondent pas au lieu indique (>50km)
- image_broken: Image noire, blanche, page d'erreur, placeholder, ou aucune image
- image_mismatch: L'image ne montre pas le lieu indique (mauvaise webcam)
- offline_chronic: Webcam offline depuis longtemps (>7 jours)
- ok: Aucun probleme detecte (ne pas inclure dans les issues)

Pour chaque issue, "suggestion" contient les champs a corriger, par exemple:
- location_mismatch: { "latitude": 47.87, "longitude": -3.92 }
- image_broken: { "_hidden": true } ou { "imageUrl": "url_corrigee" }
- offline_chronic: { "_hidden": true }

Si la webcam semble correcte, mets un tableau issues vide.
Ne fabrique PAS de donnees. Si tu n'es pas sur, mets severity "low".`,
      messages: [{ role: 'user', content }]
    })
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Claude API error: ${res.status} - ${err}`);
  }

  const result = await res.json();
  const text = result.content?.[0]?.text || '';

  // Parse JSON from response (handle markdown code blocks)
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error('No JSON in Claude response');
  return JSON.parse(jsonMatch[0]);
}

// ============================================================
// MAIN HANDLER
// ============================================================

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    switch (req.method) {
      case 'GET': return await handleGet(req, res);
      case 'POST': return await handleAnalyze(req, res);
      case 'PUT': return await handleAction(req, res);
      case 'DELETE': return await handleDelete(req, res);
      default: return res.status(405).json({ error: 'Method not allowed' });
    }
  } catch (error) {
    console.error('Webcam AI error:', error);
    return res.status(500).json({ error: error.message });
  }
}

// ============================================================
// GET - Read suggestions
// ============================================================

async function handleGet(req, res) {
  const suggestions = await kv.hgetall(KV_KEY) || {};

  // Parse and sort by severity
  const parsed = Object.values(suggestions).map(s =>
    typeof s === 'string' ? JSON.parse(s) : s
  ).sort((a, b) => {
    const order = { high: 0, medium: 1, low: 2 };
    return (order[a.severity] || 2) - (order[b.severity] || 2);
  });

  return res.status(200).json({
    count: parsed.length,
    pending: parsed.filter(s => s.status === 'pending').length,
    suggestions: parsed
  });
}

// ============================================================
// POST - Run AI analysis
// ============================================================

async function handleAnalyze(req, res) {
  const { scope = 'offline' } = req.query;
  const startTime = Date.now();

  if (!ANTHROPIC_API_KEY) {
    return res.status(500).json({ error: 'ANTHROPIC_API_KEY not configured' });
  }

  // 1. Fetch data
  const [webcams, health, rejected] = await Promise.all([
    fetchWebcams(),
    getHealthStatus(),
    kv.hgetall(KV_REJECTED_KEY) || {}
  ]);

  if (!webcams.length) {
    return res.status(500).json({ error: 'Could not fetch webcams' });
  }

  // 2. Filter webcams based on scope
  let targetWebcams;
  const rejectedIds = new Set(
    Object.entries(rejected || {})
      .filter(([, v]) => {
        const r = typeof v === 'string' ? JSON.parse(v) : v;
        // Don't re-analyze rejected webcams for 30 days
        return Date.now() - new Date(r.rejectedAt).getTime() < 30 * 24 * 3600 * 1000;
      })
      .map(([id]) => id)
  );

  switch (scope) {
    case 'all':
      targetWebcams = webcams.filter(w => !rejectedIds.has(w.id));
      break;
    case 'offline':
      targetWebcams = webcams.filter(w => {
        const h = health[w.id];
        return h && !h.online && !rejectedIds.has(w.id);
      });
      break;
    case 'batch':
    default:
      // Process 20 random webcams
      const shuffled = webcams.filter(w => !rejectedIds.has(w.id)).sort(() => Math.random() - 0.5);
      targetWebcams = shuffled.slice(0, 20);
      break;
  }

  // Limit to 30 webcams per run (API cost + timeout)
  targetWebcams = targetWebcams.slice(0, 30);

  if (!targetWebcams.length) {
    return res.status(200).json({ message: 'No webcams to analyze', suggestions: 0 });
  }

  // 3. Detect duplicates (fast, no API calls)
  const duplicates = findDuplicates(webcams);

  // 4. For each webcam: geocode + capture image
  const enriched = [];
  for (const webcam of targetWebcams) {
    // Check timeout (50s max to leave room for Claude call)
    if (Date.now() - startTime > 45000) break;

    const geocodeQuery = `${webcam.location || webcam.name}, France`;
    const [geocodeResult, image] = await Promise.all([
      geocode(geocodeQuery),
      captureImage(webcam.imageUrl)
    ]);

    const geoDistance = geocodeResult
      ? Math.round(haversineKm(webcam.latitude, webcam.longitude, geocodeResult.lat, geocodeResult.lon) * 10) / 10
      : null;

    enriched.push({
      webcam,
      health: health[webcam.id] || null,
      geocode: geocodeResult,
      geoDistance,
      image
    });
  }

  // 5. Batch analyze with Claude (groups of 5)
  const allSuggestions = [];
  const batchSize = 5;

  for (let i = 0; i < enriched.length; i += batchSize) {
    if (Date.now() - startTime > 50000) break; // Safety timeout

    const batch = enriched.slice(i, i + batchSize);
    try {
      const result = await analyzeWithClaude(batch);

      if (result.analyses) {
        for (const analysis of result.analyses) {
          if (!analysis.issues?.length) continue;

          const webcam = batch.find(b => b.webcam.id === analysis.id)?.webcam;
          if (!webcam) continue;

          for (const issue of analysis.issues) {
            if (issue.type === 'ok') continue;

            allSuggestions.push({
              id: webcam.id,
              webcamName: webcam.name,
              webcamLocation: webcam.location,
              type: issue.type,
              severity: issue.severity || 'medium',
              description: issue.description,
              suggestion: issue.suggestion || {},
              currentValues: {
                latitude: webcam.latitude,
                longitude: webcam.longitude,
                imageUrl: webcam.imageUrl,
                source: webcam.source
              },
              geocodeResult: batch.find(b => b.webcam.id === analysis.id)?.geocode || null,
              aiAnalysis: issue.description,
              status: 'pending',
              createdAt: new Date().toISOString(),
              analyzedBy: MODEL
            });
          }
        }
      }
    } catch (err) {
      console.error(`Claude batch ${i / batchSize} error:`, err.message);
    }
  }

  // 6. Add duplicate suggestions (non-AI)
  for (const dupe of duplicates) {
    if (rejectedIds.has(dupe.webcam1.id) && rejectedIds.has(dupe.webcam2.id)) continue;

    allSuggestions.push({
      id: `dup_${dupe.webcam1.id}_${dupe.webcam2.id}`,
      webcamName: `${dupe.webcam1.name} / ${dupe.webcam2.name}`,
      webcamLocation: dupe.webcam1.location,
      type: 'duplicate',
      severity: 'medium',
      description: `Deux webcams a ${dupe.distance}m l'une de l'autre: "${dupe.webcam1.name}" et "${dupe.webcam2.name}"`,
      suggestion: { duplicateOf: dupe.webcam1.id, _hidden: true },
      currentValues: {
        latitude: dupe.webcam1.latitude,
        longitude: dupe.webcam1.longitude,
        webcam1: { id: dupe.webcam1.id, name: dupe.webcam1.name },
        webcam2: { id: dupe.webcam2.id, name: dupe.webcam2.name }
      },
      status: 'pending',
      createdAt: new Date().toISOString(),
      analyzedBy: 'rule-engine'
    });
  }

  // 7. Store suggestions in KV (don't overwrite existing pending ones)
  const existing = await kv.hgetall(KV_KEY) || {};
  let newCount = 0;

  for (const suggestion of allSuggestions) {
    const key = suggestion.id;
    const existingEntry = existing[key];
    if (existingEntry) {
      const parsed = typeof existingEntry === 'string' ? JSON.parse(existingEntry) : existingEntry;
      if (parsed.status === 'pending') continue; // Don't overwrite pending
    }
    await kv.hset(KV_KEY, { [key]: JSON.stringify(suggestion) });
    newCount++;
  }

  return res.status(200).json({
    analyzed: enriched.length,
    newSuggestions: newCount,
    totalSuggestions: allSuggestions.length,
    duplicatesFound: duplicates.length,
    elapsed: `${Math.round((Date.now() - startTime) / 1000)}s`
  });
}

// ============================================================
// PUT - Approve or reject a suggestion
// ============================================================

async function handleAction(req, res) {
  const { id, action } = req.query;

  if (!id || !action) {
    return res.status(400).json({ error: 'Missing id or action param' });
  }

  // Get suggestion
  const raw = await kv.hget(KV_KEY, id);
  if (!raw) {
    return res.status(404).json({ error: 'Suggestion not found' });
  }
  const suggestion = typeof raw === 'string' ? JSON.parse(raw) : raw;

  switch (action) {
    case 'approve': {
      // Apply the correction to webcam overrides
      if (suggestion.suggestion && suggestion.id && !suggestion.id.startsWith('dup_')) {
        await kv.hset('webcam_overrides', {
          [suggestion.id]: JSON.stringify(suggestion.suggestion)
        });
      } else if (suggestion.type === 'duplicate' && suggestion.suggestion?.duplicateOf) {
        // For duplicates, hide the second webcam
        const targetId = suggestion.currentValues?.webcam2?.id;
        if (targetId) {
          await kv.hset('webcam_overrides', {
            [targetId]: JSON.stringify({ _hidden: true })
          });
        }
      }

      // Remove from suggestions
      await kv.hdel(KV_KEY, id);
      return res.status(200).json({ ok: true, action: 'approved', applied: suggestion.suggestion });
    }

    case 'reject': {
      // Remove from suggestions and add to rejected list
      await kv.hdel(KV_KEY, id);
      await kv.hset(KV_REJECTED_KEY, {
        [id]: JSON.stringify({ rejectedAt: new Date().toISOString() })
      });
      return res.status(200).json({ ok: true, action: 'rejected' });
    }

    case 'dismiss': {
      // Just remove without adding to rejected
      await kv.hdel(KV_KEY, id);
      return res.status(200).json({ ok: true, action: 'dismissed' });
    }

    default:
      return res.status(400).json({ error: 'Invalid action. Use approve, reject, or dismiss' });
  }
}

// ============================================================
// DELETE - Remove a suggestion
// ============================================================

async function handleDelete(req, res) {
  const { id } = req.query;
  if (!id) return res.status(400).json({ error: 'Missing id' });
  await kv.hdel(KV_KEY, id);
  return res.status(200).json({ ok: true });
}
