// KV wrapper — drop-in replacement for @vercel/kv using Redis
// API matches @vercel/kv: hget, hset, hgetall, hdel, del, sadd, smembers, get, set

import { createClient } from 'redis';

const client = createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });

client.on('error', (err) => console.error('Redis error:', err));

let connectPromise = null;
async function ensureConnected() {
  if (client.isOpen) return;
  if (!connectPromise) {
    connectPromise = client.connect().then(() => { connectPromise = null; });
  }
  await connectPromise;
}

export const kv = {
  async hget(key, field) {
    await ensureConnected();
    const val = await client.hGet(key, field);
    if (val === null || val === undefined) return null;
    try { return JSON.parse(val); } catch { return val; }
  },

  async hset(key, data) {
    await ensureConnected();
    const entries = Object.entries(data).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)]);
    if (entries.length === 0) return;
    await client.hSet(key, Object.fromEntries(entries));
  },

  async hgetall(key) {
    await ensureConnected();
    const data = await client.hGetAll(key);
    if (!data || Object.keys(data).length === 0) return null;
    const parsed = {};
    for (const [k, v] of Object.entries(data)) {
      try { parsed[k] = JSON.parse(v); } catch { parsed[k] = v; }
    }
    return parsed;
  },

  async hdel(key, ...fields) {
    await ensureConnected();
    await client.hDel(key, fields);
  },

  async del(key) {
    await ensureConnected();
    await client.del(key);
  },

  async sadd(key, ...members) {
    await ensureConnected();
    await client.sAdd(key, members);
  },

  async smembers(key) {
    await ensureConnected();
    const members = await client.sMembers(key);
    return members.map(m => { try { return JSON.parse(m); } catch { return m; } });
  },

  async get(key) {
    await ensureConnected();
    const val = await client.get(key);
    if (val === null) return null;
    try { return JSON.parse(val); } catch { return val; }
  },

  async set(key, value, options) {
    await ensureConnected();
    const serialized = typeof value === 'string' ? value : JSON.stringify(value);
    if (options?.ex) {
      await client.set(key, serialized, { EX: options.ex });
    } else {
      await client.set(key, serialized);
    }
  },
};
