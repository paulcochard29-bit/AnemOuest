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
    let targetTime;
    if (timestamp) {
      targetTime = new Date(parseInt(timestamp) * 1000);
    } else {
      const hoursOffset = Math.min(48, Math.max(0, parseFloat(hoursAgo) || 0));
      targetTime = new Date(Date.now() - (hoursOffset + 1) * 60 * 60 * 1000);
    }

    const year = targetTime.getUTCFullYear();
    const month = String(targetTime.getUTCMonth() + 1).padStart(2, '0');
    const day = String(targetTime.getUTCDate()).padStart(2, '0');
    const hour = String(targetTime.getUTCHours()).padStart(2, '0');
    const minute = targetTime.getUTCMinutes() < 30 ? '00' : '30';

    const subdomain = server || 'data';
    const fetchHeaders = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': 'https://www.skaping.com/',
    };

    let imageUrl;
    let imageResponse;

    // ── Strategy 1: Try S3 direct (most reliable since Skaping migration) ──
    const s3Base = `https://skaping.s3.gra.io.cloud.ovh.net/${path}/${year}/${month}/${day}`;
    try {
      const resp = await fetch(`${s3Base}/${hour}-${minute}.jpg`, { headers: fetchHeaders, signal: AbortSignal.timeout(5000) });
      if (resp.ok) { imageUrl = `${s3Base}/${hour}-${minute}.jpg`; imageResponse = resp; }
    } catch { /* continue */ }

    // Try alternate S3 slot (:00 vs :30)
    if (!imageResponse?.ok) {
      const altMinute = minute === '00' ? '30' : '00';
      try {
        const resp = await fetch(`${s3Base}/${hour}-${altMinute}.jpg`, { headers: fetchHeaders, signal: AbortSignal.timeout(5000) });
        if (resp.ok) { imageUrl = `${s3Base}/${hour}-${altMinute}.jpg`; imageResponse = resp; }
      } catch { /* continue */ }
    }

    // S3 probe nearby minutes (for cameras with irregular timestamps)
    if (!imageResponse?.ok) {
      const mins = [];
      for (let m = 1; m <= 29; m++) {
        mins.push(String(m).padStart(2, '0'));
        mins.push(String(30 + m).padStart(2, '0'));
      }
      for (let i = 0; i < mins.length && !imageResponse?.ok; i += 15) {
        const batch = mins.slice(i, i + 15);
        const results = await Promise.all(
          batch.map(async (tryMin) => {
            try {
              const r = await fetch(`${s3Base}/${hour}-${tryMin}.jpg`, { method: 'HEAD', headers: fetchHeaders, signal: AbortSignal.timeout(3000) });
              return r.ok ? tryMin : null;
            } catch { return null; }
          })
        );
        const hitMin = results.find(r => r !== null);
        if (hitMin) {
          imageUrl = `${s3Base}/${hour}-${hitMin}.jpg`;
          imageResponse = await fetch(imageUrl, { headers: fetchHeaders, signal: AbortSignal.timeout(8000) });
        }
      }
    }

    // S3 go back up to 6 hours to find the most recent image
    if (!imageResponse?.ok) {
      for (let hOffset = 1; hOffset <= 6 && !imageResponse?.ok; hOffset++) {
        const tryTime = new Date(targetTime.getTime() - hOffset * 60 * 60 * 1000);
        const tY = tryTime.getUTCFullYear();
        const tM = String(tryTime.getUTCMonth() + 1).padStart(2, '0');
        const tD = String(tryTime.getUTCDate()).padStart(2, '0');
        const tH = String(tryTime.getUTCHours()).padStart(2, '0');
        const tBase = `https://skaping.s3.gra.io.cloud.ovh.net/${path}/${tY}/${tM}/${tD}`;
        for (const m of ['00', '30']) {
          try {
            const r = await fetch(`${tBase}/${tH}-${m}.jpg`, { headers: fetchHeaders, signal: AbortSignal.timeout(3000) });
            if (r.ok) { imageUrl = `${tBase}/${tH}-${m}.jpg`; imageResponse = r; break; }
          } catch { /* continue */ }
        }
      }
    }

    // ── Strategy 2: Fallback to data/data2/data3 servers ──
    if (!imageResponse?.ok) {
      const baseUrl = `https://${subdomain}.skaping.com/${path}/${year}/${month}/${day}`;
      try {
        const resp = await fetch(`${baseUrl}/${hour}-${minute}.jpg`, { headers: fetchHeaders, redirect: 'follow', signal: AbortSignal.timeout(8000) });
        if (resp.ok) { imageUrl = `${baseUrl}/${hour}-${minute}.jpg`; imageResponse = resp; }
      } catch { /* continue */ }

      // data2/data3: probe nearby minutes
      if (!imageResponse?.ok && subdomain !== 'data') {
        const baseMin = parseInt(minute);
        const candidates = [];
        for (let offset = 1; offset < 30; offset++) {
          const m = baseMin + offset;
          if (m > 59) break;
          candidates.push(String(m).padStart(2, '0'));
        }
        for (let i = 0; i < candidates.length && !imageResponse?.ok; i += 10) {
          const batch = candidates.slice(i, i + 10);
          const results = await Promise.all(
            batch.map(async (tryMin) => {
              try {
                const r = await fetch(`${baseUrl}/${hour}-${tryMin}.jpg`, { method: 'HEAD', headers: fetchHeaders, redirect: 'follow', signal: AbortSignal.timeout(4000) });
                return r.ok ? tryMin : null;
              } catch { return null; }
            })
          );
          const hitMin = results.find(r => r !== null);
          if (hitMin) {
            imageUrl = `${baseUrl}/${hour}-${hitMin}.jpg`;
            imageResponse = await fetch(imageUrl, { headers: fetchHeaders, redirect: 'follow' });
          }
        }
      }
    }

    if (!imageResponse?.ok) {
      return res.status(404).json({
        error: 'Failed to fetch image from Skaping',
        status: imageResponse?.status || 404,
        url: imageUrl || `s3/${path}/${year}/${month}/${day}/${hour}-${minute}.jpg`
      });
    }

    const contentType = imageResponse.headers.get('content-type');
    if (!contentType || !contentType.includes('image')) {
      return res.status(502).json({ error: 'Response is not an image' });
    }

    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

    if (imageBuffer.length < 5000) {
      return res.status(404).json({ error: 'Image too small, likely unavailable' });
    }

    const metadata = await sharp(imageBuffer).metadata();
    const isPanoramic = metadata.width && metadata.height && (metadata.width > metadata.height * 2);
    const forcePanorama = panorama === 'true';

    let baseWidth, baseQuality;
    if (thumb === 'true') {
      baseWidth = (isPanoramic || forcePanorama) ? 600 : 400;
      baseQuality = (isPanoramic || forcePanorama) ? 80 : 75;
    } else {
      baseWidth = (isPanoramic || forcePanorama) ? 2400 : 1200;
      baseQuality = (isPanoramic || forcePanorama) ? 88 : 75;
    }

    const jpegQuality = Math.min(100, Math.max(10, parseInt(quality) || baseQuality));
    const maxWidth = parseInt(width) || baseWidth;

    let processedImage = sharp(imageBuffer)
      .resize(maxWidth, null, { withoutEnlargement: true, fit: 'inside' })
      .jpeg({ quality: jpegQuality, progressive: true, mozjpeg: isPanoramic || forcePanorama });

    const outputBuffer = await processedImage.toBuffer();

    let imageTimestamp = null;
    const lastModified = imageResponse.headers.get('last-modified');
    if (lastModified) {
      const parsedDate = new Date(lastModified);
      if (!isNaN(parsedDate.getTime())) imageTimestamp = Math.floor(parsedDate.getTime() / 1000);
    }
    if (!imageTimestamp) {
      imageTimestamp = Math.floor(Date.UTC(year, parseInt(month) - 1, parseInt(day), parseInt(hour), parseInt(minute), 0) / 1000);
    }

    const cacheTime = thumb === 'true' ? 600 : 300;
    const staleTime = thumb === 'true' ? 1800 : 600;
    res.setHeader('Cache-Control', `public, s-maxage=${cacheTime}, stale-while-revalidate=${staleTime}`);
    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Content-Length', outputBuffer.length);
    res.setHeader('X-Image-Timestamp', imageTimestamp.toString());
    res.setHeader('X-Panoramic', isPanoramic ? 'true' : 'false');
    res.setHeader('X-Source-Url', imageUrl);
    res.setHeader('Access-Control-Expose-Headers', 'X-Image-Timestamp, X-Panoramic, X-Source-Url');

    res.status(200).send(outputBuffer);
  } catch (error) {
    console.error('Skaping proxy error:', error);
    res.status(500).json({ error: 'Failed to process webcam image', message: error.message });
  }
}
