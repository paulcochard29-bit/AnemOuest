import { kv } from '../../lib/kv.js';
import jwt from 'jsonwebtoken';
import http2 from 'http2';

/**
 * POST /api/push/send (or GET for cron)
 * Send silent push notifications to all registered devices
 *
 * This endpoint should be called by a Vercel Cron Job every 15 minutes
 *
 * Required environment variables:
 * - APNS_KEY_ID: Your APNs Key ID from Apple Developer
 * - APNS_TEAM_ID: Your Apple Developer Team ID
 * - APNS_PRIVATE_KEY: Your .p8 private key content (base64 encoded)
 * - APNS_BUNDLE_ID: Your app bundle ID (e.g., com.yourcompany.levent)
 */

interface PushToken {
  token: string;
  platform: string;
  registeredAt: string;
}

export default async function handler(req: any, res: any) {
  // Allow GET for cron jobs, POST for manual triggers
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Verify cron secret if provided
  const cronSecret = req.headers['x-cron-secret'];
  if (process.env.CRON_SECRET && cronSecret !== process.env.CRON_SECRET) {
    // Allow if called from Vercel cron (has authorization header)
    if (!req.headers.authorization?.includes('Bearer')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  try {
    // Get all registered tokens
    const tokensRaw = await kv.smembers('push_tokens');
    const tokens: PushToken[] = tokensRaw.map(t =>
      typeof t === 'string' ? JSON.parse(t) : t
    );

    if (tokens.length === 0) {
      return res.status(200).json({ sent: 0, message: 'No registered devices' });
    }

    // Generate APNs JWT token
    const apnsToken = generateAPNsToken();
    if (!apnsToken) {
      // Debug: log which env vars are missing and JWT error
      const hasKeyId = !!process.env.APNS_KEY_ID;
      const hasTeamId = !!process.env.APNS_TEAM_ID;
      const hasPrivateKey = !!process.env.APNS_PRIVATE_KEY;
      const jwtError = getLastJwtError();
      return res.status(500).json({
        error: 'APNs configuration missing',
        debug: { hasKeyId, hasTeamId, hasPrivateKey, jwtError }
      });
    }

    // Send silent push to each device
    let sent = 0;
    let failed = 0;
    const invalidTokens: string[] = [];
    const errors: string[] = [];

    for (const { token, platform } of tokens) {
      if (platform !== 'ios') continue;

      const result = await sendSilentPush(token, apnsToken);
      if (result.success) {
        sent++;
      } else {
        failed++;
        invalidTokens.push(token);
        if (result.error) {
          errors.push(`${token.substring(0, 8)}...: ${result.error}`);
        }
      }
    }

    // Remove invalid tokens
    for (const token of invalidTokens) {
      const tokenData = tokens.find(t => t.token === token);
      if (tokenData) {
        await kv.srem('push_tokens', JSON.stringify(tokenData));
      }
    }

    console.log(`Silent push sent: ${sent} success, ${failed} failed`);

    return res.status(200).json({
      sent,
      failed,
      totalDevices: tokens.length,
      removedInvalid: invalidTokens.length,
      errors: errors.slice(0, 5) // Show first 5 errors for debugging
    });
  } catch (error) {
    console.error('Push send error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

/**
 * Generate APNs JWT token for authentication
 */
// Store last JWT error for debugging
let lastJwtError: string | null = null;

function generateAPNsToken(): string | null {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const privateKeyBase64 = process.env.APNS_PRIVATE_KEY;

  if (!keyId || !teamId || !privateKeyBase64) {
    lastJwtError = 'Missing credentials';
    return null;
  }

  try {
    const privateKey = Buffer.from(privateKeyBase64, 'base64').toString('utf8');

    const token = jwt.sign({}, privateKey, {
      algorithm: 'ES256',
      keyid: keyId,
      issuer: teamId,
      expiresIn: '1h'
    });

    lastJwtError = null;
    return token;
  } catch (error) {
    lastJwtError = error instanceof Error ? error.message : String(error);
    console.error('JWT generation error:', error);
    return null;
  }
}

function getLastJwtError(): string | null {
  return lastJwtError;
}

/**
 * Send a silent push notification via APNs
 */
interface PushResult {
  success: boolean;
  error?: string;
}

async function sendSilentPush(deviceToken: string, apnsToken: string): Promise<PushResult> {
  const bundleId = process.env.APNS_BUNDLE_ID || 'com.anemouest.levent';
  // Use APNS_ENVIRONMENT env var, default to sandbox for development testing
  const useSandbox = process.env.APNS_ENVIRONMENT !== 'production';

  // Sandbox for development builds, production for TestFlight/App Store
  const apnsHost = useSandbox
    ? 'api.sandbox.push.apple.com'
    : 'api.push.apple.com';

  // Silent push payload (content-available: 1, no alert/sound/badge)
  const payload = JSON.stringify({
    aps: {
      'content-available': 1
    },
    type: 'widget-refresh',
    timestamp: Date.now()
  });

  return new Promise((resolve) => {
    try {
      const client = http2.connect(`https://${apnsHost}`);

      client.on('error', (err) => {
        console.error(`HTTP/2 connection error: ${err.message}`);
        client.close();
        resolve({ success: false, error: `connection: ${err.message}` });
      });

      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        'authorization': `bearer ${apnsToken}`,
        'apns-topic': bundleId,
        'apns-push-type': 'background',
        'apns-priority': '5',
        'apns-expiration': '0',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload)
      });

      let responseData = '';
      let statusCode = 0;

      req.on('response', (headers) => {
        statusCode = headers[':status'] as number || 0;
      });

      req.on('data', (chunk) => {
        responseData += chunk;
      });

      req.on('end', () => {
        client.close();
        if (statusCode === 200) {
          resolve({ success: true });
        } else {
          const errorMsg = `${statusCode}: ${responseData}`;
          console.error(`APNs error for ${deviceToken.substring(0, 10)}...: ${errorMsg}`);
          resolve({ success: false, error: errorMsg });
        }
      });

      req.on('error', (err) => {
        client.close();
        console.error(`Request error: ${err.message}`);
        resolve({ success: false, error: `request: ${err.message}` });
      });

      req.write(payload);
      req.end();

      // Timeout after 10 seconds
      setTimeout(() => {
        client.close();
        resolve({ success: false, error: 'timeout' });
      }, 10000);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`Push send error for ${deviceToken.substring(0, 10)}...:`, error);
      resolve({ success: false, error: errorMsg });
    }
  });
}
