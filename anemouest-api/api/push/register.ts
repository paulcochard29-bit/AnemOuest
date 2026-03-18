import { kv } from '../../lib/kv.js';

/**
 * POST /api/push/register
 * Register a device token for silent push notifications
 */
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { token, platform } = req.body;

    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid token' });
    }

    // Store token in Vercel KV (Redis)
    // Key: push_tokens, Value: Set of tokens
    await kv.sadd('push_tokens', JSON.stringify({
      token,
      platform: platform || 'ios',
      registeredAt: new Date().toISOString()
    }));

    console.log(`Registered push token: ${token.substring(0, 10)}...`);

    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Push registration error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
