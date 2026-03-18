// Seed SpotAir spots into Vercel Blob from local machine
import { put } from '@vercel/blob';

const SPOTS_URL = 'https://data.spotair.mobi/spots/spots-get.php';
const API_KEY = 'nyBtvIV/HEFiDMzZDwgbUA==';
const BLOB_PATH = 'spotair-spots.json';

const ZONES = [
  { name: 'Nord/Bretagne/Normandie', south: 47.5, north: 51.5, west: -5.5, east: 4.0 },
  { name: 'Centre/Loire', south: 45.5, north: 48.5, west: -2.5, east: 5.5 },
  { name: 'Sud-Ouest', south: 42.0, north: 46.0, west: -2.0, east: 2.5 },
  { name: 'Sud-Est/Alpes', south: 43.0, north: 47.5, west: 2.0, east: 8.5 },
  { name: 'Corse', south: 41.0, north: 43.5, west: 8.0, east: 10.0 },
];

const DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
function decodeOrientationBitmask(bitmask) {
  if (!bitmask) return [];
  const result = [];
  for (let i = 0; i < 8; i++) {
    if ((1 << i) & bitmask) result.push(DIRECTIONS[i]);
  }
  return result;
}
function spotTypeString(type) {
  switch (type) {
    case 1: return 'takeoff';
    case 2: return 'landing';
    case 3: return 'trainingSlope';
    case 7: return 'winch';
    default: return 'other';
  }
}

async function fetchZone(zone) {
  const body = `pratique=1&sud=${zone.south}&nord=${zone.north}&ouest=${zone.west}&est=${zone.east}`;
  const r = await fetch(SPOTS_URL, {
    method: 'POST',
    headers: { 'X-Spotair-Apikey': API_KEY, 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await r.json();
  console.log(`${zone.name}: ${json.data?.length || 0} spots`);
  return json.data || [];
}

// Fetch all zones
const results = await Promise.all(ZONES.map(fetchZone));
const allRaw = results.flat();

// Deduplicate & transform
const byId = new Map();
for (const dto of allRaw) {
  if (!byId.has(dto.id)) byId.set(dto.id, dto);
}

const spots = [];
for (const dto of byId.values()) {
  if (dto.etat !== 'V') continue;
  if (!dto.latitude || !dto.longitude) continue;
  spots.push({
    id: `spotair_${dto.id}`,
    name: dto.noms?.fr || dto.nom || `Spot ${dto.id}`,
    latitude: dto.latitude,
    longitude: dto.longitude,
    altitude: dto.altitude || 0,
    orientations: decodeOrientationBitmask(dto.orientations),
    orientationsDefavo: decodeOrientationBitmask(dto.orientations_defavo),
    type: spotTypeString(dto.type),
    level: dto.niveau || null,
    description: dto.descriptions?.fr || dto.description || null,
    city: dto.ville || null,
  });
}

console.log(`\nTotal: ${spots.length} valid unique spots`);

const cacheData = {
  spots,
  count: spots.length,
  timestamp: new Date().toISOString(),
};

const json = JSON.stringify(cacheData);
console.log(`JSON size: ${(json.length / 1024).toFixed(0)} KB`);

// Upload to Vercel Blob
const blob = await put(BLOB_PATH, json, {
  access: 'public',
  addRandomSuffix: false,
  contentType: 'application/json',
});

console.log(`Uploaded to Blob: ${blob.url}`);
