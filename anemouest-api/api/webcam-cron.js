// Webcam Cron Job - Combined capture and cleanup
// Usage:
// - /api/webcam-cron?action=capture&batch=1 - Capture batch 1 (webcams 0-24)
// - /api/webcam-cron?action=capture&batch=2 - Capture batch 2 (webcams 25-49)
// - ... up to batch=10 for all 245 webcams
// - /api/webcam-cron?action=cleanup - Delete images older than 48h
//
// HLS webcams (with quanteec streamUrl) are skipped by normal capture
// and handled by the dedicated HLS capture (?hlsOnly=true) every 15 min.

import { put, list, del, head as blobHead } from '../lib/storage.js';

const CRON_SECRET = process.env.CRON_SECRET;
const RETENTION_HOURS = 48;
const BATCH_SIZE = 25;

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

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
    const webcamsResponse = await fetch('http://localhost:3001/api/webcams');
    const allWebcams = await webcamsResponse.json();

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
      errors: []
    };
    const capturedIds = []; // track successfully captured webcam IDs

    const CONCURRENT = 10;
    const batches = [];
    for (let i = 0; i < webcams.length; i += CONCURRENT) {
      batches.push(webcams.slice(i, i + CONCURRENT));
    }

    for (const batch of batches) {
      const promises = batch.map(async (webcam) => {
        try {
          let imageUrl = webcam.imageUrl;

          // Skip HLS webcams - captured by dedicated HLS job (every 15 min)
          if (webcam.streamUrl && webcam.streamUrl.includes('quanteec')) {
            results.skipped++;
            return;
          }

          // Normal Viewsurf capture via proxy
          if (webcam.source === 'Viewsurf' && imageUrl.includes('viewsurf?id=')) {
            const idMatch = imageUrl.match(/id=(\d+)/);
            if (idMatch) {
              imageUrl = `http://localhost:3001/api/viewsurf?id=${idMatch[1]}`;
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
          capturedIds.push(webcam.id);
        } catch (error) {
          results.failed++;
          results.errors.push({ id: webcam.id, error: error.message });
        }
      });

      await Promise.all(promises);

      if (Date.now() - startTime > 25000) {
        console.log('Approaching timeout, stopping capture');
        break;
      }
    }

    // Update health blob with fresh capture timestamps
    if (capturedIds.length > 0) {
      try {
        let healthData = { webcams: {}, lastCheck: Date.now() };
        try {
          const existing = await blobHead('webcam-health.json');
          if (existing?.url) {
            const url = new URL(existing.url);
            url.searchParams.set('_t', Date.now());
            const r = await fetch(url.toString(), { cache: 'no-store' });
            if (r.ok) healthData = await r.json();
          }
        } catch {}
        const now = Date.now();
        for (const id of capturedIds) {
          healthData.webcams[id] = {
            ...(healthData.webcams[id] || {}),
            online: true,
            lastSuccess: now,
            lastCheck: now,
            consecutiveFailures: 0,
          };
        }
        await put('webcam-health.json', JSON.stringify(healthData), {
          access: 'public', contentType: 'application/json', addRandomSuffix: false,
        });
      } catch (e) {
        console.error('Failed to update health blob:', e.message);
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
  const roundedTimestamp = Math.floor(timestamp / 900) * 900;

  console.log(`Starting HLS-only capture at ${new Date(startTime).toISOString()}`);

  try {
    const webcamsResponse = await fetch('http://localhost:3001/api/webcams');
    const allWebcams = await webcamsResponse.json();

    // Dynamic: get all webcams with Quanteec HLS streams from API
    const hlsWebcams = allWebcams
      .filter(w => w.streamUrl && w.streamUrl.includes('quanteec'))
      .map(w => ({ id: w.id, streamUrl: w.streamUrl }));

    const results = {
      total: hlsWebcams.length,
      success: 0,
      failed: 0,
      skipped: 0,
      errors: []
    };
    const capturedHlsIds = [];

    const CONCURRENT = 10;
    const batches = [];
    for (let i = 0; i < hlsWebcams.length; i += CONCURRENT) {
      batches.push(hlsWebcams.slice(i, i + CONCURRENT));
    }

    for (const batch of batches) {
      const promises = batch.map(async (webcam) => {
        const webcamId = webcam.id;
        const streamUrl = webcam.streamUrl;

        try {
          let apiUrl = `http://localhost:3001/api/viewsurf-stream?id=${webcamId}`;
          if (streamUrl) {
            apiUrl += `&streamUrl=${encodeURIComponent(streamUrl)}`;
          }

          const streamResponse = await fetch(apiUrl, { signal: AbortSignal.timeout(15000) });

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
          capturedHlsIds.push(webcamId);
        } catch (error) {
          results.failed++;
          results.errors.push({ id: webcamId, error: error.message });
        }
      });

      await Promise.all(promises);

      if (Date.now() - startTime > 25000) {
        console.log('Approaching timeout, stopping HLS capture');
        break;
      }
    }

    // Update health blob with fresh capture timestamps
    if (capturedHlsIds.length > 0) {
      try {
        let healthData = { webcams: {}, lastCheck: Date.now() };
        try {
          const existing = await blobHead('webcam-health.json');
          if (existing?.url) {
            const url = new URL(existing.url);
            url.searchParams.set('_t', Date.now());
            const r = await fetch(url.toString(), { cache: 'no-store' });
            if (r.ok) healthData = await r.json();
          }
        } catch {}
        const now = Date.now();
        for (const id of capturedHlsIds) {
          healthData.webcams[id] = {
            ...(healthData.webcams[id] || {}),
            online: true,
            lastSuccess: now,
            lastCheck: now,
            consecutiveFailures: 0,
          };
        }
        await put('webcam-health.json', JSON.stringify(healthData), {
          access: 'public', contentType: 'application/json', addRandomSuffix: false,
        });
      } catch (e) {
        console.error('Failed to update health blob:', e.message);
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
