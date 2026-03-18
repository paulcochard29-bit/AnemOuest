// Admin API for webcam management
// CRUD operations on webcam overrides stored in Vercel KV
// Protected by ADMIN_PASSWORD env var
//
// Architecture:
// - Public API (/api/webcams) is the source of truth (hardcoded + KV + QUANTEEC_STREAMS + auto-transform)
// - This admin API annotates public API data with flags (_hasOverride, _isAddition)
// - PUT strips auto-computed fields (imageUrl for HLS, streamUrl for QUANTEEC) before saving to KV

import { kv } from '../../lib/kv.js';
import { head } from '../../lib/storage.js';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const HEALTH_BLOB_PATH = 'webcam-health.json';
const API_BASE = 'http://localhost:3001/api';
const PUBLIC_API_BASE = 'https://api.levent.live/api';

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

// Fetch base webcam list from public API (already fully merged)
async function fetchBaseWebcams() {
  try {
    // Cache-bust to bypass Vercel CDN (s-maxage on public API)
    const res = await fetch(`${API_BASE}/webcams?includeAll=true&_t=${Date.now()}`, {
      cache: 'no-store',
      headers: { 'Cache-Control': 'no-cache' }
    });
    if (!res.ok) return [];
    return await res.json();
  } catch {
    return [];
  }
}

async function getHealthStatus() {
  try {
    const blobInfo = await head(HEALTH_BLOB_PATH);
    if (blobInfo) {
      const url = new URL(blobInfo.url);
      url.searchParams.set('_t', Date.now());
      const response = await fetch(url.toString(), { cache: 'no-store' });
      return await response.json();
    }
  } catch {}
  return null;
}

// Annotate public API webcams with admin flags (no re-merge)
async function getMergedWebcams(baseWebcams) {
  let merged = [...baseWebcams];

  try {
    const [overrides, additions] = await Promise.all([
      kv.hgetall('webcam_overrides'),
      kv.hgetall('webcam_additions')
    ]);

    const overrideSet = new Set(Object.keys(overrides || {}));
    const additionSet = new Set(Object.keys(additions || {}));

    merged = merged.map(w => {
      const flags = {};
      if (overrideSet.has(w.id)) flags._hasOverride = true;
      if (additionSet.has(w.id)) flags._isAddition = true;
      return Object.keys(flags).length > 0 ? { ...w, ...flags } : w;
    });
  } catch (e) {
    console.error('KV read error:', e.message);
  }

  return merged;
}

// Compute imageUrl from streamUrl for HLS webcams
function computeHlsImageUrl(id, streamUrl) {
  if (!streamUrl) return null;
  if (!streamUrl.includes('.m3u8') && !streamUrl.includes('quanteec')) return null;
  return `${PUBLIC_API_BASE}/viewsurf-stream?id=${id}&streamUrl=${encodeURIComponent(streamUrl)}`;
}

// Strip auto-computed fields, then re-derive imageUrl from streamUrl (Viewsurf only)
function prepareOverride(fields, id, baseWebcam) {
  const clean = { ...fields };
  const isViewsurf = baseWebcam?.source === 'Viewsurf';

  // Only auto-compute imageUrl for Viewsurf webcams
  if (isViewsurf) {
    const hlsImageUrl = computeHlsImageUrl(id, clean.streamUrl);
    if (hlsImageUrl) {
      clean.imageUrl = hlsImageUrl;
      return clean;
    }

    // If no streamUrl change but base uses viewsurf-stream, drop stale imageUrl
    if (baseWebcam?.imageUrl?.includes('viewsurf-stream')) {
      delete clean.imageUrl;
    }
  }

  return clean;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const baseWebcams = await fetchBaseWebcams();

    // GET requests
    if (req.method === 'GET') {
      const { action, id } = req.query;

      // Export: full merged list as JSON
      if (action === 'export') {
        const merged = await getMergedWebcams(baseWebcams);
        return res.status(200).json({
          webcams: merged.map(w => {
            const { _hasOverride, _isAddition, ...clean } = w;
            return clean;
          }),
          count: merged.length,
          exportedAt: new Date().toISOString()
        });
      }

      // Health status
      if (action === 'health') {
        const health = await getHealthStatus();
        return res.status(200).json(health || { webcams: {} });
      }

      // Raw overrides (for diffing)
      if (action === 'overrides') {
        const [overrides, additions] = await Promise.all([
          kv.hgetall('webcam_overrides'),
          kv.hgetall('webcam_additions')
        ]);
        return res.status(200).json({
          overrides: overrides || {},
          additions: additions || {}
        });
      }

      // Cleanup KV: remove obsolete imageUrl/streamUrl from overrides
      if (action === 'cleanup-kv') {
        const overrides = await kv.hgetall('webcam_overrides') || {};
        const baseMap = {};
        baseWebcams.forEach(w => { baseMap[w.id] = w; });

        const results = { cleaned: 0, removed: 0, skipped: 0, details: [] };

        for (const [id, raw] of Object.entries(overrides)) {
          const override = typeof raw === 'string' ? JSON.parse(raw) : { ...raw };
          let changed = false;

          // Skip hidden webcams
          if (override._hidden) { results.skipped++; continue; }

          const base = baseMap[id];

          // Remove obsolete imageUrl
          if (override.imageUrl) {
            if (override.imageUrl.includes('viewsurf?id=') ||
                override.imageUrl.includes('viewsurf-stream') ||
                base?.imageUrl?.includes('viewsurf-stream')) {
              delete override.imageUrl;
              changed = true;
              results.details.push({ id, field: 'imageUrl', action: 'removed' });
            }
          }

          // Remove only null streamUrl (obsolete placeholder)
          // Non-null streamUrl values are intentional admin overrides
          if ('streamUrl' in override && override.streamUrl === null) {
            delete override.streamUrl;
            changed = true;
            results.details.push({ id, field: 'streamUrl', action: 'removed' });
          }

          if (changed) {
            // Check if override is now empty (only internal flags remain)
            const remainingKeys = Object.keys(override).filter(k => !k.startsWith('_'));
            if (remainingKeys.length === 0 && !override._verified) {
              await kv.hdel('webcam_overrides', id);
              results.removed++;
              results.details.push({ id, action: 'deleted_empty_override' });
            } else {
              await kv.hset('webcam_overrides', { [id]: JSON.stringify(override) });
              results.cleaned++;
            }
          } else {
            results.skipped++;
          }
        }

        return res.status(200).json({ success: true, results });
      }

      // Single webcam
      if (id) {
        const merged = await getMergedWebcams(baseWebcams);
        const webcam = merged.find(w => w.id === id);
        if (!webcam) return res.status(404).json({ error: 'Webcam not found' });
        return res.status(200).json(webcam);
      }

      // Default: full merged list with health
      const merged = await getMergedWebcams(baseWebcams);
      const health = await getHealthStatus();
      return res.status(200).json({
        webcams: merged,
        health: health?.webcams || {},
        count: merged.length
      });
    }

    // PUT: update existing webcam
    if (req.method === 'PUT') {
      const { id } = req.query;
      if (!id) return res.status(400).json({ error: 'Missing id parameter' });

      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      if (!body || typeof body !== 'object') {
        return res.status(400).json({ error: 'Invalid body' });
      }

      // Remove internal flags
      delete body._hasOverride;
      delete body._isAddition;
      delete body.id;

      // Check if it's an addition - update directly (no stripping needed)
      const additions = await kv.hgetall('webcam_additions') || {};
      if (additions[id]) {
        const existing = typeof additions[id] === 'string' ? JSON.parse(additions[id]) : additions[id];
        const updated = { ...existing, ...body };
        await kv.hset('webcam_additions', { [id]: JSON.stringify(updated) });
        return res.status(200).json({ success: true, webcam: { id, ...updated } });
      }

      // It's a base webcam - prepare override (compute imageUrl from streamUrl)
      const baseWebcam = baseWebcams.find(w => w.id === id);
      const cleanBody = prepareOverride(body, id, baseWebcam);

      // Merge with existing override
      const existingOverrides = await kv.hgetall('webcam_overrides') || {};
      let existingOverride = existingOverrides[id]
        ? (typeof existingOverrides[id] === 'string' ? JSON.parse(existingOverrides[id]) : existingOverrides[id])
        : {};

      // Clean existing override too
      existingOverride = prepareOverride(existingOverride, id, baseWebcam);

      const merged = { ...existingOverride, ...cleanBody };

      // If nothing left to save, remove the override
      const meaningfulKeys = Object.keys(merged).filter(k => !k.startsWith('_'));
      if (meaningfulKeys.length === 0 && !merged._verified && !merged._hidden) {
        if (existingOverrides[id]) {
          await kv.hdel('webcam_overrides', id);
        }
        const result = baseWebcam || { id };
        return res.status(200).json({ success: true, webcam: result });
      }

      await kv.hset('webcam_overrides', { [id]: JSON.stringify(merged) });

      // Return the full webcam data (base + override) so frontend can update immediately
      const result = { ...(baseWebcam || {}), ...merged, id, _hasOverride: true };
      return res.status(200).json({ success: true, webcam: result });
    }

    // POST: add new webcam
    if (req.method === 'POST') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      if (!body?.id) return res.status(400).json({ error: 'Missing webcam id' });

      const merged = await getMergedWebcams(baseWebcams);
      if (merged.find(w => w.id === body.id)) {
        return res.status(409).json({ error: 'Webcam with this ID already exists' });
      }

      await kv.hset('webcam_additions', { [body.id]: JSON.stringify(body) });
      return res.status(201).json({ success: true, webcam: body });
    }

    // DELETE: remove webcam
    if (req.method === 'DELETE') {
      const { id } = req.query;
      if (!id) return res.status(400).json({ error: 'Missing id parameter' });

      const additions = await kv.hgetall('webcam_additions') || {};
      if (additions[id]) {
        await kv.hdel('webcam_additions', id);
        return res.status(200).json({ success: true, deleted: true });
      }

      await kv.hset('webcam_overrides', { [id]: JSON.stringify({ _hidden: true }) });
      return res.status(200).json({ success: true, hidden: true });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('Admin webcams error:', error);
    return res.status(500).json({ error: error.message });
  }
}
