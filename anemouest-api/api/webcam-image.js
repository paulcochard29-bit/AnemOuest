// Webcam Image API
// Serves stored webcam images with history support
// GET /api/webcam-image?id={webcam_id}&hoursAgo={0-48}

import { list } from '../lib/storage.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { id, hoursAgo, redirect } = req.query;

  if (!id) {
    return res.status(400).json({ error: 'Missing id parameter' });
  }

  try {
    const hours = Math.min(48, Math.max(0, parseFloat(hoursAgo) || 0));
    const targetTimestamp = Math.floor((Date.now() - hours * 60 * 60 * 1000) / 1000);

    // List all images for this webcam
    const { blobs } = await list({
      prefix: `webcams/${id}/`,
      limit: 100, // 48h at 30min intervals = 96 max
    });

    if (blobs.length === 0) {
      return res.status(404).json({
        error: 'No images found',
        message: 'Webcam images not yet captured. Please wait for the next capture cycle.',
        webcamId: id
      });
    }

    // Parse timestamps and find closest to target
    const imagesWithTime = blobs.map(blob => {
      const match = blob.pathname.match(/\/(\d+)\.jpg$/);
      return {
        url: blob.url,
        timestamp: match ? parseInt(match[1]) : 0,
        pathname: blob.pathname
      };
    }).filter(img => img.timestamp > 0);

    // Sort by timestamp (newest first)
    imagesWithTime.sort((a, b) => b.timestamp - a.timestamp);

    // Find closest to target
    let closest = imagesWithTime[0];
    let minDiff = Math.abs(closest.timestamp - targetTimestamp);

    for (const img of imagesWithTime) {
      const diff = Math.abs(img.timestamp - targetTimestamp);
      if (diff < minDiff) {
        minDiff = diff;
        closest = img;
      }
    }

    // Calculate actual hours ago for this image
    const actualHoursAgo = (Date.now() / 1000 - closest.timestamp) / 3600;

    // Get available time range
    const newest = imagesWithTime[0];
    const oldest = imagesWithTime[imagesWithTime.length - 1];
    const availableHours = (newest.timestamp - oldest.timestamp) / 3600;

    if (redirect === 'true') {
      // Redirect to blob URL
      res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
      return res.redirect(302, closest.url);
    }

    // Return JSON with image info
    res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
    res.status(200).json({
      imageUrl: closest.url,
      timestamp: closest.timestamp,
      requestedHoursAgo: hours,
      actualHoursAgo: Math.round(actualHoursAgo * 10) / 10,
      availableImages: imagesWithTime.length,
      availableHours: Math.round(availableHours * 10) / 10,
      newestTimestamp: newest.timestamp,
      oldestTimestamp: oldest.timestamp,
      webcamId: id
    });
  } catch (error) {
    console.error('Webcam image error:', error);
    res.status(500).json({ error: 'Failed to fetch webcam image', message: error.message });
  }
}
