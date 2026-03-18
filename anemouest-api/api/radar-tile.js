/**
 * GET /api/radar-tile?z={z}&x={x}&y={y}&t={ISO_timestamp}
 *
 * Proxy for Tomorrow.io precipitation map tiles with Vercel CDN caching.
 * Caches tiles for 1 hour to avoid hitting Tomorrow.io rate limits (25/hour free tier).
 * On 429 (rate limit), returns a transparent 1x1 PNG cached for 60s so the client
 * sees a valid empty tile instead of an error.
 *
 * Required env: TOMORROW_API_KEY
 */

// Minimal valid 1x1 transparent PNG (67 bytes)
const TRANSPARENT_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQAB' +
  'Nl7BcQAAAABJRU5ErkJggg==',
  'base64'
);

export default async function handler(req, res) {
  const { z, x, y, t } = req.query;

  if (!z || !x || !y || !t) {
    return res.status(400).json({ error: 'Missing parameters: z, x, y, t required' });
  }

  const apiKey = process.env.TOMORROW_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'TOMORROW_API_KEY not configured' });
  }

  try {
    const tomorrowUrl = `https://api.tomorrow.io/v4/map/tile/${z}/${x}/${y}/precipitationIntensity/${t}.png?apikey=${apiKey}`;

    const response = await fetch(tomorrowUrl);

    if (response.status === 429) {
      // Rate limited: return transparent PNG with short cache so client retries soon
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=120');
      return res.status(200).send(TRANSPARENT_PNG);
    }

    if (!response.ok) {
      // Other errors: also return transparent PNG but don't cache long
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Cache-Control', 'public, s-maxage=30, stale-while-revalidate=60');
      return res.status(200).send(TRANSPARENT_PNG);
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    res.setHeader('Content-Type', 'image/png');
    // Cache 1h on Vercel CDN, serve stale for 24h while revalidating
    res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=86400');
    res.send(buffer);
  } catch (error) {
    console.error('Radar tile proxy error:', error.message);
    // Network error: return transparent PNG
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, s-maxage=30, stale-while-revalidate=60');
    return res.status(200).send(TRANSPARENT_PNG);
  }
}
