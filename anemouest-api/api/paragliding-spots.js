// Paragliding Spots API - Serves pre-generated SpotAir data
// Data file generated locally from SpotAir API (their API blocks cloud IPs)
// To refresh: run gen_spotair_json.mjs locally, redeploy

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_PATH = join(__dirname, '..', 'data', 'paragliding-spots.json');

let cachedData = null;

export default function handler(req, res) {
  res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=172800');
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    if (!cachedData) {
      cachedData = JSON.parse(readFileSync(DATA_PATH, 'utf-8'));
    }
    return res.json(cachedData);
  } catch (error) {
    console.error('Paragliding spots error:', error.message);
    return res.status(500).json({ error: error.message, spots: [], count: 0 });
  }
}
