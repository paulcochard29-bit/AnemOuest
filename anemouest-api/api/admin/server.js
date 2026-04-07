// Server monitoring & cron management endpoint
import { execSync } from 'child_process';
import os from 'os';
import { createClient } from 'redis';

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || process.env.CRON_SECRET;

function isAuthorized(req) {
  const auth = req.headers.authorization;
  if (!auth || !ADMIN_PASSWORD) return false;
  return auth === `Bearer ${ADMIN_PASSWORD}`;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (!isAuthorized(req)) return res.status(401).json({ error: 'Unauthorized' });

  const action = req.query.action || 'status';

  try {
    if (action === 'status') {
      // System info
      const uptime = os.uptime();
      const totalMem = os.totalmem();
      const freeMem = os.freemem();
      const cpus = os.cpus();
      const loadAvg = os.loadavg();

      // CPU usage average
      const cpuUsage = cpus.map(cpu => {
        const total = Object.values(cpu.times).reduce((a, b) => a + b, 0);
        const idle = cpu.times.idle;
        return Math.round((1 - idle / total) * 100);
      });

      // Disk usage
      let disk = {};
      try {
        const df = execSync("df -h / | tail -1").toString().trim().split(/\s+/);
        disk = { total: df[1], used: df[2], available: df[3], percent: df[4] };
      } catch {}

      // PM2 processes
      let pm2 = [];
      try {
        const pm2Json = execSync("pm2 jlist 2>/dev/null").toString();
        pm2 = JSON.parse(pm2Json).map(p => ({
          name: p.name,
          pid: p.pid,
          status: p.pm2_env?.status,
          uptime: p.pm2_env?.pm_uptime ? Date.now() - p.pm2_env.pm_uptime : 0,
          restarts: p.pm2_env?.restart_time || 0,
          cpu: p.monit?.cpu || 0,
          memory: p.monit?.memory || 0,
        }));
      } catch {}

      // Redis info
      let redis = {};
      try {
        const client = createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
        await client.connect();
        const info = await client.info('memory');
        const keyCount = await client.dbSize();
        const memMatch = info.match(/used_memory_human:(.+)/);
        redis = {
          connected: true,
          memory: memMatch ? memMatch[1].trim() : 'unknown',
          keys: keyCount,
        };
        await client.quit();
      } catch (e) {
        redis = { connected: false, error: e.message };
      }

      // R2 storage info
      const r2 = {
        configured: !!(process.env.R2_BUCKET && process.env.R2_ACCESS_KEY_ID),
        bucket: process.env.R2_BUCKET || 'not set',
        endpoint: process.env.R2_ENDPOINT ? 'configured' : 'not set',
      };

      return res.json({
        system: {
          hostname: os.hostname(),
          platform: `${os.type()} ${os.release()}`,
          arch: os.arch(),
          uptime,
          nodeVersion: process.version,
        },
        cpu: {
          cores: cpus.length,
          model: cpus[0]?.model,
          usage: cpuUsage,
          avgPercent: Math.round(cpuUsage.reduce((a, b) => a + b, 0) / cpuUsage.length),
          loadAvg: loadAvg.map(l => Math.round(l * 100) / 100),
        },
        memory: {
          total: totalMem,
          free: freeMem,
          used: totalMem - freeMem,
          percent: Math.round((1 - freeMem / totalMem) * 100),
        },
        disk,
        pm2,
        redis,
        r2,
        timestamp: new Date().toISOString(),
      });
    }

    if (action === 'logs') {
      const lines = req.query.lines || 50;
      const process = req.query.process || 'api';
      try {
        const logs = execSync(`pm2 logs ${process} --lines ${lines} --nostream 2>&1`).toString();
        return res.json({ logs });
      } catch (e) {
        return res.json({ logs: e.message });
      }
    }

    if (action === 'crons') {
      // Return cron schedule info
      const crons = [
        { name: 'push/send', schedule: '*/15 * * * *', desc: 'Push notifications' },
        { name: 'candhis-cron', schedule: '10,40 * * * *', desc: 'Bouées CANDHIS (toutes les 30 min)' },
        { name: 'webcam-health', schedule: '15,45 * * * *', desc: 'Santé webcams (toutes les 30 min)' },
        { name: 'webcam-cron (batch 1-10)', schedule: '0-9,30-39 * * * *', desc: 'Capture images standard (10 batches)' },
        { name: 'webcam-cron (HLS)', schedule: '0,15,30,45 * * * *', desc: 'Capture HLS Quanteec (Vision-Env exclu)' },
        { name: 'webcam-cron (Skaping)', schedule: '5 batches × 6 min/h', desc: 'Capture Skaping S3 (cycle 10 min, ~670 cams)' },
        { name: 'webcam-cron (Vision-Env)', schedule: '5,20,35,50 * * * *', desc: 'Capture Vision-Env via /api/vision (96 cams)' },
        { name: 'webcam-cron (WindsUp)', schedule: '7,22,37,52 * * * *', desc: 'Capture WindsUp (22 cams)' },
        { name: 'webcam-cron (cleanup)', schedule: '0 */6 * * *', desc: 'Purge images >48h' },
        { name: 'webcam-ai', schedule: '0 6,18 * * *', desc: 'Suggestions IA webcams' },
        { name: 'netatmo-cron', schedule: '*/3 * * * *', desc: 'Refresh Netatmo (zones côtières)' },
        { name: 'netatmo-cron (scan)', schedule: '5 */2 * * *', desc: 'Scan complet 15 zones côtières' },
        { name: 'wind-cron', schedule: '10 * * * *', desc: 'Prévisions vent AROME' },
        { name: 'analytics-cleanup', schedule: '0 3 * * *', desc: 'Purge analytics >90 jours' },
      ];

      // Get recent cron execution from logs
      try {
        const logs = execSync("pm2 logs api --lines 200 --nostream 2>&1 | grep 'Cron' | tail -30").toString();
        const executions = logs.split('\n').filter(Boolean).map(line => {
          const match = line.match(/Cron (\S+) → (\d+)/);
          return match ? { name: match[1], status: parseInt(match[2]), raw: line.trim() } : null;
        }).filter(Boolean);
        return res.json({ crons, recentExecutions: executions });
      } catch {
        return res.json({ crons, recentExecutions: [] });
      }
    }

    if (action === 'restart' && req.method === 'POST') {
      const proc = req.query.process || 'api';
      if (!['api', 'web'].includes(proc)) {
        return res.status(400).json({ error: 'Invalid process' });
      }
      try {
        execSync(`pm2 restart ${proc}`);
        return res.json({ ok: true, restarted: proc });
      } catch (e) {
        return res.status(500).json({ error: e.message });
      }
    }

    return res.status(400).json({ error: 'Unknown action', valid: ['status', 'logs', 'crons', 'restart'] });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
