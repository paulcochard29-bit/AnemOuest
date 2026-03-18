// One-time token initializer
// Usage: GET /api/netatmo-init?token=YOUR_REFRESH_TOKEN
// Tests the token, saves it to Blob, and does a test API call

import { put } from '../lib/storage.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-cache');

  const refreshToken = req.query.token;
  if (!refreshToken) {
    return res.status(400).json({ error: 'Pass ?token=YOUR_REFRESH_TOKEN' });
  }

  const clientId = process.env.NETATMO_CLIENT_ID;
  const clientSecret = process.env.NETATMO_CLIENT_SECRET;

  try {
    // Step 1: Exchange refresh token for access token
    const tokenRes = await fetch('https://api.netatmo.com/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
      }).toString(),
    });

    const tokenData = await tokenRes.json();

    if (!tokenRes.ok) {
      return res.json({ step: 'token_failed', status: tokenRes.status, error: tokenData });
    }

    // Step 2: Save new refresh token AND access token to Blob
    const newRefreshToken = tokenData.refresh_token;
    const now = Date.now();
    await Promise.all([
      put('netatmo-token/refresh.txt', newRefreshToken, {
        access: 'public', addRandomSuffix: false, contentType: 'text/plain',
      }),
      put('netatmo-token/access.json', JSON.stringify({
        accessToken: tokenData.access_token,
        expiresAt: now + (tokenData.expires_in || 10800) * 1000,
      }), {
        access: 'public', addRandomSuffix: false, contentType: 'application/json',
      }),
    ]);

    // Step 3: Test API call (small area in Paris)
    const apiRes = await fetch('https://api.netatmo.com/api/getpublicdata', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenData.access_token}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        lat_ne: '48.9', lon_ne: '2.5',
        lat_sw: '48.8', lon_sw: '2.2',
      }).toString(),
    });

    const apiData = await apiRes.json();

    return res.json({
      status: 'ok',
      tokenSaved: true,
      newRefreshTokenPrefix: newRefreshToken.slice(0, 12) + '...',
      testStations: (apiData.body || []).length,
      message: 'Token saved to Blob. You can now run the scan.',
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
