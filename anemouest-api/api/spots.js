// Public Spots API
// Serves kite and surf spots from Vercel KV
// GET /api/spots?type=kite|surf

import { kv } from '../lib/kv.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');

  if (req.method === 'OPTIONS') return res.status(200).end();

  const { type } = req.query;

  try {
    if (type === 'kite') {
      const spots = (await kv.get('kite_spots')) || [];
      return res.status(200).json(spots);
    }

    if (type === 'surf') {
      const spots = (await kv.get('surf_spots')) || [];
      return res.status(200).json(spots);
    }

    if (type === 'config') {
      const config = (await kv.get('app_config')) || {};
      return res.status(200).json(config);
    }

    // Return both
    const [kite, surf] = await Promise.all([
      kv.get('kite_spots'),
      kv.get('surf_spots')
    ]);

    return res.status(200).json({
      kite: kite || [],
      surf: surf || [],
      kiteCount: (kite || []).length,
      surfCount: (surf || []).length
    });
  } catch (error) {
    console.error('Spots API error:', error);
    return res.status(500).json({ error: error.message });
  }
}
