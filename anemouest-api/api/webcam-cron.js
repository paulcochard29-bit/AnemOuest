// Webcam Cron Job - Combined capture and cleanup
// Usage:
// - /api/webcam-cron?action=capture&batch=1 - Capture batch 1 (webcams 0-24)
// - /api/webcam-cron?action=capture&batch=2 - Capture batch 2 (webcams 25-49)
// - ... up to batch=10 for all 245 webcams
// - /api/webcam-cron?action=cleanup - Delete images older than 48h

import { put, list, del } from '@vercel/blob';

const CRON_SECRET = process.env.CRON_SECRET;
const RETENTION_HOURS = 48;
const BATCH_SIZE = 25; // 25 webcams per batch for faster execution

// Viewsurf webcams with HLS streams available (fresher images via poster)
// Only webcams that exist in webcams.js AND have HLS streams
const VIEWSURF_HLS_STREAMS = new Set([
  'vs-fouesnant-capi', 'vs-benodet', 'vs-penmarch', 'vs-guilvinec', 'vs-crozon', 'vs-pont-labbe',
  'vs-paimpol', 'vs-combrit', 'vs-glenan', 'vs-croisic', 'vs-pouliguen',
  'vs-lacanau', 'vs-arcachon', 'vs-seignosse', 'vs-le-havre', 'vs-dieppe',
  'vs-siouville', 'vs-goury', 'vs-barneville', 'vs-dunkerque', 'vs-bray-dunes',
  'vs-zuydcoote', 'vs-calais', 'vs-hardelot', 'vs-anglet', 'vs-nice',
  // Custom webcams from KV
  'new-1770302739665', 'new-1770303647286', 'new-1770303809736'
]);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  // Verify authorization
  const authHeader = req.headers.authorization;
  if (CRON_SECRET && authHeader !== `Bearer ${CRON_SECRET}`) {
    if (req.headers['x-vercel-cron'] !== '1') {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  const { action, batch, hlsOnly } = req.query;

  if (action === 'cleanup') {
    return handleCleanup(req, res);
  } else if (hlsOnly === 'true') {
    return handleHlsCapture(req, res);
  } else {
    return handleCapture(req, res, parseInt(batch) || 0);
  }
}

async function handleCapture(req, res, batchNum) {
  const startTime = Date.now();
  const timestamp = Math.floor(startTime / 1000);
  const roundedTimestamp = Math.floor(timestamp / 1800) * 1800;

  console.log(`Starting webcam capture batch ${batchNum} at ${new Date(startTime).toISOString()}`);

  try {
    const webcamsResponse = await fetch('https://anemouest-api.vercel.app/api/webcams');
    const allWebcams = await webcamsResponse.json();

    // Filter to specific batch if specified (1-10), otherwise capture all
    let webcams;
    if (batchNum >= 1 && batchNum <= 10) {
      const startIdx = (batchNum - 1) * BATCH_SIZE;
      const endIdx = batchNum * BATCH_SIZE;
      webcams = allWebcams.slice(startIdx, endIdx);
    } else {
      webcams = allWebcams;
    }

    const results = {
      batch: batchNum || 'all',
      total: webcams.length,
      success: 0,
      failed: 0,
      skipped: 0,
      hlsCaptures: 0,
      errors: []
    };

    // Process 10 at a time for faster completion
    const CONCURRENT = 10;
    const batches = [];
    for (let i = 0; i < webcams.length; i += CONCURRENT) {
      batches.push(webcams.slice(i, i + CONCURRENT));
    }

    for (const batch of batches) {
      const promises = batch.map(async (webcam) => {
        try {
          let imageUrl = webcam.imageUrl;

          // Skip HLS webcams - they're captured by the dedicated HLS job (every 15 min)
          if (VIEWSURF_HLS_STREAMS.has(webcam.id)) {
            results.skipped++;
            return;
          }

          // Normal Viewsurf capture via proxy (returns image directly)
          if (webcam.source === 'Viewsurf' && imageUrl.includes('viewsurf?id=')) {
            const idMatch = imageUrl.match(/id=(\d+)/);
            if (idMatch) {
              // Use proxy URL directly - it returns the image
              imageUrl = `https://anemouest-api.vercel.app/api/viewsurf?id=${idMatch[1]}`;
            }
          }

          const response = await fetch(imageUrl, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://www.skaping.com/',
              'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
            },
            signal: AbortSignal.timeout(10000),
          });

          if (!response.ok) {
            results.failed++;
            results.errors.push({ id: webcam.id, error: `HTTP ${response.status}` });
            return;
          }

          const contentType = response.headers.get('content-type');
          if (!contentType || !contentType.includes('image')) {
            results.failed++;
            results.errors.push({ id: webcam.id, error: 'Not an image' });
            return;
          }

          const imageBuffer = await response.arrayBuffer();

          if (imageBuffer.byteLength < 5000) {
            results.skipped++;
            return;
          }

          const blobPath = `webcams/${webcam.id}/${roundedTimestamp}.jpg`;

          await put(blobPath, imageBuffer, {
            access: 'public',
            contentType: 'image/jpeg',
            addRandomSuffix: false,
          });

          results.success++;
        } catch (error) {
          results.failed++;
          results.errors.push({ id: webcam.id, error: error.message });
        }
      });

      await Promise.all(promises);

      // 25s timeout for cron-job.org compatibility
      if (Date.now() - startTime > 25000) {
        console.log('Approaching timeout, stopping capture');
        break;
      }
    }

    const duration = Math.round((Date.now() - startTime) / 1000);
    console.log(`Batch ${batchNum || 'all'} complete: ${results.success}/${results.total} in ${duration}s`);

    res.status(200).json({
      message: `Batch ${batchNum || 'all'} capture completed`,
      timestamp: roundedTimestamp,
      duration: `${duration}s`,
      results
    });
  } catch (error) {
    console.error('Capture error:', error);
    res.status(500).json({ error: 'Capture failed', message: error.message });
  }
}

async function handleHlsCapture(req, res) {
  const startTime = Date.now();
  const timestamp = Math.floor(startTime / 1000);
  // Round to 15 minutes for HLS captures (900 seconds)
  const roundedTimestamp = Math.floor(timestamp / 900) * 900;

  console.log(`Starting HLS-only capture at ${new Date(startTime).toISOString()}`);

  try {
    const results = {
      total: VIEWSURF_HLS_STREAMS.size,
      success: 0,
      failed: 0,
      skipped: 0,
      errors: []
    };

    // Convert Set to Array for processing
    const hlsWebcams = Array.from(VIEWSURF_HLS_STREAMS);

    // Process 10 at a time
    const CONCURRENT = 10;
    const batches = [];
    for (let i = 0; i < hlsWebcams.length; i += CONCURRENT) {
      batches.push(hlsWebcams.slice(i, i + CONCURRENT));
    }

    for (const batch of batches) {
      const promises = batch.map(async (webcamId) => {
        try {
          const streamResponse = await fetch(
            `https://anemouest-api.vercel.app/api/viewsurf-stream?id=${webcamId}`,
            { signal: AbortSignal.timeout(15000) }
          );

          if (!streamResponse.ok) {
            results.failed++;
            results.errors.push({ id: webcamId, error: `HTTP ${streamResponse.status}` });
            return;
          }

          if (!streamResponse.headers.get('content-type')?.includes('image')) {
            results.failed++;
            results.errors.push({ id: webcamId, error: 'Not an image' });
            return;
          }

          const imageBuffer = await streamResponse.arrayBuffer();

          if (imageBuffer.byteLength < 5000) {
            results.skipped++;
            return;
          }

          const blobPath = `webcams/${webcamId}/${roundedTimestamp}.jpg`;
          await put(blobPath, imageBuffer, {
            access: 'public',
            contentType: 'image/jpeg',
            addRandomSuffix: false,
          });

          results.success++;
        } catch (error) {
          results.failed++;
          results.errors.push({ id: webcamId, error: error.message });
        }
      });

      await Promise.all(promises);

      // 25s timeout safety
      if (Date.now() - startTime > 25000) {
        console.log('Approaching timeout, stopping HLS capture');
        break;
      }
    }

    const duration = Math.round((Date.now() - startTime) / 1000);
    console.log(`HLS capture complete: ${results.success}/${results.total} in ${duration}s`);

    res.status(200).json({
      message: 'HLS capture completed',
      timestamp: roundedTimestamp,
      duration: `${duration}s`,
      results
    });
  } catch (error) {
    console.error('HLS capture error:', error);
    res.status(500).json({ error: 'HLS capture failed', message: error.message });
  }
}

async function handleCleanup(req, res) {
  const startTime = Date.now();
  const cutoffTimestamp = Math.floor((startTime - RETENTION_HOURS * 60 * 60 * 1000) / 1000);

  console.log(`Starting cleanup, removing images before timestamp ${cutoffTimestamp}`);

  try {
    let deletedCount = 0;
    let cursor = undefined;
    let totalScanned = 0;

    do {
      const { blobs, cursor: nextCursor } = await list({
        prefix: 'webcams/',
        cursor,
        limit: 1000,
      });

      cursor = nextCursor;
      totalScanned += blobs.length;

      const toDelete = blobs.filter(blob => {
        const match = blob.pathname.match(/\/(\d+)\.jpg$/);
        if (match) {
          const blobTimestamp = parseInt(match[1]);
          return blobTimestamp < cutoffTimestamp;
        }
        return false;
      });

      if (toDelete.length > 0) {
        await Promise.all(toDelete.map(blob => del(blob.url)));
        deletedCount += toDelete.length;
      }

      if (Date.now() - startTime > 50000) {
        console.log('Approaching timeout, stopping cleanup');
        break;
      }
    } while (cursor);

    const duration = Math.round((Date.now() - startTime) / 1000);
    console.log(`Cleanup complete: deleted ${deletedCount}/${totalScanned} in ${duration}s`);

    res.status(200).json({
      message: 'Cleanup completed',
      scanned: totalScanned,
      deleted: deletedCount,
      duration: `${duration}s`
    });
  } catch (error) {
    console.error('Cleanup error:', error);
    res.status(500).json({ error: 'Cleanup failed', message: error.message });
  }
}
