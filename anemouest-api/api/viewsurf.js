// Viewsurf Webcam Proxy with Image Compression
// Fetches, compresses, and serves images from Viewsurf webcams with history support

import sharp from 'sharp';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { id, slug, hoursAgo, quality, width, thumb, panorama, timestamp } = req.query;

  if (!id) {
    return res.status(400).json({ error: 'Missing id parameter' });
  }

  try {
    // Fetch the Viewsurf webcam page
    const pageUrl = `https://www.viewsurf.com/univers/plage/vue/${id}${slug ? `-${slug}` : ''}`;
    const response = await fetch(pageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
      },
    });

    if (!response.ok) {
      return res.status(404).json({ error: 'Webcam not found' });
    }

    const html = await response.text();

    // Extract ALL image URLs from the page (they span ~48h)
    // Format: media_{timestamp}_tncrop.jpg or media_{timestamp}_tn.jpg
    const imageRegex = /https:\/\/filmssite\.viewsurf\.com\/[^"]+_tn(?:crop)?\.jpg/g;
    const allMatches = html.match(imageRegex);

    if (!allMatches || allMatches.length === 0) {
      return res.status(404).json({ error: 'No images found' });
    }

    // Filter to only this camera's images (pages include "Autres vues" from other cameras)
    // Extract camera slug from first match: https://filmssite.viewsurf.com/{slug}/...
    const slugMatch = allMatches[0].match(/filmssite\.viewsurf\.com\/([^/]+)\//);
    const cameraSlug = slugMatch ? slugMatch[1] : null;
    const matches = cameraSlug
      ? allMatches.filter(url => url.includes(`/${cameraSlug}/`))
      : allMatches;

    // Parse hoursAgo or timestamp parameter
    const hours = Math.min(48, Math.max(0, parseFloat(hoursAgo) || 0));
    const targetTimestamp = timestamp ? parseInt(timestamp) : null;

    let selectedUrl;
    if (targetTimestamp || hours > 0) {
      // Find image closest to requested time
      const targetTime = targetTimestamp ? targetTimestamp * 1000 : Date.now() - (hours * 60 * 60 * 1000);

      // Parse timestamps from URLs (format: media_{timestamp}_tncrop.jpg or _tn.jpg)
      const urlsWithTime = matches.map(url => {
        const match = url.match(/media_(\d+)_tn(?:crop)?\.jpg/);
        return {
          url,
          timestamp: match ? parseInt(match[1]) * 1000 : 0
        };
      }).filter(u => u.timestamp > 0);

      // Sort by timestamp
      urlsWithTime.sort((a, b) => a.timestamp - b.timestamp);

      // Find closest to target
      let closest = urlsWithTime[0];
      for (const item of urlsWithTime) {
        if (Math.abs(item.timestamp - targetTime) < Math.abs(closest.timestamp - targetTime)) {
          closest = item;
        }
      }

      selectedUrl = closest ? closest.url : matches[matches.length - 1];
    } else {
      // Get the most recent image (last in list)
      selectedUrl = matches[matches.length - 1];
    }

    // Remove _tn or _tncrop for full size
    const fullSizeUrl = selectedUrl.replace(/_tn(?:crop)?\.jpg$/, '.jpg');

    // Fetch the actual image
    const imageResponse = await fetch(fullSizeUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'image/*',
        'Referer': 'https://www.viewsurf.com/',
      },
    });

    if (!imageResponse.ok) {
      return res.status(502).json({ error: 'Failed to fetch image from source' });
    }

    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

    // Get image metadata to detect panoramic images
    const metadata = await sharp(imageBuffer).metadata();
    const isPanoramic = metadata.width && metadata.height && (metadata.width > metadata.height * 2);
    const forcePanorama = panorama === 'true';

    // Configure compression settings
    // Panoramic images get higher resolution and quality to preserve detail
    let baseWidth, baseQuality;
    if (thumb === 'true') {
      // Thumbnails: 400px normal, 600px panorama (for map markers)
      baseWidth = (isPanoramic || forcePanorama) ? 600 : 400;
      baseQuality = (isPanoramic || forcePanorama) ? 80 : 75;
    } else {
      // Full images: 1200px normal, 2400px panorama
      baseWidth = (isPanoramic || forcePanorama) ? 2400 : 1200;
      baseQuality = (isPanoramic || forcePanorama) ? 88 : 75;
    }

    const jpegQuality = Math.min(100, Math.max(10, parseInt(quality) || baseQuality));
    const maxWidth = parseInt(width) || baseWidth;

    // Process image with sharp
    let processedImage = sharp(imageBuffer)
      .resize(maxWidth, null, {
        withoutEnlargement: true,
        fit: 'inside',
      })
      .jpeg({
        quality: jpegQuality,
        progressive: true,
        mozjpeg: isPanoramic || forcePanorama, // Better compression for panoramas
      });

    const outputBuffer = await processedImage.toBuffer();

    // Extract timestamp from the selected URL (format: media_{timestamp}_tn.jpg or media_{timestamp}.jpg)
    let imageTimestamp = null;
    const timestampMatch = selectedUrl.match(/media_(\d+)(?:_tn(?:crop)?)?\.jpg/i);
    if (timestampMatch) {
      imageTimestamp = parseInt(timestampMatch[1]);
    }
    // Fallback: try Last-Modified header from image response
    if (!imageTimestamp) {
      const lastModified = imageResponse.headers.get('last-modified');
      if (lastModified) {
        const parsedDate = new Date(lastModified);
        if (!isNaN(parsedDate.getTime())) {
          imageTimestamp = Math.floor(parsedDate.getTime() / 1000);
        }
      }
    }

    // Set cache headers - longer cache for thumbnails (10 min), shorter for full images (5 min)
    const cacheTime = thumb === 'true' ? 600 : 300;
    const staleTime = thumb === 'true' ? 1800 : 600;
    res.setHeader('Cache-Control', `public, s-maxage=${cacheTime}, stale-while-revalidate=${staleTime}`);
    res.setHeader('CDN-Cache-Control', `public, max-age=${cacheTime}`);
    res.setHeader('Vercel-CDN-Cache-Control', `public, max-age=${cacheTime}`);
    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Content-Length', outputBuffer.length);
    res.setHeader('X-Original-Size', imageBuffer.length);
    res.setHeader('X-Compressed-Size', outputBuffer.length);
    res.setHeader('X-Compression-Ratio', (imageBuffer.length / outputBuffer.length).toFixed(2));
    // Only set timestamp if we have a real one
    if (imageTimestamp) {
      res.setHeader('X-Image-Timestamp', imageTimestamp.toString());
    }
    res.setHeader('X-Cache-TTL', cacheTime.toString());
    res.setHeader('X-Panoramic', isPanoramic ? 'true' : 'false');
    res.setHeader('X-Original-Width', metadata.width?.toString() || '0');
    res.setHeader('X-Original-Height', metadata.height?.toString() || '0');
    res.setHeader('Access-Control-Expose-Headers', 'X-Image-Timestamp, X-Cache-TTL, X-Panoramic, X-Original-Width, X-Original-Height');

    res.status(200).send(outputBuffer);
  } catch (error) {
    console.error('Viewsurf proxy error:', error);
    res.status(500).json({ error: 'Failed to process webcam image', message: error.message });
  }
}
