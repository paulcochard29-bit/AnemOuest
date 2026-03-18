// AI-powered webcam weather/conditions analysis using Claude Vision
// Detects: weather, sea state, visibility, crowd level
// Protected by ADMIN_PASSWORD

import { kv } from '../../lib/kv.js';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const API_BASE = 'http://localhost:3001/api';
const KV_KEY = 'webcam_weather_data';
const MODEL = 'claude-sonnet-4-5-20250929';

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

async function fetchWebcams() {
  try {
    const res = await fetch(`${API_BASE}/webcams?includeAll=true`);
    return res.ok ? await res.json() : [];
  } catch { return []; }
}

async function captureImage(imageUrl) {
  try {
    // Add cache buster
    const url = new URL(imageUrl);
    url.searchParams.set('_t', Date.now());

    const res = await fetch(url.toString(), {
      signal: AbortSignal.timeout(15000),
      headers: { 'User-Agent': 'AnemOuest-WeatherAI/1.0' }
    });
    if (!res.ok) return null;

    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('image')) return null;

    const buffer = Buffer.from(await res.arrayBuffer());
    if (buffer.length < 2000) return null; // Too small, probably error

    const mediaType = contentType.includes('png') ? 'image/png' : 'image/jpeg';
    return { base64: buffer.toString('base64'), mediaType, size: buffer.length };
  } catch { return null; }
}

// ============================================================
// CLAUDE VISION ANALYSIS
// ============================================================

async function analyzeWithClaude(webcamBatch) {
  if (!ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY not set');

  const content = [];

  // Add images and metadata
  for (const item of webcamBatch) {
    if (item.image) {
      content.push({
        type: 'image',
        source: { type: 'base64', media_type: item.image.mediaType, data: item.image.base64 }
      });
      content.push({
        type: 'text',
        text: `Image de la webcam "${item.webcam.name}" (ID: ${item.webcam.id}) - ${item.webcam.location}`
      });
    }
  }

  if (content.length === 0) {
    return [];
  }

  content.push({
    type: 'text',
    text: `Analyse chaque image de webcam ci-dessus et retourne un JSON array avec un objet par webcam.

Pour chaque webcam, analyse:
1. **weather**: conditions meteo visibles
   - "sunny" (ciel bleu, soleil visible)
   - "partly_cloudy" (quelques nuages)
   - "cloudy" (couvert)
   - "overcast" (tres couvert/gris)
   - "rainy" (pluie visible)
   - "foggy" (brouillard)
   - "stormy" (orage/tempete)
   - "unknown" (nuit ou impossible a determiner)

2. **sea_state**: etat de la mer (si visible)
   - "flat" (plat, pas de vagues)
   - "small" (petites vagues <0.5m)
   - "medium" (vagues moyennes 0.5-1.5m)
   - "big" (grosses vagues >1.5m)
   - "rough" (mer agitee/chaotique)
   - "not_visible" (mer non visible)

3. **visibility**: visibilite
   - "excellent" (>10km, horizon net)
   - "good" (5-10km)
   - "moderate" (1-5km, brumeux)
   - "poor" (<1km, brouillard)
   - "night" (nuit, impossible a evaluer)

4. **crowd**: affluence (si plage/spot visible)
   - "empty" (personne)
   - "few" (quelques personnes, <10)
   - "moderate" (10-50 personnes)
   - "crowded" (>50 personnes)
   - "not_visible" (plage non visible)

5. **wind_signs**: indices visuels de vent
   - "calm" (pas de mouvement visible)
   - "light" (leger mouvement vegetation/drapeaux)
   - "moderate" (mouvement net, moutons sur eau)
   - "strong" (arbres plient, spray)
   - "unknown" (pas d'indice visible)

6. **confidence**: niveau de confiance (0.0 a 1.0)

7. **notes**: observations particulieres (optionnel)

Retourne UNIQUEMENT le JSON array, pas d'explication:
[
  {
    "webcamId": "id1",
    "weather": "sunny",
    "sea_state": "medium",
    "visibility": "good",
    "crowd": "few",
    "wind_signs": "moderate",
    "confidence": 0.85,
    "notes": "Conditions ideales pour kite"
  },
  ...
]`
  });

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
      messages: [{ role: 'user', content }]
    })
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`Claude API error: ${res.status} - ${error}`);
  }

  const data = await res.json();
  const text = data.content?.[0]?.text || '';

  // Parse JSON from response
  try {
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    }
  } catch (e) {
    console.error('Failed to parse Claude response:', e, text);
  }

  return [];
}

// ============================================================
// ANALYSIS ORCHESTRATOR
// ============================================================

async function runAnalysis(webcamIds = null, limit = 10) {
  const startTime = Date.now();
  let webcams = await fetchWebcams();

  if (webcams.length === 0) {
    return { error: 'No webcams found', elapsed: '0s' };
  }

  // Filter by IDs if provided
  if (webcamIds && webcamIds.length > 0) {
    webcams = webcams.filter(w => webcamIds.includes(w.id));
  }

  // Limit batch size
  webcams = webcams.slice(0, limit);

  // Capture images in parallel
  const batch = await Promise.all(
    webcams.map(async (webcam) => {
      const image = await captureImage(webcam.imageUrl);
      return { webcam, image };
    })
  );

  // Filter out failed captures
  const validBatch = batch.filter(b => b.image);

  if (validBatch.length === 0) {
    return {
      webcamsChecked: webcams.length,
      imagesCaptures: 0,
      analyzed: 0,
      error: 'No images could be captured',
      elapsed: ((Date.now() - startTime) / 1000).toFixed(1) + 's'
    };
  }

  // Analyze with Claude
  const results = await analyzeWithClaude(validBatch);

  // Map results back to webcam IDs and save
  const timestamp = new Date().toISOString();
  const toSave = {};

  for (let i = 0; i < validBatch.length; i++) {
    const webcam = validBatch[i].webcam;
    const analysis = results.find(r => r.webcamId === webcam.id) || results[i];

    if (analysis) {
      toSave[webcam.id] = JSON.stringify({
        webcamId: webcam.id,
        webcamName: webcam.name,
        location: webcam.location,
        ...analysis,
        analyzedAt: timestamp
      });
    }
  }

  if (Object.keys(toSave).length > 0) {
    await kv.hset(KV_KEY, toSave);
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1) + 's';
  return {
    webcamsChecked: webcams.length,
    imagesCaptured: validBatch.length,
    analyzed: results.length,
    elapsed
  };
}

// ============================================================
// HANDLER
// ============================================================

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // GET - Get weather data
    if (req.method === 'GET') {
      const { id, stats } = req.query;

      // Stats summary
      if (stats === 'true') {
        const data = await kv.hgetall(KV_KEY) || {};
        const parsed = Object.values(data).map(d => typeof d === 'string' ? JSON.parse(d) : d);

        const summary = {
          total: parsed.length,
          byWeather: {},
          bySeaState: {},
          byVisibility: {},
          byCrowd: {},
          avgConfidence: 0
        };

        for (const p of parsed) {
          summary.byWeather[p.weather] = (summary.byWeather[p.weather] || 0) + 1;
          summary.bySeaState[p.sea_state] = (summary.bySeaState[p.sea_state] || 0) + 1;
          summary.byVisibility[p.visibility] = (summary.byVisibility[p.visibility] || 0) + 1;
          summary.byCrowd[p.crowd] = (summary.byCrowd[p.crowd] || 0) + 1;
          summary.avgConfidence += p.confidence || 0;
        }

        if (parsed.length > 0) {
          summary.avgConfidence = Math.round((summary.avgConfidence / parsed.length) * 100) / 100;
        }

        return res.json(summary);
      }

      // Single webcam data
      if (id) {
        const data = await kv.hget(KV_KEY, id);
        if (!data) {
          return res.status(404).json({ error: 'No weather data for this webcam' });
        }
        return res.json(typeof data === 'string' ? JSON.parse(data) : data);
      }

      // All data
      const data = await kv.hgetall(KV_KEY) || {};
      const parsed = Object.values(data).map(d => typeof d === 'string' ? JSON.parse(d) : d);

      // Sort by most recent
      parsed.sort((a, b) => new Date(b.analyzedAt) - new Date(a.analyzedAt));

      return res.json({ data: parsed, count: parsed.length });
    }

    // POST - Run analysis
    if (req.method === 'POST') {
      const { ids, limit = 10 } = req.query;
      const webcamIds = ids ? ids.split(',') : null;
      const result = await runAnalysis(webcamIds, parseInt(limit));
      return res.json(result);
    }

    // DELETE - Clear data
    if (req.method === 'DELETE') {
      const { id } = req.query;
      if (id) {
        await kv.hdel(KV_KEY, id);
        return res.json({ success: true, deleted: id });
      }
      await kv.del(KV_KEY);
      return res.json({ success: true, cleared: 'all' });
    }

    return res.status(405).json({ error: 'Method not allowed' });

  } catch (e) {
    console.error('Webcam Weather AI error:', e);
    return res.status(500).json({ error: e.message });
  }
}
