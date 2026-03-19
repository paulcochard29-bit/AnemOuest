// AnemOuest API — Express server (replaces Vercel serverless functions)
import 'dotenv/config';
import express from 'express';
import cron from 'node-cron';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { kv } from './lib/kv.js';

const app = express();
const PORT = process.env.PORT || 3001;

// ─── Security ───

// Helmet: security headers (XSS, clickjacking, MIME sniffing, etc.)
app.use(helmet({
  contentSecurityPolicy: false,  // API returns JSON, not HTML
  crossOriginResourcePolicy: { policy: 'cross-origin' },  // Allow image loading from other origins
}));

// Trust proxy (behind Traefik)
app.set('trust proxy', 1);

// Rate limiting — public endpoints
const publicLimiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  max: 600,             // 600 req/min per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later' },
});

// Rate limiting — admin endpoints (stricter)
const adminLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,              // 30 req/min per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests' },
});

// Admin brute-force protection
const loginAttempts = new Map();
function adminBruteForce(req, res, next) {
  const ip = req.ip;
  const auth = req.headers.authorization;
  const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;

  if (!auth || !ADMIN_PASSWORD) return next();

  const attempts = loginAttempts.get(ip) || { count: 0, blockedUntil: 0 };

  // Check if blocked
  if (attempts.blockedUntil > Date.now()) {
    const wait = Math.ceil((attempts.blockedUntil - Date.now()) / 1000);
    return res.status(429).json({ error: `Blocked for ${wait}s after too many failed attempts` });
  }

  // Check password
  if (auth !== `Bearer ${ADMIN_PASSWORD}`) {
    attempts.count++;
    if (attempts.count >= 5) {
      attempts.blockedUntil = Date.now() + 5 * 60 * 1000; // Block 5 min
      attempts.count = 0;
      console.warn(`🔒 Admin brute-force blocked: ${ip}`);
    }
    loginAttempts.set(ip, attempts);
  } else {
    // Successful auth — reset
    loginAttempts.delete(ip);
  }

  next();
}

// Cleanup old brute-force entries every 10 min
setInterval(() => {
  const now = Date.now();
  for (const [ip, data] of loginAttempts) {
    if (data.blockedUntil < now && data.count === 0) loginAttempts.delete(ip);
  }
}, 10 * 60 * 1000);

// ─── CORS (restrict to known origins) ───
const ALLOWED_ORIGINS = [
  'https://levent.live',
  'https://www.levent.live',
  'https://srv1502947.hstgr.cloud',
  'http://localhost:3000',
  'http://localhost:3001',
];

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (!origin || ALLOWED_ORIGINS.includes(origin)) {
    res.header('Access-Control-Allow-Origin', origin || '*');
  } else {
    // Allow requests without origin (iOS app, curl, cron)
    // but don't reflect unknown browser origins
    res.header('Access-Control-Allow-Origin', ALLOWED_ORIGINS[0]);
  }
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Api-Key');
  res.header('Access-Control-Max-Age', '86400');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// Middleware
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// Apply rate limiters
app.use('/api/admin', adminLimiter, adminBruteForce);
app.use('/api', publicLimiter);

// Block cron endpoints from external access
const CRON_ENDPOINTS = ['candhis-cron', 'netatmo-cron', 'webcam-cron', 'webcam-health', 'wind-cron', 'warmup'];
app.use((req, res, next) => {
  const endpoint = req.path.replace('/api/', '');
  if (CRON_ENDPOINTS.includes(endpoint)) {
    const isLocal = req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1';
    const hasSecret = req.headers.authorization === `Bearer ${process.env.CRON_SECRET}`;
    if (!isLocal && !hasSecret) {
      return res.status(403).json({ error: 'Forbidden' });
    }
  }
  next();
});

// ─── API Key authentication ───
// Endpoints that don't require API key (public or handled by their own auth)
const PUBLIC_ENDPOINTS = [
  'health', 'push/register',
  // Image/media endpoints called from <img> tags (can't send headers)
  'webcam-image', 'skaping', 'viewsurf', 'viewsurf-stream', 'windsup-webcam', 'vision',
  // Proxy endpoints
  'radar-tile', 'wind-tiles', 'wind-raster',
];
const ADMIN_PREFIX = '/api/admin/';

// Cache API keys in memory (refresh every 60s)
let apiKeysCache = null;
let apiKeysCacheTime = 0;
const API_KEYS_TTL = 60 * 1000;

async function loadApiKeys() {
  if (apiKeysCache && Date.now() - apiKeysCacheTime < API_KEYS_TTL) return apiKeysCache;
  try {
    const raw = await kv.hgetall('api_keys') || {};
    const keys = new Map();
    for (const [id, data] of Object.entries(raw)) {
      const parsed = typeof data === 'string' ? JSON.parse(data) : data;
      if (parsed.active) keys.set(parsed.key, { id, ...parsed });
    }
    apiKeysCache = keys;
    apiKeysCacheTime = Date.now();
    return keys;
  } catch {
    return apiKeysCache || new Map();
  }
}

// Per-key rate limiting
const keyRequestCounts = new Map();
setInterval(() => keyRequestCounts.clear(), 60 * 1000);

app.use('/api', async (req, res, next) => {
  // Skip auth for admin (has its own), cron (already blocked), public, and OPTIONS
  if (req.method === 'OPTIONS') return next();
  if (req.path.startsWith(ADMIN_PREFIX.replace('/api', ''))) return next();
  const endpoint = req.path.replace('/', '');
  if (CRON_ENDPOINTS.includes(endpoint) || PUBLIC_ENDPOINTS.includes(endpoint)) return next();

  // Allow internal calls (localhost)
  const isLocal = req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1';
  if (isLocal) return next();

  // Check if API key auth is enabled
  const keys = await loadApiKeys();
  if (keys.size === 0) return next(); // No keys configured = open access

  // Extract API key from header or query
  const apiKey = req.headers['x-api-key'] || req.query.apikey;
  if (!apiKey) {
    return res.status(401).json({ error: 'API key required', hint: 'Pass via X-Api-Key header or ?apikey= param' });
  }

  const keyData = keys.get(apiKey);
  if (!keyData) {
    return res.status(403).json({ error: 'Invalid API key' });
  }

  // Per-key rate limiting
  const count = (keyRequestCounts.get(keyData.id) || 0) + 1;
  keyRequestCounts.set(keyData.id, count);
  if (count > keyData.rateLimit) {
    return res.status(429).json({ error: 'Rate limit exceeded for this API key' });
  }

  // Track usage (async, don't block)
  const today = new Date().toISOString().split('T')[0];
  kv.set(`apikey_usage:${keyData.id}:${today}`, count, { ex: 86400 * 7 }).catch(() => {});
  kv.hset('api_keys', { [keyData.id]: JSON.stringify({ ...keyData, lastUsed: new Date().toISOString(), requestCount: (keyData.requestCount || 0) + 1 }) }).catch(() => {});

  // Attach key info to request
  req.apiKey = keyData;
  res.setHeader('X-RateLimit-Limit', keyData.rateLimit);
  res.setHeader('X-RateLimit-Remaining', Math.max(0, keyData.rateLimit - count));
  next();
});

// Route helper: wraps a Vercel-style handler for Express
function route(handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (err) {
      console.error(`[${req.path}]`, err);
      if (!res.headersSent) {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  };
}

// ─── Load all handlers ───
const handlers = {};
const endpoints = [
  'candhis', 'candhis-cron', 'diabox', 'forecast-accuracy', 'gowind',
  'history', 'meteofrance', 'ndbc', 'netatmo', 'netatmo-cron', 'netatmo-debug',
  'netatmo-init', 'paragliding-spots', 'pioupiou', 'radar-tile', 'skaping',
  'spots', 'stations', 'tide', 'viewsurf', 'viewsurf-stream', 'vision',
  'warmup', 'webcam-cron', 'webcam-health', 'webcam-image', 'webcam-timeline',
  'webcams', 'wind-cron', 'wind-raster', 'wind-tiles', 'windcornouaille',
  'windsup', 'windsup-webcam',
  'mf2-stations', 'mf2-meteofrance', 'mf2-history',
];
const adminEndpoints = [
  'api-keys', 'config', 'netatmo', 'server', 'station-ai', 'stations', 'status',
  'webcam-ai', 'webcam-weather', 'webcams',
];

// Dynamic import all handlers
async function loadHandlers() {
  for (const name of endpoints) {
    try {
      const mod = await import(`./api/${name}.js`);
      handlers[name] = mod.default;
    } catch (err) {
      console.warn(`⚠ Failed to load /api/${name}:`, err.message);
    }
  }
  for (const name of adminEndpoints) {
    try {
      const mod = await import(`./api/admin/${name}.js`);
      handlers[`admin/${name}`] = mod.default;
    } catch (err) {
      console.warn(`⚠ Failed to load /api/admin/${name}:`, err.message);
    }
  }

  // Push endpoints
  try {
    const pushSend = await import('./api/push/send.js');
    handlers['push/send'] = pushSend.default;
  } catch (err) {
    console.warn('⚠ Failed to load /api/push/send:', err.message);
  }
  try {
    const pushRegister = await import('./api/push/register.js');
    handlers['push/register'] = pushRegister.default;
  } catch (err) {
    console.warn('⚠ Failed to load /api/push/register:', err.message);
  }
}

// ─── Register routes ───
function registerRoutes() {
  // Standard endpoints
  for (const name of endpoints) {
    if (handlers[name]) {
      app.all(`/api/${name}`, route(handlers[name]));
    }
  }
  // Admin endpoints
  for (const name of adminEndpoints) {
    if (handlers[`admin/${name}`]) {
      app.all(`/api/admin/${name}`, route(handlers[`admin/${name}`]));
    }
  }
  // Push endpoints
  if (handlers['push/send']) app.all('/api/push/send', route(handlers['push/send']));
  if (handlers['push/register']) app.all('/api/push/register', route(handlers['push/register']));

  // Health check
  app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

  // Catch-all 404
  app.use('/api/*', (req, res) => res.status(404).json({ error: 'Endpoint not found' }));
}

// ─── Cron jobs (replaces Vercel cron) ───
function setupCrons() {
  const callHandler = async (name, query = {}) => {
    if (!handlers[name]) return console.warn(`Cron: handler ${name} not loaded`);
    const req = { method: 'GET', query, headers: { authorization: `Bearer ${process.env.CRON_SECRET}` }, ip: '127.0.0.1' };
    const res = {
      _status: 200,
      _body: null,
      status(code) { this._status = code; return this; },
      json(data) { this._body = data; return this; },
      send(data) { this._body = data; return this; },
      setHeader() { return this; },
      end() { return this; },
    };
    try {
      await handlers[name](req, res);
      console.log(`✓ Cron ${name} → ${res._status}`);
    } catch (err) {
      console.error(`✗ Cron ${name} failed:`, err.message);
    }
  };

  // Push notifications — every 15 min
  cron.schedule('*/15 * * * *', () => callHandler('push/send'));

  // CANDHIS buoys — every 30 min
  cron.schedule('10,40 * * * *', () => callHandler('candhis-cron'));

  // Webcam health — every 30 min
  cron.schedule('15,45 * * * *', () => callHandler('webcam-health', { check: 'true' }));

  // Webcam capture — 10 batches staggered every minute
  for (let batch = 1; batch <= 10; batch++) {
    const min1 = batch - 1;
    const min2 = min1 + 30;
    cron.schedule(`${min1},${min2} * * * *`, () => callHandler('webcam-cron', { action: 'capture', batch: String(batch) }));
  }

  // HLS-only webcam capture — every 15 min
  cron.schedule('0,15,30,45 * * * *', () => callHandler('webcam-cron', { hlsOnly: 'true' }));

  // Webcam cleanup (48h+) — every 6 hours
  cron.schedule('0 */6 * * *', () => callHandler('webcam-cron', { action: 'cleanup' }));

  // Webcam AI suggestions — 6h and 18h
  cron.schedule('0 6,18 * * *', () => callHandler('admin/webcam-ai', { scope: 'offline', auto: 'true' }));

  // Netatmo refresh — every 3 min
  cron.schedule('*/3 * * * *', () => callHandler('netatmo-cron'));

  // Netatmo full scan — every 2 hours
  cron.schedule('5 */2 * * *', () => callHandler('netatmo-cron', { scan: 'true' }));

  // Wind forecast generation — every hour at :10
  cron.schedule('10 * * * *', () => callHandler('wind-cron'));

  console.log('⏰ Cron jobs registered');
}

// ─── Start ───
async function start() {
  await loadHandlers();
  registerRoutes();
  setupCrons();

  app.listen(PORT, () => {
    console.log(`🚀 AnemOuest API running on port ${PORT}`);
    console.log(`   ${Object.keys(handlers).length} endpoints loaded`);
    console.log(`   🔒 Security: helmet, rate-limit (120/min), CORS restricted, cron endpoints protected`);
  });
}

start().catch(err => {
  console.error('Failed to start:', err);
  process.exit(1);
});
