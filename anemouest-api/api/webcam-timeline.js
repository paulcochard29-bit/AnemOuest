// Webcam Timeline API
// Returns available timestamps for a webcam's history (up to 48h)
// Supports: Vision-Env (Blob), Viewsurf (HTML parsing), Skaping (30min intervals)

import { list } from '../lib/storage.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { source, id, slug, path, server } = req.query;

  if (!source) {
    return res.status(400).json({ error: 'Missing source parameter' });
  }

  try {
    let timestamps = [];

    const normalizedSource = source.toLowerCase().replace(/-/g, '');

    switch (normalizedSource) {
      case 'visionenv':
      case 'visionenvironnement':
        if (!id) {
          return res.status(400).json({ error: 'Missing id parameter for vision-env' });
        }
        timestamps = await getBlobTimestamps(id);
        break;

      case 'viewsurf':
        if (!id) {
          return res.status(400).json({ error: 'Missing id parameter for viewsurf' });
        }
        // Check Blob storage first (works for all HLS-captured webcams)
        timestamps = await getBlobTimestamps(id);
        if (timestamps.length === 0) {
          // Fallback to HTML parsing (only works for numeric Viewsurf IDs)
          timestamps = await getViewsurfTimestamps(id, slug);
        }
        break;

      case 'skaping':
        if (!path) {
          return res.status(400).json({ error: 'Missing path parameter for skaping' });
        }
        timestamps = await getSkapingTimestamps(path, server);
        break;

      // WindsUp webcams: captured by cron, stored in Blob
      case 'windsup':
      // Diabox webcams: captured by cron, stored in Blob
      case 'diabox':
      // YouTube webcams: captured by cron, stored in Blob
      case 'youtube':
      // Generic blob lookup for any HLS-captured webcam
      case 'blob':
      case 'hls':
        if (!id) {
          return res.status(400).json({ error: 'Missing id parameter' });
        }
        timestamps = await getBlobTimestamps(id);
        break;

      default:
        // Try blob storage as fallback for unknown sources
        if (id) {
          timestamps = await getBlobTimestamps(id);
          if (timestamps.length === 0) {
            return res.status(400).json({ error: `Unsupported source: ${source}` });
          }
        } else {
          return res.status(400).json({ error: `Unsupported source: ${source}` });
        }
    }

    // Sort by timestamp descending (most recent first)
    timestamps.sort((a, b) => b.timestamp - a.timestamp);

    // Cache for 5 minutes
    res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');

    res.status(200).json({
      source,
      count: timestamps.length,
      timestamps
    });
  } catch (error) {
    console.error('Webcam timeline error:', error);
    res.status(500).json({ error: 'Failed to fetch timeline', message: error.message });
  }
}

// Fetch timestamps from Vercel Blob storage (for any HLS-captured webcam)
async function getBlobTimestamps(webcamId) {
  try {
    const { blobs } = await list({
      prefix: `webcams/${webcamId}/`,
      limit: 200, // ~48h at 30min intervals = 96 images
    });

    if (!blobs || blobs.length === 0) {
      return [];
    }

    // Parse timestamps from blob paths: webcams/{id}/{timestamp}.jpg
    return blobs
      .map(blob => {
        const match = blob.pathname.match(/\/(\d+)\.jpg$/);
        if (match) {
          const ts = parseInt(match[1]);
          return {
            timestamp: ts,
            url: blob.url,
            size: blob.size
          };
        }
        return null;
      })
      .filter(Boolean);
  } catch (error) {
    console.error('Blob timeline error:', error);
    return [];
  }
}

// Viewsurf: parse timestamps from HTML page
async function getViewsurfTimestamps(id, slug) {
  try {
    const pageUrl = `https://www.viewsurf.com/univers/plage/vue/${id}${slug ? `-${slug}` : ''}`;

    const response = await fetch(pageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
        'Referer': 'https://www.viewsurf.com/',
      },
    });

    if (!response.ok) {
      console.log(`Viewsurf page fetch failed: ${response.status} for ${pageUrl}`);
      return [];
    }

    const html = await response.text();
    console.log(`Viewsurf page size: ${html.length} bytes for id=${id}`);

    // Extract ALL image URLs from the page (they span ~48h)
    // Format: media_{timestamp}_tncrop.jpg or media_{timestamp}_tn.jpg
    const imageRegex = /https:\/\/filmssite\.viewsurf\.com\/[^"]+_tn(?:crop)?\.jpg/g;
    const allMatches = html.match(imageRegex);

    console.log(`Viewsurf matches found: ${allMatches?.length || 0}`);

    if (!allMatches || allMatches.length === 0) {
      return [];
    }

    // Filter to only this camera's images
    const slugMatch = allMatches[0].match(/filmssite\.viewsurf\.com\/([^/]+)\//);
    const cameraSlug = slugMatch ? slugMatch[1] : null;
    const matches = cameraSlug
      ? allMatches.filter(url => url.includes(`/${cameraSlug}/`))
      : allMatches;

    // Parse timestamps and deduplicate
    const seen = new Set();
    const timestamps = [];

    for (const url of matches) {
      const match = url.match(/media_(\d+)_tn(?:crop)?\.jpg/);
      if (match) {
        const ts = parseInt(match[1]);
        if (!seen.has(ts)) {
          seen.add(ts);
          // Build full-size URL
          const fullUrl = url.replace(/_tn(?:crop)?\.jpg$/, '.jpg');
          timestamps.push({
            timestamp: ts,
            url: fullUrl
          });
        }
      }
    }

    return timestamps;
  } catch (error) {
    console.error('Viewsurf timeline error:', error);
    return [];
  }
}

// Skaping: generate 30-minute interval timestamps for last 48h
async function getSkapingTimestamps(webcamPath, server = 'data') {
  const timestamps = [];
  const now = Date.now();
  const subdomain = server || 'data';

  // Generate timestamps for last 48 hours at 30-minute intervals
  // Skaping uses UTC time in path: /{path}/{year}/{month}/{day}/{hour}-{minute}.jpg
  for (let hoursAgo = 1; hoursAgo <= 48; hoursAgo += 0.5) {
    const targetTime = new Date(now - hoursAgo * 60 * 60 * 1000);

    const year = targetTime.getUTCFullYear();
    const month = String(targetTime.getUTCMonth() + 1).padStart(2, '0');
    const day = String(targetTime.getUTCDate()).padStart(2, '0');
    const hour = String(targetTime.getUTCHours()).padStart(2, '0');
    const minute = targetTime.getUTCMinutes() < 30 ? '00' : '30';

    const ts = Math.floor(Date.UTC(year, targetTime.getUTCMonth(), parseInt(day), parseInt(hour), parseInt(minute), 0) / 1000);

    timestamps.push({
      timestamp: ts,
      url: `https://${subdomain}.skaping.com/${webcamPath}/${year}/${month}/${day}/${hour}-${minute}.jpg`,
      estimated: true // These are estimated, not guaranteed to exist
    });
  }

  return timestamps;
}
