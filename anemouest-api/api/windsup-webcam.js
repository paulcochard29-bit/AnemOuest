// WindsUp Webcam Proxy
// Fetches latest webcam image from winds-up.com
// GET /api/windsup-webcam?id={camId} → returns JPEG image
//
// Image URLs on WindsUp are dynamic (include timestamp in filename),
// so we scrape the listing page to find the current URL, then proxy the image.
// The page HTML is cached in-memory for 5 min to avoid redundant fetches.

let cachedHtml = null;
let cacheTime = 0;
const CACHE_TTL = 5 * 60 * 1000; // 5 min

async function getListingPage() {
  if (cachedHtml && Date.now() - cacheTime < CACHE_TTL) {
    return cachedHtml;
  }

  const res = await fetch('https://www.winds-up.com/webcams-spots-kitesurf-windsurf.html', {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'fr-FR,fr;q=0.9',
    },
    signal: AbortSignal.timeout(10000),
  });

  if (!res.ok) {
    throw new Error(`WindsUp page returned ${res.status}`);
  }

  cachedHtml = await res.text();
  cacheTime = Date.now();
  return cachedHtml;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Expose-Headers', 'X-Image-Timestamp');

  if (req.method === 'OPTIONS') return res.status(200).end();

  const { id } = req.query;
  if (!id) return res.status(400).json({ error: 'Missing id parameter' });

  try {
    const html = await getListingPage();

    // Find image URL: images/webcam/{id}/{id}_{timestamp}_.jpg
    const regex = new RegExp(`images/webcam/${id}/${id}_(\\d+)_\\.jpg`);
    const match = html.match(regex);

    if (!match) {
      return res.status(404).json({ error: `Webcam ${id} not found` });
    }

    const imageUrl = `https://www.winds-up.com/${match[0]}`;

    // Proxy the image
    const imgRes = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Referer': 'https://www.winds-up.com/',
        'Accept': 'image/*',
      },
      signal: AbortSignal.timeout(10000),
    });

    if (!imgRes.ok) {
      return res.status(502).json({ error: `Image fetch failed: ${imgRes.status}` });
    }

    const buffer = Buffer.from(await imgRes.arrayBuffer());

    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');
    res.setHeader('X-Image-Timestamp', match[1]);
    res.send(buffer);
  } catch (error) {
    console.error('WindsUp webcam error:', error);
    res.status(500).json({ error: 'Failed to fetch webcam image', message: error.message });
  }
}
