// Skaping Webcam Proxy with Image Compression
// Fetches, compresses, and serves images from Skaping webcams

import sharp from 'sharp';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { path, quality, width, thumb, hoursAgo, server, panorama, timestamp } = req.query;

  if (!path) {
    return res.status(400).json({ error: 'Missing path parameter' });
  }

  try {
    // Calculate timestamp for Skaping URL
    // Skaping webcams update at :00 and :30 intervals
    let targetTime;
    if (timestamp) {
      // Direct Unix timestamp provided
      targetTime = new Date(parseInt(timestamp) * 1000);
    } else {
      // hoursAgo provided
      const hoursOffset = Math.min(48, Math.max(0, parseFloat(hoursAgo) || 0));
      targetTime = new Date(Date.now() - (hoursOffset + 1) * 60 * 60 * 1000); // 1h buffer
    }

    const year = targetTime.getUTCFullYear();
    const month = String(targetTime.getUTCMonth() + 1).padStart(2, '0');
    const day = String(targetTime.getUTCDate()).padStart(2, '0');
    const hour = String(targetTime.getUTCHours()).padStart(2, '0');
    const minute = targetTime.getUTCMinutes() < 30 ? '00' : '30';

    // Build the Skaping URL (supports data, data2, data3 subdomains + S3 storage)
    const subdomain = server || 'data';
    const isS3 = subdomain === 's3';
    const fetchHeaders = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': 'https://www.skaping.com/',
    };

    let imageUrl;
    let imageResponse;

    if (isS3) {
      // S3 OVH storage: skaping.s3.gra.io.cloud.ovh.net/{path}/{YYYY}/{MM}/{DD}/{HH}-{MM}.jpg
      const s3Base = `https://skaping.s3.gra.io.cloud.ovh.net/${path}/${year}/${month}/${day}`;
      imageUrl = `${s3Base}/${hour}-${minute}.jpg`;
      imageResponse = await fetch(imageUrl, { headers: fetchHeaders, signal: AbortSignal.timeout(8000) });

      // S3 cameras: try :00/:30 slots, then nearby minutes (for solar cameras)
      if (!imageResponse.ok) {
        let found = false;
        // Try going back up to 6 hours to find the most recent available image
        for (let hOffset = 0; hOffset <= 6 && !found; hOffset++) {
          const tryTime = new Date(targetTime.getTime() - hOffset * 60 * 60 * 1000);
          const tY = tryTime.getUTCFullYear();
          const tM = String(tryTime.getUTCMonth() + 1).padStart(2, '0');
          const tD = String(tryTime.getUTCDate()).padStart(2, '0');
          const tH = String(tryTime.getUTCHours()).padStart(2, '0');
          const tBase = `https://skaping.s3.gra.io.cloud.ovh.net/${path}/${tY}/${tM}/${tD}`;

          // First try standard :00/:30 slots
          for (const m of ['30', '00']) {
            if (hOffset === 0 && m === minute) continue;
            try {
              const r = await fetch(`${tBase}/${tH}-${m}.jpg`, { method: 'HEAD', headers: fetchHeaders, signal: AbortSignal.timeout(3000) });
              if (r.ok) {
                imageUrl = `${tBase}/${tH}-${m}.jpg`;
                imageResponse = await fetch(imageUrl, { headers: fetchHeaders, signal: AbortSignal.timeout(8000) });
                found = true; break;
              }
            } catch { /* continue */ }
          }

          // Then probe nearby minutes in parallel (solar cameras use irregular timestamps)
          if (!found) {
            const mins = [];
            for (let m = 1; m <= 29; m++) {
              mins.push(String(m).padStart(2, '0'));
              mins.push(String(30 + m).padStart(2, '0'));
            }
            for (let i = 0; i < mins.length && !found; i += 15) {
              const batch = mins.slice(i, i + 15);
              const results = await Promise.all(
                batch.map(async (tryMin) => {
                  try {
                    const r = await fetch(`${tBase}/${tH}-${tryMin}.jpg`, { method: 'HEAD', headers: fetchHeaders, signal: AbortSignal.timeout(3000) });
                    return r.ok ? tryMin : null;
                  } catch { return null; }
                })
              );
              const hitMin = results.find(r => r !== null);
              if (hitMin) {
                imageUrl = `${tBase}/${tH}-${hitMin}.jpg`;
                imageResponse = await fetch(imageUrl, { headers: fetchHeaders, signal: AbortSignal.timeout(8000) });
                found = true;
              }
            }
          }
        }
      }
    } else {
      // Standard data/data2/data3 servers
      const baseUrl = `https://${subdomain}.skaping.com/${path}/${year}/${month}/${day}`;
      imageUrl = `${baseUrl}/${hour}-${minute}.jpg`;
      imageResponse = await fetch(imageUrl, { headers: fetchHeaders, redirect: 'follow' });

      // Some Skaping servers (data3) use per-minute timestamps instead of :00/:30
      // If standard timestamp fails, probe nearby minutes in parallel batches
      if (!imageResponse.ok && subdomain !== 'data') {
        const baseMin = parseInt(minute);
        const candidates = [];
        for (let offset = 1; offset < 30; offset++) {
          const m = baseMin + offset;
          if (m > 59) break;
          candidates.push(String(m).padStart(2, '0'));
        }
        let found = false;
        for (let i = 0; i < candidates.length && !found; i += 10) {
          const batch = candidates.slice(i, i + 10);
          const results = await Promise.all(
            batch.map(async (tryMin) => {
              const tryUrl = `${baseUrl}/${hour}-${tryMin}.jpg`;
              try {
                const r = await fetch(tryUrl, { method: 'HEAD', headers: fetchHeaders, redirect: 'follow', signal: AbortSignal.timeout(4000) });
                return r.ok ? tryMin : null;
              } catch { return null; }
            })
          );
          const hitMin = results.find(r => r !== null);
          if (hitMin) {
            imageUrl = `${baseUrl}/${hour}-${hitMin}.jpg`;
            imageResponse = await fetch(imageUrl, { headers: fetchHeaders, redirect: 'follow' });
            found = true;
          }
        }
      }

      // Fallback: if data/data3 servers redirect to S3 and fail, try S3 directly
      if (!imageResponse.ok) {
        const s3Url = `https://skaping.s3.gra.io.cloud.ovh.net/${path}/${year}/${month}/${day}/${hour}-${minute}.jpg`;
        try {
          const s3Resp = await fetch(s3Url, { headers: fetchHeaders, signal: AbortSignal.timeout(5000) });
          if (s3Resp.ok) {
            imageUrl = s3Url;
            imageResponse = s3Resp;
          }
        } catch { /* keep original error */ }
      }
    }

    if (!imageResponse.ok) {
      return res.status(imageResponse.status).json({
        error: 'Failed to fetch image from Skaping',
        status: imageResponse.status,
        url: imageUrl
      });
    }

    const contentType = imageResponse.headers.get('content-type');
    if (!contentType || !contentType.includes('image')) {
      return res.status(502).json({ error: 'Response is not an image' });
    }

    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

    // Skip very small images (likely error placeholders)
    if (imageBuffer.length < 5000) {
      return res.status(404).json({ error: 'Image too small, likely unavailable' });
    }

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

    // Get the real image timestamp - prefer Last-Modified header, fallback to URL calculation
    let imageTimestamp = null;
    const lastModified = imageResponse.headers.get('last-modified');
    if (lastModified) {
      const parsedDate = new Date(lastModified);
      if (!isNaN(parsedDate.getTime())) {
        imageTimestamp = Math.floor(parsedDate.getTime() / 1000);
      }
    }
    // Fallback: calculate from URL components (less reliable if server returns cached/different image)
    if (!imageTimestamp) {
      imageTimestamp = Math.floor(Date.UTC(year, parseInt(month) - 1, parseInt(day), parseInt(hour), parseInt(minute), 0) / 1000);
    }

    // Set cache headers - longer cache for thumbnails (10 min), shorter for full images (5 min)
    // Skaping updates every 30min, so we can safely cache longer
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
    res.setHeader('X-Image-Timestamp', imageTimestamp.toString());
    res.setHeader('X-Cache-TTL', cacheTime.toString());
    res.setHeader('X-Panoramic', isPanoramic ? 'true' : 'false');
    res.setHeader('X-Original-Width', metadata.width?.toString() || '0');
    res.setHeader('X-Original-Height', metadata.height?.toString() || '0');
    res.setHeader('Access-Control-Expose-Headers', 'X-Image-Timestamp, X-Cache-TTL, X-Panoramic, X-Original-Width, X-Original-Height');

    res.status(200).send(outputBuffer);
  } catch (error) {
    console.error('Skaping proxy error:', error);
    res.status(500).json({ error: 'Failed to process webcam image', message: error.message });
  }
}
