// Webcam Health Check - Checks availability and stores status
// Run via cron every 30 min: /api/webcam-health
// Status stored in Vercel Blob as webcam-health.json

import { put, head } from '../lib/storage.js';

const CRON_SECRET = process.env.CRON_SECRET;
const HEALTH_BLOB_PATH = 'webcam-health.json';
const OFFLINE_THRESHOLD_HOURS = 3; // Mark offline after 3h without valid image

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');

  // GET without auth returns current health status
  if (req.method === 'GET' && !req.query.check) {
    try {
      const healthData = await getHealthStatus();
      return res.status(200).json(healthData);
    } catch (error) {
      return res.status(200).json({ webcams: {}, lastCheck: null });
    }
  }

  // POST or ?check=true triggers health check (requires auth)
  const authHeader = req.headers.authorization;
  if (CRON_SECRET && authHeader !== `Bearer ${CRON_SECRET}`) {
    if (req.headers['x-vercel-cron'] !== '1') {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  return runHealthCheck(req, res);
}

async function getHealthStatus() {
  try {
    const blobInfo = await head(HEALTH_BLOB_PATH);
    if (blobInfo) {
      // Add cache-busting query param to avoid stale data
      const url = new URL(blobInfo.url);
      url.searchParams.set('_t', Date.now());
      const response = await fetch(url.toString(), {
        cache: 'no-store',
        headers: { 'Cache-Control': 'no-cache' }
      });
      return await response.json();
    }
  } catch (error) {
    // Blob doesn't exist yet
  }
  return { webcams: {}, lastCheck: null };
}

async function runHealthCheck(req, res) {
  const startTime = Date.now();
  console.log(`Starting webcam health check at ${new Date(startTime).toISOString()}`);

  try {
    // Fetch ALL webcams (including master list with broken ones)
    const webcamsResponse = await fetch('http://localhost:3001/api/webcams?includeAll=true');
    const allWebcams = await webcamsResponse.json();

    // Get existing health data
    const existingHealth = await getHealthStatus();
    const healthStatus = existingHealth.webcams || {};

    const results = {
      total: allWebcams.length,
      online: 0,
      offline: 0,
      errors: []
    };

    // Sort webcams: prioritize offline/unchecked ones to re-verify them first
    const sortedWebcams = [...allWebcams].sort((a, b) => {
      const statusA = healthStatus[a.id];
      const statusB = healthStatus[b.id];
      // Unchecked webcams first
      if (!statusA && statusB) return -1;
      if (statusA && !statusB) return 1;
      // Then offline webcams
      if (statusA?.online === false && statusB?.online !== false) return -1;
      if (statusA?.online !== false && statusB?.online === false) return 1;
      // Then by last check time (oldest first)
      return (statusA?.lastCheck || 0) - (statusB?.lastCheck || 0);
    });

    // Check webcams in parallel batches (reduced to avoid overwhelming proxies)
    const CONCURRENT = 8;
    for (let i = 0; i < sortedWebcams.length; i += CONCURRENT) {
      const batch = sortedWebcams.slice(i, i + CONCURRENT);

      const checks = batch.map(async (webcam) => {
        const status = await checkWebcamHealth(webcam);

        // Update health status
        const prevStatus = healthStatus[webcam.id] || {};

        if (status.ok) {
          healthStatus[webcam.id] = {
            online: true,
            lastSuccess: Date.now(),
            lastCheck: Date.now(),
            consecutiveFailures: 0
          };
          results.online++;
        } else {
          const consecutiveFailures = (prevStatus.consecutiveFailures || 0) + 1;
          const lastSuccess = prevStatus.lastSuccess || 0;
          const hoursSinceSuccess = lastSuccess ? (Date.now() - lastSuccess) / (1000 * 60 * 60) : 999;

          healthStatus[webcam.id] = {
            online: hoursSinceSuccess < OFFLINE_THRESHOLD_HOURS,
            lastSuccess: lastSuccess,
            lastCheck: Date.now(),
            consecutiveFailures,
            lastError: status.error
          };

          if (hoursSinceSuccess >= OFFLINE_THRESHOLD_HOURS) {
            results.offline++;
            results.errors.push({ id: webcam.id, error: status.error, hoursSinceSuccess: Math.round(hoursSinceSuccess) });
          } else {
            results.online++; // Still within grace period
          }
        }
      });

      await Promise.all(checks);

      // Timeout protection (Vercel function timeout is 60s for Hobby, 300s for Pro)
      if (Date.now() - startTime > 55000) {
        console.log(`Approaching timeout after checking ${i + batch.length}/${allWebcams.length} webcams`);
        break;
      }
    }

    // Save health status to Blob
    const healthData = {
      webcams: healthStatus,
      lastCheck: Date.now(),
      summary: results
    };

    await put(HEALTH_BLOB_PATH, JSON.stringify(healthData), {
      access: 'public',
      contentType: 'application/json',
      addRandomSuffix: false,
    });

    const duration = Math.round((Date.now() - startTime) / 1000);
    console.log(`Health check complete: ${results.online} online, ${results.offline} offline in ${duration}s`);

    res.status(200).json({
      message: 'Health check completed',
      duration: `${duration}s`,
      results
    });
  } catch (error) {
    console.error('Health check error:', error);
    res.status(500).json({ error: 'Health check failed', message: error.message });
  }
}

async function checkWebcamHealth(webcam) {
  try {
    let imageUrl = webcam.imageUrl;

    // Skip if no URL
    if (!imageUrl) {
      return { ok: false, error: 'no-url' };
    }

    // Check if this is our own proxy URL
    const isOurProxy = imageUrl.includes('api.levent.live');

    // For our proxies, use GET (they need to fetch the actual image)
    // For external URLs, try HEAD first
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), isOurProxy ? 15000 : 8000);

    try {
      const response = await fetch(imageUrl, {
        method: isOurProxy ? 'GET' : 'HEAD',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
        signal: controller.signal,
      });

      clearTimeout(timeout);

      if (response.status >= 400) {
        return { ok: false, error: `http-${response.status}` };
      }

      // Check content type
      const contentType = response.headers.get('content-type') || '';
      if (!contentType.includes('image') && !contentType.includes('octet-stream')) {
        return { ok: false, error: 'not-image' };
      }

      // Check content length (too small = error page)
      const contentLength = parseInt(response.headers.get('content-length') || '0');
      if (contentLength > 0 && contentLength < 1000) {
        return { ok: false, error: 'too-small' };
      }

      return { ok: true };
    } finally {
      clearTimeout(timeout);
    }
  } catch (error) {
    if (error.name === 'AbortError') {
      return { ok: false, error: 'timeout' };
    }
    return { ok: false, error: error.code || error.message || 'unknown' };
  }
}
