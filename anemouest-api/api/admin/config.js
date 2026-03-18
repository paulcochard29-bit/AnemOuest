// Admin API for app configuration and spot management
// Stores kite spots, surf spots, and app config in Vercel KV
// Protected by ADMIN_PASSWORD env var

import { kv } from '../../lib/kv.js';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;

const VALID_TYPES = ['kite_spots', 'surf_spots', 'app_config', 'wind_stations_config'];

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { type, id } = req.query;

  if (!type || !VALID_TYPES.includes(type)) {
    return res.status(400).json({ error: 'Invalid type', validTypes: VALID_TYPES });
  }

  try {
    // GET - Read data
    if (req.method === 'GET') {
      const data = await kv.get(type);
      return res.status(200).json({
        type,
        data: data || (type === 'app_config' || type === 'wind_stations_config' ? {} : []),
        updatedAt: await kv.get(`${type}_updated_at`)
      });
    }

    // PUT - Write data (full replace or single item update)
    if (req.method === 'PUT') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;

      if (type === 'app_config' || type === 'wind_stations_config') {
        // Config objects: merge with existing
        const existing = (await kv.get(type)) || {};
        const merged = { ...existing, ...body };
        await kv.set(type, merged);
        await kv.set(`${type}_updated_at`, new Date().toISOString());
        return res.status(200).json({ success: true, data: merged });
      }

      // Spot arrays: if id is provided, update single spot; otherwise replace all
      if (id) {
        const spots = (await kv.get(type)) || [];
        const idx = spots.findIndex(s => s.id === id);
        if (idx === -1) {
          // Add new spot
          spots.push({ ...body, id });
        } else {
          // Update existing
          spots[idx] = { ...spots[idx], ...body };
        }
        await kv.set(type, spots);
        await kv.set(`${type}_updated_at`, new Date().toISOString());
        return res.status(200).json({ success: true, spot: spots[idx !== -1 ? idx : spots.length - 1] });
      }

      // Replace entire array
      if (!Array.isArray(body)) {
        return res.status(400).json({ error: 'Expected array for spot data' });
      }
      await kv.set(type, body);
      await kv.set(`${type}_updated_at`, new Date().toISOString());
      return res.status(200).json({ success: true, count: body.length });
    }

    // DELETE - Remove single spot by id
    if (req.method === 'DELETE') {
      if (!id) return res.status(400).json({ error: 'Missing id parameter' });

      const spots = (await kv.get(type)) || [];
      const filtered = spots.filter(s => s.id !== id);
      if (filtered.length === spots.length) {
        return res.status(404).json({ error: 'Spot not found' });
      }
      await kv.set(type, filtered);
      await kv.set(`${type}_updated_at`, new Date().toISOString());
      return res.status(200).json({ success: true, deleted: id });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('Admin config error:', error);
    return res.status(500).json({ error: error.message });
  }
}
