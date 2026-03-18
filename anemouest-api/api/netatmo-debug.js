// Debug: test Netatmo token and API directly
import { list } from '../lib/storage.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-cache');

  const clientId = process.env.NETATMO_CLIENT_ID;
  const clientSecret = process.env.NETATMO_CLIENT_SECRET;
  const refreshToken = process.env.NETATMO_REFRESH_TOKEN;

  // Check Blob tokens
  const blobInfo = {};
  try {
    const accessBlobs = await list({ prefix: 'netatmo-token/access.json' });
    if (accessBlobs.blobs.length > 0) {
      const r = await fetch(accessBlobs.blobs[0].url);
      if (r.ok) {
        const cached = await r.json();
        blobInfo.accessTokenExpired = cached.expiresAt < Date.now();
        blobInfo.accessTokenExpiresIn = Math.round((cached.expiresAt - Date.now()) / 1000) + 's';
      }
    }
    const refreshBlobs = await list({ prefix: 'netatmo-token/refresh.txt' });
    if (refreshBlobs.blobs.length > 0) {
      const r = await fetch(refreshBlobs.blobs[0].url);
      if (r.ok) {
        const blobRefresh = (await r.text()).trim();
        blobInfo.refreshTokenPrefix = blobRefresh.slice(0, 12) + '...';
        blobInfo.refreshTokenLength = blobRefresh.length;
        blobInfo.sameAsEnv = blobRefresh === refreshToken;
      }
    }
  } catch (e) { blobInfo.error = e.message; }

  // Also try the Blob refresh token
  let blobRefreshToken = null;
  try {
    const refreshBlobs = await list({ prefix: 'netatmo-token/refresh.txt' });
    if (refreshBlobs.blobs.length > 0) {
      const r = await fetch(refreshBlobs.blobs[0].url);
      if (r.ok) blobRefreshToken = (await r.text()).trim();
    }
  } catch (e) { /* no blob */ }

  // Use query param ?useBlob=true to test Blob refresh token instead of env var
  const useToken = req.query.useBlob === 'true' && blobRefreshToken ? blobRefreshToken : refreshToken;

  const diagnostics = {
    hasClientId: !!clientId,
    hasClientSecret: !!clientSecret,
    hasRefreshToken: !!useToken,
    refreshTokenPrefix: useToken ? useToken.slice(0, 12) + '...' : null,
    refreshTokenLength: useToken ? useToken.length : 0,
    tokenSource: req.query.useBlob === 'true' ? 'blob' : 'env',
  };

  // Step 1: Try to get access token
  try {
    const tokenRes = await fetch('https://api.netatmo.com/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: useToken,
      }).toString(),
    });

    const tokenBody = await tokenRes.text();
    diagnostics.tokenStatus = tokenRes.status;
    diagnostics.tokenResponse = tokenBody.slice(0, 500);

    if (!tokenRes.ok) {
      return res.json({ step: 'token_failed', diagnostics, blobInfo });
    }

    const tokenData = JSON.parse(tokenBody);
    const accessToken = tokenData.access_token;
    diagnostics.hasAccessToken = !!accessToken;
    diagnostics.scopes = tokenData.scope;

    // Step 2: Try a simple API call (Paris area, should always have stations)
    const apiRes = await fetch('https://api.netatmo.com/api/getpublicdata', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        lat_ne: '48.9',
        lon_ne: '2.5',
        lat_sw: '48.8',
        lon_sw: '2.2',
      }).toString(),
    });

    const apiBody = await apiRes.text();
    diagnostics.apiStatus = apiRes.status;

    if (apiRes.ok) {
      const apiData = JSON.parse(apiBody);
      diagnostics.stationsInParis = (apiData.body || []).length;
      diagnostics.apiOk = true;
    } else {
      diagnostics.apiError = apiBody.slice(0, 500);
      diagnostics.apiOk = false;
    }

    return res.json({ step: 'complete', diagnostics, blobInfo });
  } catch (e) {
    diagnostics.error = e.message;
    return res.json({ step: 'exception', diagnostics, blobInfo });
  }
}
