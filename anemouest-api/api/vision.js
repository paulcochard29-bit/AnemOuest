// Vision-Environnement Webcam Proxy with Image Compression
// Fetches, compresses, and serves images from Vision-Environnement webcams
// Supports history via Vercel Blob storage (captured by webcam-cron)

import sharp from 'sharp';
import { list } from '../lib/storage.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { slug, id, quality, width, thumb, hoursAgo, panorama, timestamp } = req.query;

  if (!slug) {
    return res.status(400).json({ error: 'Missing slug parameter' });
  }

  // Parse hoursAgo parameter for history support (0-48 hours)
  const hours = Math.min(48, Math.max(0, parseFloat(hoursAgo) || 0));

  // Parse timestamp parameter (Unix timestamp in seconds)
  const targetTimestamp = timestamp ? parseInt(timestamp) : null;

  try {
    // If timestamp or hoursAgo is specified, try to fetch from Blob storage first
    if ((targetTimestamp || hours > 0) && id) {
      const forcePanorama = panorama === 'true';
      const blobResult = await fetchFromBlobHistory(id, targetTimestamp || hours, parseInt(quality) || 75, thumb === 'true' ? 400 : (parseInt(width) || 1200), forcePanorama, !!targetTimestamp);
      if (blobResult) {
        res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=7200');
        res.setHeader('Content-Type', 'image/jpeg');
        res.setHeader('Content-Length', blobResult.buffer.length);
        res.setHeader('X-Source', 'blob-history');
        res.setHeader('X-Image-Timestamp', blobResult.timestamp.toString());
        res.setHeader('X-Panoramic', blobResult.isPanoramic ? 'true' : 'false');
        res.setHeader('X-Original-Width', blobResult.originalWidth?.toString() || '0');
        res.setHeader('X-Original-Height', blobResult.originalHeight?.toString() || '0');
        res.setHeader('Access-Control-Expose-Headers', 'X-Image-Timestamp, X-Panoramic, X-Original-Width, X-Original-Height');
        return res.status(200).send(blobResult.buffer);
      }
      // Fall through to live image if Blob not available
    }

    // Fetch the Vision-Environnement webcam page to get image URL
    const pageUrl = `https://www.vision-environnement.com/livecams/webcam.php?webcam=${slug}`;
    const pageResponse = await fetch(pageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      },
    });

    if (!pageResponse.ok) {
      return res.status(404).json({ error: 'Webcam not found' });
    }

    const html = await pageResponse.text();

    // Try multiple patterns to find the image URL
    let imageUrl = null;

    // Pattern 1: s1.vision-environnement.com URLs
    const s1Match = html.match(/https:\/\/s1\.vision-environnement\.com\/[^"'\s]+\.jpg/i);
    if (s1Match) {
      imageUrl = s1Match[0];
    }

    // Pattern 2: www.vision-environnement.com/live/image/webcam URLs
    if (!imageUrl) {
      const wwwMatch = html.match(/https:\/\/www\.vision-environnement\.com\/live\/image\/webcam\/[^"'\s]+\.(jpg|JPG)/i);
      if (wwwMatch) {
        imageUrl = wwwMatch[0];
      }
    }

    // Pattern 3: og:image meta tag
    if (!imageUrl) {
      const ogMatch = html.match(/property="og:image"\s+content="([^"]+)"/);
      if (ogMatch) {
        imageUrl = ogMatch[1];
      }
    }

    if (!imageUrl) {
      return res.status(404).json({ error: 'No image found for this webcam', slug });
    }

    // Fetch the actual image
    const imageResponse = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'image/*',
        'Referer': 'https://www.vision-environnement.com/',
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

    // Get the real image timestamp from Last-Modified header
    let imageTimestamp = null;
    const lastModified = imageResponse.headers.get('last-modified');
    if (lastModified) {
      const parsedDate = new Date(lastModified);
      if (!isNaN(parsedDate.getTime())) {
        imageTimestamp = Math.floor(parsedDate.getTime() / 1000);
      }
    }
    // Fallback: try to extract timestamp from URL if present
    if (!imageTimestamp) {
      const urlTimestampMatch = imageUrl.match(/(\d{10,13})/);
      if (urlTimestampMatch) {
        const ts = parseInt(urlTimestampMatch[1]);
        imageTimestamp = ts > 10000000000 ? Math.floor(ts / 1000) : ts;
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
    // Only set timestamp header if we have a real timestamp
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
    console.error('Vision proxy error:', error);
    res.status(500).json({ error: 'Failed to process webcam image', message: error.message });
  }
}

// Helper function to fetch historical images from Vercel Blob storage
// timeValue: either hoursAgo (float) or Unix timestamp (int)
// isTimestamp: true if timeValue is a Unix timestamp
async function fetchFromBlobHistory(webcamId, timeValue, jpegQuality, maxWidth, forcePanorama = false, isTimestamp = false) {
  try {
    // Calculate target timestamp
    let targetTimestamp;
    if (isTimestamp) {
      // Direct timestamp provided
      targetTimestamp = Math.floor(timeValue / 1800) * 1800; // Round to 30-min interval
    } else {
      // hoursAgo provided - calculate target time
      const targetTime = Date.now() - (timeValue * 60 * 60 * 1000);
      targetTimestamp = Math.floor(targetTime / 1000 / 1800) * 1800;
    }

    // List blobs for this webcam to find closest match
    const { blobs } = await list({
      prefix: `webcams/${webcamId}/`,
      limit: 100,
    });

    if (!blobs || blobs.length === 0) {
      console.log(`No blob history found for webcam ${webcamId}`);
      return null;
    }

    // Parse timestamps from blob paths and find closest to target
    const blobsWithTimestamp = blobs.map(blob => {
      const match = blob.pathname.match(/\/(\d+)\.jpg$/);
      return {
        url: blob.url,
        timestamp: match ? parseInt(match[1]) : 0
      };
    }).filter(b => b.timestamp > 0);

    if (blobsWithTimestamp.length === 0) {
      return null;
    }

    // Find closest timestamp
    let closest = blobsWithTimestamp[0];
    for (const blob of blobsWithTimestamp) {
      if (Math.abs(blob.timestamp - targetTimestamp) < Math.abs(closest.timestamp - targetTimestamp)) {
        closest = blob;
      }
    }

    // Fetch the image from Blob storage
    const response = await fetch(closest.url);
    if (!response.ok) {
      return null;
    }

    const imageBuffer = Buffer.from(await response.arrayBuffer());

    // Detect panoramic images
    const metadata = await sharp(imageBuffer).metadata();
    const isPanoramic = metadata.width && metadata.height && (metadata.width > metadata.height * 2);

    // Adjust quality and width for panoramas
    let finalWidth = maxWidth;
    let finalQuality = jpegQuality;
    if (isPanoramic || forcePanorama) {
      finalWidth = Math.max(maxWidth, maxWidth > 600 ? 2400 : 600);
      finalQuality = Math.max(jpegQuality, 85);
    }

    // Compress with sharp
    const processedImage = sharp(imageBuffer)
      .resize(finalWidth, null, {
        withoutEnlargement: true,
        fit: 'inside',
      })
      .jpeg({
        quality: finalQuality,
        progressive: true,
        mozjpeg: isPanoramic || forcePanorama,
      });

    return {
      buffer: await processedImage.toBuffer(),
      timestamp: closest.timestamp,
      isPanoramic,
      originalWidth: metadata.width,
      originalHeight: metadata.height
    };
  } catch (error) {
    console.error('Error fetching from Blob history:', error);
    return null;
  }
}
