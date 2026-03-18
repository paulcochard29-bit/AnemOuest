// API Key management endpoint
import { kv } from '../../lib/kv.js';
import crypto from 'crypto';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;
const KV_KEY = 'api_keys';

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

function generateKey() {
  return 'lv_' + crypto.randomBytes(24).toString('base64url');
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (!isAuthorized(req)) return res.status(401).json({ error: 'Unauthorized' });

  const action = req.query.action || 'list';

  try {
    // LIST all keys
    if (action === 'list' && req.method === 'GET') {
      const keys = await kv.hgetall(KV_KEY) || {};
      const list = Object.entries(keys).map(([id, data]) => {
        const parsed = typeof data === 'string' ? JSON.parse(data) : data;
        return { id, ...parsed, key: parsed.key.substring(0, 8) + '...' }; // mask key
      });
      return res.json({ keys: list, total: list.length });
    }

    // CREATE a new key
    if (action === 'create' && req.method === 'POST') {
      const { name, permissions, rateLimit } = req.body;
      if (!name) return res.status(400).json({ error: 'Name is required' });

      const id = crypto.randomUUID().substring(0, 8);
      const key = generateKey();
      const keyData = {
        key,
        name,
        permissions: permissions || 'read',  // read, write, admin
        rateLimit: rateLimit || 120,          // req/min
        createdAt: new Date().toISOString(),
        lastUsed: null,
        requestCount: 0,
        active: true,
      };

      await kv.hset(KV_KEY, { [id]: JSON.stringify(keyData) });
      return res.json({ id, ...keyData }); // Return full key only on creation
    }

    // UPDATE a key
    if (action === 'update' && req.method === 'PUT') {
      const { id } = req.query;
      if (!id) return res.status(400).json({ error: 'Missing id' });

      const raw = await kv.hget(KV_KEY, id);
      if (!raw) return res.status(404).json({ error: 'Key not found' });

      const existing = typeof raw === 'string' ? JSON.parse(raw) : raw;
      const { name, permissions, rateLimit, active } = req.body;

      if (name !== undefined) existing.name = name;
      if (permissions !== undefined) existing.permissions = permissions;
      if (rateLimit !== undefined) existing.rateLimit = rateLimit;
      if (active !== undefined) existing.active = active;

      await kv.hset(KV_KEY, { [id]: JSON.stringify(existing) });
      return res.json({ id, ...existing, key: existing.key.substring(0, 8) + '...' });
    }

    // DELETE a key
    if (action === 'delete' && req.method === 'DELETE') {
      const { id } = req.query;
      if (!id) return res.status(400).json({ error: 'Missing id' });
      await kv.hdel(KV_KEY, id);
      return res.json({ ok: true, deleted: id });
    }

    // STATS for a key
    if (action === 'stats' && req.method === 'GET') {
      const { id } = req.query;
      if (!id) return res.status(400).json({ error: 'Missing id' });
      const raw = await kv.hget(KV_KEY, id);
      if (!raw) return res.status(404).json({ error: 'Key not found' });
      const data = typeof raw === 'string' ? JSON.parse(raw) : raw;

      // Get usage stats from Redis
      const today = new Date().toISOString().split('T')[0];
      const todayCount = await kv.get(`apikey_usage:${id}:${today}`) || 0;

      return res.json({
        id,
        name: data.name,
        requestCount: data.requestCount,
        todayCount,
        lastUsed: data.lastUsed,
        active: data.active,
      });
    }

    return res.status(400).json({ error: 'Unknown action', valid: ['list', 'create', 'update', 'delete', 'stats'] });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
