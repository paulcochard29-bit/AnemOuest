// Webcams API endpoint
// Returns webcams for French coasts and lakes
// Automatically filters out offline webcams based on health check status

import { head } from '../lib/storage.js';
import { kv } from '../lib/kv.js';

const HEALTH_BLOB_PATH = 'webcam-health.json';

// Quanteec HLS stream URLs for Viewsurf webcams
// This mapping is used to populate streamUrl for hardcoded webcams
const QUANTEEC_STREAMS = {
  // Bretagne - Finistère
  'vs-fouesnant-capi': 'https://ds1-cache.quanteec.com/contents/encodings/live/99ef199d-276c-4858-3731-3230-6d61-63-8ae5-83cef40fc28bd/media_0.m3u8',
  'vs-benodet': 'https://ds2-cache.quanteec.com/contents/encodings/live/56caa721-02b2-4031-3430-3130-6d61-63-b9f9-f23307135ec5d/media_0.m3u8',
  'vs-penmarch': 'https://ds2-cache.quanteec.com/contents/encodings/live/068f1c25-1be9-4494-3439-3330-6d61-63-837f-3e21424f20a2d/media_0.m3u8',
  'vs-guilvinec': 'https://ds2-cache.quanteec.com/contents/encodings/live/7b24320f-47ce-4242-3333-3230-6d61-63-9244-9275136a96bdd/media_0.m3u8',
  'vs-crozon': 'https://ds2-cache.quanteec.com/contents/encodings/live/a57d6076-bcdd-4e1b-3738-3130-6d61-63-ba69-112b409efb73d/media_0.m3u8',
  'vs-pont-labbe': 'https://ds2-cache.quanteec.com/contents/encodings/live/927939d7-996a-4e66-3530-3430-6d61-63-b236-56683e39d5e9d/media_0.m3u8',
  'vs-paimpol': 'https://ds2-cache.quanteec.com/contents/encodings/live/8ca4ab2a-c52d-4198-3238-3330-6d61-63-ac39-531978ff7942d/media_0.m3u8',
  'vs-combrit': 'https://ds2-cache.quanteec.com/contents/encodings/live/2fe87ffd-1ac2-4f9c-3138-3130-6d61-63-9b25-a02ee9338d50d/media_0.m3u8',
  'vs-glenan': 'https://ds1-cache.quanteec.com/contents/encodings/live/f96e5f26-57d2-42ab-3239-3530-6d61-63-a7d3-96dd6b2ec090d/media_0.m3u8',
  // Bretagne - Morbihan / Loire-Atlantique
  'vs-croisic': 'https://ds2-cache.quanteec.com/contents/encodings/live/6bac6633-41ad-4dd8-3432-3330-6d61-63-afab-bfcab638ff8fd/media_0.m3u8',
  'vs-pouliguen': 'https://ds2-cache.quanteec.com/contents/encodings/live/94798048-1561-4a0a-3832-3330-6d61-63-8476-0a7d558c33d3d/media_0.m3u8',
  // Gironde / Landes
  'vs-lacanau': 'https://ds2-cache.quanteec.com/contents/encodings/live/67eb6464-055f-47cb-3730-3330-6d61-63-abc5-fa5259757cc4d/media_0.m3u8',
  'vs-arcachon': 'https://ds2-cache.quanteec.com/contents/encodings/live/001f0c90-60c6-4121-3134-3030-6d61-63-a2eb-acfa247e6c29d/media_0.m3u8',
  'vs-seignosse': 'https://ds2-cache.quanteec.com/contents/encodings/live/8da4aff9-9afb-47ce-3937-3430-6d61-63-b10b-bae5e6dead40d/media_0.m3u8',
  // Normandie
  'vs-le-havre': 'https://ds2-cache.quanteec.com/contents/encodings/live/c6ac4174-ee79-4e08-3632-3330-6d61-63-9efb-ce2d3fb197b0d/media_0.m3u8',
  'vs-dieppe': 'https://ds2-cache.quanteec.com/contents/encodings/live/41b8fbe2-cf49-4396-3139-3130-6d61-63-b29f-ad20fe94d576d/media_0.m3u8',
  'vs-siouville': 'https://ds2-cache.quanteec.com/contents/encodings/live/a89f3474-9d1c-40dd-3437-3230-6d61-63-a5fd-58da85d36f6cd/media_0.m3u8',
  'vs-goury': 'https://ds2-cache.quanteec.com/contents/encodings/live/ae1a4a8c-784b-4571-3537-3230-6d61-63-a65b-ceb2396bd8add/media_0.m3u8',
  'vs-barneville': 'https://ds2-cache.quanteec.com/contents/encodings/live/273a3e7a-b125-4cb1-3839-3030-6d61-63-a49f-22af76e7fbf2d/media_0.m3u8',
  // Hauts-de-France
  'sk-le-portel': 'https://skaping.quanteec.com/contents/encodings/live/4e8844cd-6cbb-40b3-746c-7561-6665-64-89d2-2cef5a933a84d/media_0.m3u8',
  'vs-dunkerque': 'https://ds2-cache.quanteec.com/contents/encodings/live/8d9f7a17-a395-4be6-3739-3130-6d61-63-b32b-4069d95be7a5d/media_0.m3u8',
  'vs-bray-dunes': 'https://ds2-cache.quanteec.com/contents/encodings/live/4e0100d6-7bc4-43be-3839-3130-6d61-63-bd66-bcfd64e27574d/media_0.m3u8',
  'vs-zuydcoote': 'https://ds2-cache.quanteec.com/contents/encodings/live/8f0170c0-1b41-48f9-3030-3230-6d61-63-98e4-bc495cd8d793d/media_0.m3u8',
  'vs-calais': 'https://ds2-cache.quanteec.com/contents/encodings/live/d5e9f551-7435-4ea6-3532-3130-6d61-63-916e-ff1d72543cced/media_0.m3u8',
  'vs-hardelot': 'https://ds2-cache.quanteec.com/contents/encodings/live/16d1ad82-49dc-491a-3433-3230-6d61-63-a59d-fc77596c2e6dd/media_0.m3u8',
  // Pays Basque
  'vs-anglet': 'https://ds2-cache.quanteec.com/contents/encodings/live/c56ac32d-4df6-4924-3430-3030-6d61-63-9e97-d84cc86e129bd/media_0.m3u8',
  // Côte d'Azur
  'vs-nice': 'https://ds2-cache.quanteec.com/contents/encodings/live/44325ee8-0cde-4f0c-3737-3330-6d61-63-a448-371421fe696ad/media_0.m3u8',
};

// Fetch health status from Blob storage
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
    // Blob doesn't exist yet - return all webcams as online
  }
  return null;
}

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Check if we should include all webcams (for health check)
  const includeAll = req.query.includeAll === 'true';

  try {
    // Skaping URL helper (uses our proxy with compression)
    // server param: 'data' (default), 'data2', 'data3', 's3' for different Skaping storage backends
    const skaping = (path, server = 'data') =>
      `https://api.levent.live/api/skaping?path=${encodeURIComponent(path)}${server !== 'data' ? `&server=${server}` : ''}`;

    // Viewsurf URL helper (uses our proxy with compression)
    const viewsurf = (id) =>
      `https://api.levent.live/api/viewsurf?id=${id}`;

    // Viewsurf Stream URL helper (for webcams with HLS streams - fresher images)
    const viewsurfStream = (streamId) =>
      `https://api.levent.live/api/viewsurf-stream?id=${streamId}`;

    // Vision-Environnement URL helper (uses our proxy with compression)
    const vision = (slug) =>
      `https://api.levent.live/api/vision?slug=${slug}`;

    // YouTube live webcam thumbnail helper
    const youtube = (videoId) =>
      `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`;

    // WindsUp webcam proxy helper (dynamic image URLs require scraping)
    const windsup = (camId) =>
      `https://api.levent.live/api/windsup-webcam?id=${camId}`;

    const webcams = [
      // ═══════════════════════════════════════════════════════════
      // SKAPING - BRETAGNE
      // ═══════════════════════════════════════════════════════════
      {
        id: "concarneau",
        name: "Concarneau Panoramique",
        location: "Concarneau",
        region: "Bretagne",
        latitude: 47.8735,
        longitude: -3.9214,
        imageUrl: skaping('concarneau/panoramique'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      {
        id: "concarneau-port",
        name: "Port de Concarneau",
        location: "Concarneau",
        region: "Bretagne",
        latitude: 47.8680,
        longitude: -3.9110,
        imageUrl: 'https://pubs.diabox.com/graphGeneration.php?data=cam_rt&lang=fr&size=large&id=115&lastData',
        streamUrl: null,
        source: "Diabox",
        refreshInterval: 300
      },
      { id: "sk-arzon-navalo", name: "Port Navalo", location: "Arzon", region: "Bretagne", latitude: 47.5479, longitude: -2.9182, imageUrl: skaping('arzon/port-navalo', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-arzon-crouesty", name: "Port du Crouesty", location: "Arzon", region: "Bretagne", latitude: 47.5429, longitude: -2.8947, imageUrl: skaping('port-du-crouesty/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-damgan", name: "Grande Plage", location: "Damgan", region: "Bretagne", latitude: 47.5177, longitude: -2.5830, imageUrl: skaping('damgan/grande-plage/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sarzeau", name: "Port Saint-Jacques", location: "Sarzeau", region: "Bretagne", latitude: 47.4862, longitude: -2.7918, imageUrl: skaping('sarzeau/port-saint-jacques', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-manech", name: "Port Manec'h SNSM", location: "Nevez", region: "Bretagne", latitude: 47.8002, longitude: -3.7381, imageUrl: skaping('snsm/port-manech/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-belon", name: "Port de Belon", location: "Moëlan-sur-Mer", region: "Bretagne", latitude: 47.8127, longitude: -3.7067, imageUrl: skaping('moelan-sur-mer/port-de-belon', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pont-aven", name: "Pont-Aven", location: "Pont-Aven", region: "Bretagne", latitude: 47.8534, longitude: -3.7479, imageUrl: skaping('pont-aven/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-plage", name: "Les Perdrix", location: "Loctudy", region: "Bretagne", latitude: 47.8358, longitude: -4.1697, imageUrl: skaping('loctudy/les-perdrix', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-port", name: "Port de Plaisance", location: "Loctudy", region: "Bretagne", latitude: 47.8371, longitude: -4.1766, imageUrl: skaping('loctudy/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-trebeurden", name: "Pors Termen", location: "Trébeurden", region: "Bretagne", latitude: 48.7731, longitude: -3.5840, imageUrl: skaping('trebeurden/porz-termen/plage', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient", name: "Rade Panoramique", location: "Lorient", region: "Bretagne", latitude: 47.7264, longitude: -3.3645, imageUrl: skaping('lorient/k3-la-base', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guidel", name: "Port de Plaisance", location: "Guidel", region: "Bretagne", latitude: 47.7724, longitude: -3.5285, imageUrl: skaping('port-de-plaisance/guidel/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lampaul", name: "La Corniche", location: "Lampaul-Plouarzel", region: "Bretagne", latitude: 48.4618, longitude: -4.7696, imageUrl: skaping('lampaul-plouarzel/la-corniche', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-brignogan", name: "Plage", location: "Plounéour-Brignogan", region: "Bretagne", latitude: 48.6664, longitude: -4.3261, imageUrl: skaping('plouneour-brignogan-plages', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-andre", name: "Casino Plage", location: "Pléneuf-Val-André", region: "Bretagne", latitude: 48.5909, longitude: -2.5530, imageUrl: skaping('pleneuf-val-andre/casino/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-la-foret", name: "Port La Forêt", location: "La Forêt-Fouesnant", region: "Bretagne", latitude: 47.8953, longitude: -3.9714, imageUrl: skaping('port-la-foret', 's3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morlaix-ile", name: "Île aux Dames", location: "Baie de Morlaix", region: "Bretagne", latitude: 48.6861, longitude: -3.8841, imageUrl: skaping('morlaix/ile-aux-dames/solaire', 's3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-trinite-sur-mer", name: "Port Panoramique", location: "La Trinité-sur-Mer", region: "Bretagne", latitude: 47.5861, longitude: -3.0292, imageUrl: skaping('port-de-la-trinite-sur-mer/pano'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-quiberon", name: "Panoramique", location: "Quiberon", region: "Bretagne", latitude: 47.4833, longitude: -3.1167, imageUrl: skaping('quiberon/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-malo-sablons", name: "Port des Sablons", location: "Saint-Malo", region: "Bretagne", latitude: 48.6497, longitude: -2.0261, imageUrl: skaping('saint-malo/port-des-sablons', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-briac", name: "Capitainerie", location: "Saint-Briac-sur-Mer", region: "Bretagne", latitude: 48.6208, longitude: -2.1361, imageUrl: skaping('saint-briac/capitainerie/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aber-wrach", name: "Sémaphore", location: "Landéda", region: "Bretagne", latitude: 48.6100, longitude: -4.5833, imageUrl: skaping('les-abers/semaphore-de-l-aber-wrac-h', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-du-vilh", name: "Port du Vilh", location: "Landéda", region: "Bretagne", latitude: 48.5900, longitude: -4.5700, imageUrl: skaping('les-abers/port-du-vilh/photo', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient-kernevel", name: "Port Kernevel", location: "Larmor-Plage", region: "Bretagne", latitude: 47.7200, longitude: -3.3500, imageUrl: skaping('lorient/rade/port-kernevel', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient-keroman", name: "Port Keroman", location: "Lorient", region: "Bretagne", latitude: 47.7300, longitude: -3.3600, imageUrl: skaping('lorient/rade/port-keroman', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-langoz", name: "Plage Langoz", location: "Loctudy", region: "Bretagne", latitude: 47.8345, longitude: -4.1750, imageUrl: skaping('loctudy/langoz', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lampaul-porspaul", name: "Porspaul", location: "Lampaul-Plouarzel", region: "Bretagne", latitude: 48.4530, longitude: -4.7730, imageUrl: skaping('lampaul-plouarzel/porspaul'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guidel-fort", name: "Fort du Loch", location: "Guidel", region: "Bretagne", latitude: 47.7600, longitude: -3.5000, imageUrl: skaping('lorient/guidel-fort-du-loch', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-quimper", name: "Quai de l'Odet", location: "Quimper", region: "Bretagne", latitude: 47.9950, longitude: -4.1000, imageUrl: skaping('quimper/quai-de-l-odet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - NORMANDIE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-granville", name: "Port", location: "Granville", region: "Normandie", latitude: 48.8347, longitude: -1.5951, imageUrl: skaping('8-milles-nautic/granville', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gouville", name: "Plage", location: "Gouville-sur-Mer", region: "Normandie", latitude: 49.0993, longitude: -1.6096, imageUrl: skaping('gouville/sur/mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-jullouville", name: "Plage", location: "Jullouville", region: "Normandie", latitude: 48.7731, longitude: -1.5566, imageUrl: skaping('8-milles-nautic/jullouville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-havre-port", name: "Port de Plaisance", location: "Le Havre", region: "Normandie", latitude: 49.4863, longitude: 0.1075, imageUrl: skaping('le-havre/port-de-plaisance', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - HAUTS-DE-FRANCE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-baie-somme", name: "Cap Hornu", location: "Saint-Valery-sur-Somme", region: "Hauts-de-France", latitude: 50.1903, longitude: 1.6116, imageUrl: skaping('baie-de-somme/cap-hornu'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-touquet", name: "Base Nord", location: "Le Touquet", region: "Hauts-de-France", latitude: 50.5367, longitude: 1.5942, imageUrl: skaping('le-touquet/base-nord', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-merlimont", name: "Plage", location: "Merlimont", region: "Hauts-de-France", latitude: 50.4629, longitude: 1.5725, imageUrl: skaping('merlimont/pano'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-portel", name: "Plage Live", location: "Le Portel", region: "Hauts-de-France", latitude: 50.7075, longitude: 1.5722, imageUrl: null, streamUrl: null, source: "Skaping", refreshInterval: 300 },
      { id: "sk-berck-authie", name: "Baie d'Authie", location: "Berck-sur-Mer", region: "Hauts-de-France", latitude: 50.4100, longitude: 1.5700, imageUrl: skaping('berck-sur-mer/baie-d-authie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-berck-eole", name: "Éole Kite", location: "Berck-sur-Mer", region: "Hauts-de-France", latitude: 50.3944, longitude: 1.5625, imageUrl: skaping('berck-sur-mer/eole'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-berck-mer", name: "Plage", location: "Berck-sur-Mer", region: "Hauts-de-France", latitude: 50.3900, longitude: 1.5550, imageUrl: skaping('berck-sur-mer/mer', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-touquet-sud", name: "Base Sud", location: "Le Touquet", region: "Hauts-de-France", latitude: 50.5205, longitude: 1.5942, imageUrl: skaping('le-touquet/base-sud'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-touquet-vue-mer", name: "Poste Central Vue Mer", location: "Le Touquet", region: "Hauts-de-France", latitude: 50.5244, longitude: 1.5847, imageUrl: skaping('le-touquet/poste-central/vue-mer', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - PAYS DE LA LOIRE / VENDÉE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-pornichet", name: "Plage", location: "Pornichet", region: "Pays de la Loire", latitude: 47.2645, longitude: -2.3449, imageUrl: skaping('pornichet/plage/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-govelle", name: "La Govelle", location: "Batz-sur-Mer", region: "Pays de la Loire", latitude: 47.2666, longitude: -2.4539, imageUrl: skaping('batz-sur-mer/la-govelle/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guerande", name: "Panoramique", location: "Guérande", region: "Pays de la Loire", latitude: 47.3275, longitude: -2.4264, imageUrl: skaping('guerande/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-noirmoutier-barbatre", name: "Plage de Barbâtre", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.9372, longitude: -2.1808, imageUrl: skaping('noirmoutier/plage-de-barbatre', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-du-bec", name: "Port du Bec", location: "Beauvoir-sur-Mer", region: "Pays de la Loire", latitude: 46.9356, longitude: -2.0713, imageUrl: skaping('port-du-bec', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-fromentine", name: "Centre Nautique", location: "La Barre-de-Monts", region: "Pays de la Loire", latitude: 46.8902, longitude: -2.1438, imageUrl: skaping('la-barre-de-monts/centre-nautique-360', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-batz-valentin", name: "Plage Valentin", location: "Batz-sur-Mer", region: "Pays de la Loire", latitude: 47.2666, longitude: -2.4539, imageUrl: skaping('batz-sur-mer/plage-valentin/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pornichet-surf", name: "Plage Surf", location: "Pornichet", region: "Pays de la Loire", latitude: 47.2645, longitude: -2.3449, imageUrl: skaping('pornichet/plage/surf', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pornic-port", name: "Port de Plaisance", location: "Pornic", region: "Pays de la Loire", latitude: 47.1133, longitude: -2.1017, imageUrl: skaping('pornic/port-de-plaisance', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-notre-dame-monts", name: "Plage Centrale", location: "Notre-Dame-de-Monts", region: "Pays de la Loire", latitude: 46.8358, longitude: -2.1338, imageUrl: skaping('notre-dame-de-monts/plage-centrale', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-st-jean-monts", name: "Front de Mer", location: "Saint-Jean-de-Monts", region: "Pays de la Loire", latitude: 46.7900, longitude: -2.0700, imageUrl: skaping('saint-jean-de-monts/front-de-mer/pano'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sables-olona", name: "Port Olona", location: "Les Sables-d'Olonne", region: "Pays de la Loire", latitude: 46.4958, longitude: -1.7867, imageUrl: skaping('sables-d-olonne/port-olona/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - CHARENTE-MARITIME / NOUVELLE-AQUITAINE
      // ═══════════════════════════════════════════════════════════
      {
        id: "larochelle",
        name: "Vieux Port Panoramique",
        location: "La Rochelle",
        region: "Nouvelle-Aquitaine",
        latitude: 46.1558,
        longitude: -1.1532,
        imageUrl: skaping('panoramiquelarochelle/panoramique'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      { id: "sk-larochelle-minimes", name: "Port des Minimes", location: "La Rochelle", region: "Nouvelle-Aquitaine", latitude: 46.1446, longitude: -1.1726, imageUrl: skaping('port-de-plaisance/la-rochelle/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-rivedoux", name: "Plage Nord", location: "Rivedoux-Plage", region: "Nouvelle-Aquitaine", latitude: 46.1595, longitude: -1.2723, imageUrl: skaping('rivedoux-salle-des-fetes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-porge", name: "Plage Océan", location: "Le Porge", region: "Nouvelle-Aquitaine", latitude: 44.8943, longitude: -1.2173, imageUrl: skaping('medoc-plein-sud/le-porge-ocean-plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-st-vincent-jard", name: "Panoramique", location: "Saint-Vincent-sur-Jard", region: "Pays de la Loire", latitude: 46.4167, longitude: -1.5333, imageUrl: skaping('saint-vincent-sur-jard/panoramique', 's3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-bourgenay", name: "Port Panoramique", location: "Talmont-Saint-Hilaire", region: "Pays de la Loire", latitude: 46.4456, longitude: -1.6872, imageUrl: skaping('port-bourgenay/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - LANGUEDOC-ROUSSILLON / OCCITANIE
      // ═══════════════════════════════════════════════════════════
      {
        id: "valras",
        name: "Plage de Valras",
        location: "Valras-Plage",
        region: "Occitanie",
        latitude: 43.2494,
        longitude: 3.2903,
        imageUrl: skaping('beziers/valras/plage'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      { id: "sk-port-la-nouvelle", name: "Port", location: "Port-la-Nouvelle", region: "Occitanie", latitude: 43.0139, longitude: 3.0652, imageUrl: skaping('port-la-nouvelle', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-narbonne-plage", name: "Plage", location: "Narbonne-Plage", region: "Occitanie", latitude: 43.1691, longitude: 3.1812, imageUrl: skaping('narbonne/plage', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-barcares", name: "Les Dousses", location: "Le Barcarès", region: "Occitanie", latitude: 42.7903, longitude: 3.0353, imageUrl: skaping('le-barcares/dousses'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gruissan", name: "Capitainerie", location: "Gruissan", region: "Occitanie", latitude: 43.1050, longitude: 3.0917, imageUrl: skaping('gruissan/capitainerie', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - CÔTE D'AZUR / PACA
      // ═══════════════════════════════════════════════════════════
      {
        id: "embiez",
        name: "Île des Embiez",
        location: "Six-Fours-les-Plages",
        region: "Provence-Alpes-Côte d'Azur",
        latitude: 43.0803,
        longitude: 5.7844,
        imageUrl: skaping('iles-des-embiez/chateau-d-eau'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      {
        id: "saint-cyr-madrague",
        name: "Port de la Madrague",
        location: "Saint-Cyr-sur-Mer",
        region: "Provence-Alpes-Côte d'Azur",
        latitude: 43.1833,
        longitude: 5.7064,
        imageUrl: skaping('saint-cyr-sur-mer/cs2'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      { id: "sk-mandelieu", name: "Panoramique", location: "Mandelieu-la-Napoule", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5340, longitude: 6.9509, imageUrl: skaping('mandelieu/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-mandelieu-mer", name: "Vue Mer", location: "Mandelieu-la-Napoule", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5300, longitude: 6.9400, imageUrl: skaping('mandelieu/mer', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-grimaud", name: "Capitainerie", location: "Port Grimaud", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2723, longitude: 6.5858, imageUrl: skaping('port-grimaud/capitainerie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-menton-sablettes", name: "Plage des Sablettes", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7750, longitude: 7.5000, imageUrl: skaping('menton/plage-des-sablettes/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-toulon-royale", name: "Tour Royale", location: "Toulon", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1167, longitude: 5.9333, imageUrl: skaping('toulon/tour-royale'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-marseille-wtc", name: "WTC Panoramique", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3123, longitude: 5.3676, imageUrl: skaping('marseille/world-trade-center'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // CORSE
      // ═══════════════════════════════════════════════════════════
      // Note: Skaping n'a pas encore de webcams installées en Corse

      // ═══════════════════════════════════════════════════════════
      // SKAPING - LACS
      // ═══════════════════════════════════════════════════════════
      { id: "sk-lac-bourget", name: "Port de Chatillon", location: "Lac du Bourget", region: "Auvergne-Rhône-Alpes", latitude: 45.6900, longitude: 5.8900, imageUrl: skaping('grand-lac/port-de-chatillon-360'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-aiguebelette", name: "Saint-Alban", location: "Lac d'Aiguebelette", region: "Auvergne-Rhône-Alpes", latitude: 45.5500, longitude: 5.7800, imageUrl: skaping('lac-d-aiguebelette/st-alban'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-serre-poncon", name: "Plage Embrun", location: "Lac de Serre-Ponçon", region: "Provence-Alpes-Côte d'Azur", latitude: 44.5600, longitude: 6.4900, imageUrl: skaping('lac-serre-poncon/plage-embrun', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-sainte-croix", name: "Bord de Lac", location: "Sainte-Croix-du-Verdon", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7700, longitude: 6.1500, imageUrl: skaping('sainte-croix-du-verdon/bord-de-lac'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - BRETAGNE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-carnac-pano", name: "Plage Panoramique", location: "Carnac", region: "Bretagne", latitude: 47.5833, longitude: -3.0833, imageUrl: viewsurf(5491), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-carnac-port", name: "Saint-Colomban", location: "Carnac", region: "Bretagne", latitude: 47.5822, longitude: -3.0789, imageUrl: viewsurf(18724), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-trinite", name: "Vieux Môle", location: "La Trinité-sur-Mer", region: "Bretagne", latitude: 47.5861, longitude: -3.0292, imageUrl: viewsurf(7326), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-benodet", name: "Panoramique HD", location: "Bénodet", region: "Bretagne", latitude: 47.8753, longitude: -4.1064, imageUrl: viewsurfStream('vs-benodet'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-penmarch", name: "La Torche", location: "Penmarch", region: "Bretagne", latitude: 47.8403, longitude: -4.3508, imageUrl: viewsurfStream('vs-penmarch'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-crozon", name: "Plage de Morgat", location: "Crozon-Morgat", region: "Bretagne", latitude: 48.2264, longitude: -4.5017, imageUrl: viewsurfStream('vs-crozon'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-dinard", name: "Panoramique HD", location: "Dinard", region: "Bretagne", latitude: 48.6328, longitude: -2.0700, imageUrl: viewsurf(18326), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-fouesnant-capi", name: "Capitainerie Beg Meil", location: "Fouesnant", region: "Bretagne", latitude: 47.8650, longitude: -3.9850, imageUrl: viewsurfStream('vs-fouesnant-capi'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-glenan", name: "Port Saint-Nicolas", location: "Îles de Glénan", region: "Bretagne", latitude: 47.7267, longitude: -3.9983, imageUrl: viewsurfStream('vs-glenan'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-guilvinec", name: "Le Port", location: "Guilvinec", region: "Bretagne", latitude: 47.7933, longitude: -4.2833, imageUrl: viewsurfStream('vs-guilvinec'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ile-tudy", name: "La Plage", location: "Île-Tudy", region: "Bretagne", latitude: 47.8417, longitude: -4.1667, imageUrl: viewsurf(18340), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-landeda", name: "Panoramique HD", location: "Landéda", region: "Bretagne", latitude: 48.5833, longitude: -4.5667, imageUrl: viewsurf(19280), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-belle-ile", name: "Le Palais", location: "Belle-Île-en-Mer", region: "Bretagne", latitude: 47.3500, longitude: -3.1500, imageUrl: viewsurf(16898), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-paimpol", name: "Panoramique HD", location: "Paimpol", region: "Bretagne", latitude: 48.7833, longitude: -3.0500, imageUrl: viewsurfStream('vs-paimpol'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-plouguerneau", name: "Phare Île Vierge", location: "Plouguerneau", region: "Bretagne", latitude: 48.6167, longitude: -4.5333, imageUrl: viewsurf(19278), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-combrit", name: "Le Port", location: "Combrit", region: "Bretagne", latitude: 47.8833, longitude: -4.1500, imageUrl: viewsurfStream('vs-combrit'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-pont-labbe", name: "Panoramique HD", location: "Pont-l'Abbé", region: "Bretagne", latitude: 47.8667, longitude: -4.2167, imageUrl: viewsurfStream('vs-pont-labbe'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-brieuc", name: "Panoramique HD", location: "Saint-Brieuc", region: "Bretagne", latitude: 48.5136, longitude: -2.7600, imageUrl: viewsurf(17650), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-gildas", name: "Plage Kerfago", location: "Saint-Gildas-de-Rhuys", region: "Bretagne", latitude: 47.5000, longitude: -2.8333, imageUrl: viewsurf(11030), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-plestin", name: "Plage Saint-Efflam", location: "Plestin-les-Grèves", region: "Bretagne", latitude: 48.6667, longitude: -3.6333, imageUrl: viewsurf(19308), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - NORMANDIE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-etretat", name: "Falaises Nord", location: "Étretat", region: "Normandie", latitude: 49.7069, longitude: 0.2061, imageUrl: viewsurf(17574), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-le-havre", name: "Le Port", location: "Le Havre", region: "Normandie", latitude: 49.4944, longitude: 0.1078, imageUrl: viewsurfStream('vs-le-havre'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-dieppe", name: "La Plage", location: "Dieppe", region: "Normandie", latitude: 49.9256, longitude: 1.0828, imageUrl: viewsurfStream('vs-dieppe'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-barneville", name: "Le Port", location: "Barneville-Carteret", region: "Normandie", latitude: 49.3833, longitude: -1.7833, imageUrl: viewsurfStream('vs-barneville'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-siouville", name: "La Plage", location: "Siouville-Hague", region: "Normandie", latitude: 49.5667, longitude: -1.8333, imageUrl: viewsurfStream('vs-siouville'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-goury", name: "Sémaphore", location: "La Hague", region: "Normandie", latitude: 49.7167, longitude: -1.9500, imageUrl: viewsurfStream('vs-goury'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cherbourg", name: "Plage Collignon", location: "Cherbourg", region: "Normandie", latitude: 49.6500, longitude: -1.6167, imageUrl: viewsurf(19376), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-courseulles", name: "Le Port", location: "Courseulles-sur-Mer", region: "Normandie", latitude: 49.3333, longitude: -0.4500, imageUrl: viewsurf(19414), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-trouville", name: "Port Deauville", location: "Trouville-sur-Mer", region: "Normandie", latitude: 49.3653, longitude: 0.0786, imageUrl: viewsurf(19416), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - PAYS DE LA LOIRE / VENDÉE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-sables-olonne", name: "Tanchet Surf", location: "Les Sables-d'Olonne", region: "Pays de la Loire", latitude: 46.4833, longitude: -1.7833, imageUrl: viewsurf(4517), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-pornic", name: "Panoramique HD", location: "Pornic", region: "Pays de la Loire", latitude: 47.1133, longitude: -2.1017, imageUrl: viewsurf(18510), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ile-yeu", name: "Entrée du Port", location: "L'Île-d'Yeu", region: "Pays de la Loire", latitude: 46.7269, longitude: -2.3483, imageUrl: viewsurf(17598), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-gilles", name: "La Plage", location: "Saint-Gilles-Croix-de-Vie", region: "Pays de la Loire", latitude: 46.6833, longitude: -1.9333, imageUrl: viewsurf(4733), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-tranche", name: "La Plage", location: "La Tranche-sur-Mer", region: "Pays de la Loire", latitude: 46.3500, longitude: -1.4333, imageUrl: viewsurf(18790), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-faute", name: "La Plage", location: "La Faute-sur-Mer", region: "Pays de la Loire", latitude: 46.3167, longitude: -1.3167, imageUrl: viewsurf(17880), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-croisic", name: "Le Port", location: "Le Croisic", region: "Pays de la Loire", latitude: 47.2917, longitude: -2.5167, imageUrl: viewsurfStream('vs-croisic'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-pouliguen", name: "La Jetée", location: "Le Pouliguen", region: "Pays de la Loire", latitude: 47.2667, longitude: -2.4333, imageUrl: viewsurfStream('vs-pouliguen'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-turballe", name: "Panoramique HD", location: "La Turballe", region: "Pays de la Loire", latitude: 47.3500, longitude: -2.5167, imageUrl: viewsurf(18708), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-brevin", name: "Les Rochelets", location: "Saint-Brevin-les-Pins", region: "Pays de la Loire", latitude: 47.2500, longitude: -2.1667, imageUrl: viewsurf(13178), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-prefailles", name: "Le Port", location: "Préfailles", region: "Pays de la Loire", latitude: 47.1333, longitude: -2.2167, imageUrl: viewsurf(16906), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-michel", name: "Panoramique HD", location: "Saint-Michel-Chef-Chef", region: "Pays de la Loire", latitude: 47.1833, longitude: -2.1500, imageUrl: viewsurf(16910), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-grand-lieu", name: "Lac de Grand-Lieu", location: "La Chevrolière", region: "Pays de la Loire", latitude: 47.0500, longitude: -1.6167, imageUrl: viewsurf(18460), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - NOUVELLE-AQUITAINE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-lacanau", name: "Plage Centrale", location: "Lacanau", region: "Nouvelle-Aquitaine", latitude: 45.0000, longitude: -1.2000, imageUrl: viewsurfStream('vs-lacanau'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-carcans", name: "La Plage", location: "Carcans", region: "Nouvelle-Aquitaine", latitude: 45.1000, longitude: -1.1833, imageUrl: viewsurf(1255), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-hossegor", name: "La Plage", location: "Soorts-Hossegor", region: "Nouvelle-Aquitaine", latitude: 43.6667, longitude: -1.4000, imageUrl: viewsurf(2058), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-mimizan", name: "Plage Sud", location: "Mimizan", region: "Nouvelle-Aquitaine", latitude: 44.2167, longitude: -1.2833, imageUrl: viewsurf(731), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-capbreton", name: "Le Quai", location: "Capbreton", region: "Nouvelle-Aquitaine", latitude: 43.6419, longitude: -1.4333, imageUrl: viewsurf(19380), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-biscarrosse", name: "Plage Nord", location: "Biscarrosse", region: "Nouvelle-Aquitaine", latitude: 44.4500, longitude: -1.2500, imageUrl: viewsurf(11530), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-seignosse", name: "La Plage", location: "Seignosse", region: "Nouvelle-Aquitaine", latitude: 43.6833, longitude: -1.4167, imageUrl: viewsurfStream('vs-seignosse'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-moliets", name: "Plage Nord", location: "Moliets-et-Maa", region: "Nouvelle-Aquitaine", latitude: 43.8500, longitude: -1.3833, imageUrl: viewsurf(14302), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-contis", name: "La Plage", location: "Contis", region: "Nouvelle-Aquitaine", latitude: 44.0833, longitude: -1.3167, imageUrl: viewsurf(17346), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ondres", name: "La Plage", location: "Ondres", region: "Nouvelle-Aquitaine", latitude: 43.5667, longitude: -1.4833, imageUrl: viewsurf(5892), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-anglet", name: "Plage des Cavaliers", location: "Anglet", region: "Nouvelle-Aquitaine", latitude: 43.5044, longitude: -1.5372, imageUrl: viewsurfStream('vs-anglet'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-jean-luz", name: "Plage Donibane", location: "Saint-Jean-de-Luz", region: "Nouvelle-Aquitaine", latitude: 43.3833, longitude: -1.6667, imageUrl: viewsurf(12734), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-arcachon", name: "Le Bassin", location: "Arcachon", region: "Nouvelle-Aquitaine", latitude: 44.6500, longitude: -1.1667, imageUrl: viewsurfStream('vs-arcachon'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-andernos", name: "Panoramique", location: "Andernos-les-Bains", region: "Nouvelle-Aquitaine", latitude: 44.7500, longitude: -1.1000, imageUrl: viewsurf(6772), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-hourtin", name: "Le Port", location: "Hourtin", region: "Nouvelle-Aquitaine", latitude: 45.1833, longitude: -1.0667, imageUrl: viewsurf(18164), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-soulac", name: "La Plage", location: "Soulac-sur-Mer", region: "Nouvelle-Aquitaine", latitude: 45.5000, longitude: -1.1333, imageUrl: viewsurf(15744), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-montalivet", name: "La Plage", location: "Vendays-Montalivet", region: "Nouvelle-Aquitaine", latitude: 45.3833, longitude: -1.1500, imageUrl: viewsurf(13902), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-salie", name: "La Plage", location: "La Teste-de-Buch", region: "Nouvelle-Aquitaine", latitude: 44.5667, longitude: -1.2167, imageUrl: viewsurf(18468), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-sanguinet", name: "Lac Panoramique", location: "Sanguinet", region: "Nouvelle-Aquitaine", latitude: 44.4833, longitude: -1.0833, imageUrl: viewsurf(12268), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-arjuzanx", name: "Le Lac", location: "Arjuzanx", region: "Nouvelle-Aquitaine", latitude: 44.0167, longitude: -0.8667, imageUrl: viewsurf(17542), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - CHARENTE-MARITIME
      // ═══════════════════════════════════════════════════════════
      { id: "vs-chatelaillon", name: "Le Port", location: "Châtelaillon-Plage", region: "Nouvelle-Aquitaine", latitude: 46.0833, longitude: -1.0833, imageUrl: viewsurf(19098), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-royan", name: "Plage Pontaillac", location: "Royan", region: "Nouvelle-Aquitaine", latitude: 45.6333, longitude: -1.0333, imageUrl: viewsurf(18404), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-meschers", name: "Panoramique HD", location: "Meschers-sur-Gironde", region: "Nouvelle-Aquitaine", latitude: 45.5500, longitude: -0.9500, imageUrl: viewsurf(18842), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-georges", name: "La Plage", location: "Saint-Georges-de-Didonne", region: "Nouvelle-Aquitaine", latitude: 45.6000, longitude: -1.0000, imageUrl: viewsurf(14524), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-tremblade", name: "Côte Sauvage", location: "La Tremblade", region: "Nouvelle-Aquitaine", latitude: 45.7667, longitude: -1.1333, imageUrl: viewsurf(18408), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - OCCITANIE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-grau-du-roi", name: "Panoramique", location: "Le Grau-du-Roi", region: "Occitanie", latitude: 43.5333, longitude: 4.1333, imageUrl: viewsurf(11774), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-balaruc", name: "Le Port", location: "Balaruc-les-Bains", region: "Occitanie", latitude: 43.4417, longitude: 3.6750, imageUrl: viewsurf(16072), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-palavas", name: "Rive Droite", location: "Palavas-les-Flots", region: "Occitanie", latitude: 43.5333, longitude: 3.9333, imageUrl: viewsurf(18402), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cap-agde", name: "Centre Nautique", location: "Cap d'Agde", region: "Occitanie", latitude: 43.2833, longitude: 3.5167, imageUrl: viewsurf(6948), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-marseillan", name: "Le Port", location: "Marseillan", region: "Occitanie", latitude: 43.3500, longitude: 3.5333, imageUrl: viewsurf(13874), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-frontignan", name: "Étang Ingril", location: "Frontignan", region: "Occitanie", latitude: 43.4500, longitude: 3.7500, imageUrl: viewsurf(6906), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-canet", name: "Zone Kite Surf", location: "Canet-en-Roussillon", region: "Occitanie", latitude: 42.7000, longitude: 3.0333, imageUrl: viewsurf(11046), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-argeles", name: "Panoramique HD", location: "Argelès-sur-Mer", region: "Occitanie", latitude: 42.5500, longitude: 3.0333, imageUrl: viewsurf(12748), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-collioure", name: "Vue Port", location: "Collioure", region: "Occitanie", latitude: 42.5250, longitude: 3.0833, imageUrl: viewsurf(11108), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-banyuls", name: "Plage Centrale", location: "Banyuls-sur-Mer", region: "Occitanie", latitude: 42.4833, longitude: 3.1333, imageUrl: viewsurf(13892), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-port-vendres", name: "Panoramique", location: "Port-Vendres", region: "Occitanie", latitude: 42.5167, longitude: 3.1167, imageUrl: viewsurf(11768), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-leucate", name: "Le Port", location: "Leucate", region: "Occitanie", latitude: 42.9167, longitude: 3.0333, imageUrl: viewsurf(17040), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-bouillouses", name: "Lac des Bouillouses", location: "Les Angles", region: "Occitanie", latitude: 42.5500, longitude: 2.0833, imageUrl: viewsurf(12756), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - PROVENCE-ALPES-CÔTE D'AZUR
      // ═══════════════════════════════════════════════════════════
      { id: "vs-nice", name: "Baie des Anges", location: "Nice", region: "Provence-Alpes-Côte d'Azur", latitude: 43.6958, longitude: 7.2653, imageUrl: viewsurfStream('vs-nice'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-antibes", name: "Port Vauban", location: "Antibes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5808, longitude: 7.1283, imageUrl: viewsurf(18258), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cannes", name: "La Croisette", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5500, longitude: 7.0167, imageUrl: viewsurf(18150), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-menton", name: "Panoramique HD", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7750, longitude: 7.5000, imageUrl: viewsurf(17702), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-tropez", name: "Le Port", location: "Saint-Tropez", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2667, longitude: 6.6333, imageUrl: viewsurf(19428), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ste-maxime", name: "Vue Saint-Tropez", location: "Sainte-Maxime", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3167, longitude: 6.6333, imageUrl: viewsurf(11328), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-frejus", name: "La Plage", location: "Fréjus", region: "Provence-Alpes-Côte d'Azur", latitude: 43.4333, longitude: 6.7333, imageUrl: viewsurf(18360), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-raphael", name: "La Plage", location: "Saint-Raphaël", region: "Provence-Alpes-Côte d'Azur", latitude: 43.4167, longitude: 6.7667, imageUrl: viewsurf(16184), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cavalaire", name: "La Plage", location: "Cavalaire-sur-Mer", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1667, longitude: 6.5333, imageUrl: viewsurf(14296), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-lavandou", name: "Le Port", location: "Le Lavandou", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1333, longitude: 6.3667, imageUrl: viewsurf(10514), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cassis", name: "Le Port", location: "Cassis", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2144, longitude: 5.5372, imageUrl: viewsurf(18662), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-la-ciotat", name: "Vieux Port", location: "La Ciotat", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1833, longitude: 5.6000, imageUrl: viewsurf(6802), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-le-pradet", name: "Port Oursinières", location: "Le Pradet", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1000, longitude: 6.0167, imageUrl: viewsurf(17386), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cap-dail", name: "Panoramique", location: "Cap-d'Ail", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7167, longitude: 7.4000, imageUrl: viewsurf(19318), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-golfe-juan", name: "Le Port", location: "Vallauris", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5667, longitude: 7.0667, imageUrl: viewsurf(18180), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ile-levant", name: "L'Île", location: "Île du Levant", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0333, longitude: 6.4667, imageUrl: viewsurf(19374), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - NORD / HAUTS-DE-FRANCE
      // ═══════════════════════════════════════════════════════════
      { id: "vs-calais", name: "La Plage", location: "Calais", region: "Hauts-de-France", latitude: 50.9500, longitude: 1.8500, imageUrl: viewsurfStream('vs-calais'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-dunkerque", name: "La Plage", location: "Dunkerque", region: "Hauts-de-France", latitude: 51.0333, longitude: 2.3667, imageUrl: viewsurfStream('vs-dunkerque'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-bray-dunes", name: "Plage Est", location: "Bray-Dunes", region: "Hauts-de-France", latitude: 51.0667, longitude: 2.5333, imageUrl: viewsurfStream('vs-bray-dunes'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-zuydcoote", name: "Panoramique HD", location: "Zuydcoote", region: "Hauts-de-France", latitude: 51.0667, longitude: 2.4833, imageUrl: viewsurfStream('vs-zuydcoote'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-hardelot", name: "La Plage", location: "Neufchâtel-Hardelot", region: "Hauts-de-France", latitude: 50.6333, longitude: 1.5833, imageUrl: viewsurfStream('vs-hardelot'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cucq", name: "La Plage", location: "Cucq", region: "Hauts-de-France", latitude: 50.4667, longitude: 1.6167, imageUrl: viewsurf(16024), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VIEWSURF - LACS
      // ═══════════════════════════════════════════════════════════
      { id: "vs-miramas", name: "Étang de Berre", location: "Miramas", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5833, longitude: 5.0000, imageUrl: viewsurf(18508), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - BRETAGNE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-st-malo", name: "Panoramique", location: "Saint-Malo", region: "Bretagne", latitude: 48.6497, longitude: -2.0261, imageUrl: vision('saint-malo'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-cast", name: "La Plage", location: "Saint-Cast-le-Guildo", region: "Bretagne", latitude: 48.6333, longitude: -2.2500, imageUrl: vision('stcast'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-erquy", name: "Le Port", location: "Erquy", region: "Bretagne", latitude: 48.6333, longitude: -2.4667, imageUrl: vision('erquy'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-binic", name: "Le Port", location: "Binic", region: "Bretagne", latitude: 48.6000, longitude: -2.8333, imageUrl: vision('binic'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-quay", name: "Le Port", location: "Saint-Quay-Portrieux", region: "Bretagne", latitude: 48.6500, longitude: -2.8167, imageUrl: vision('sqpp'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-perros-port", name: "Le Port", location: "Perros-Guirec", region: "Bretagne", latitude: 48.8167, longitude: -3.4333, imageUrl: vision('portperrosguirec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-perros-trestraou", name: "Trestraou", location: "Perros-Guirec", region: "Bretagne", latitude: 48.8167, longitude: -3.4333, imageUrl: vision('trestraou'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ploumanach", name: "Le Port", location: "Ploumanac'h", region: "Bretagne", latitude: 48.8333, longitude: -3.4833, imageUrl: vision('portploumanach'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-tregastel", name: "La Plage", location: "Trégastel", region: "Bretagne", latitude: 48.8167, longitude: -3.5000, imageUrl: vision('tregastel'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-locquirec", name: "La Plage", location: "Locquirec", region: "Bretagne", latitude: 48.6833, longitude: -3.6500, imageUrl: vision('locquirec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lannion", name: "La Ville", location: "Lannion", region: "Bretagne", latitude: 48.7333, longitude: -3.4500, imageUrl: vision('lannion'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-plouescat", name: "La Plage", location: "Plouescat", region: "Bretagne", latitude: 48.6500, longitude: -4.1667, imageUrl: vision('plouescat'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-carantec", name: "La Plage", location: "Carantec", region: "Bretagne", latitude: 48.6667, longitude: -3.9167, imageUrl: vision('carantec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-roscoff", name: "Le Port", location: "Roscoff", region: "Bretagne", latitude: 48.7167, longitude: -3.9833, imageUrl: vision('roscoff'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-batz", name: "L'Île", location: "Île de Batz", region: "Bretagne", latitude: 48.7500, longitude: -4.0167, imageUrl: vision('iledebatz'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-pol", name: "La Baie", location: "Saint-Pol-de-Léon", region: "Bretagne", latitude: 48.6833, longitude: -3.9833, imageUrl: vision('stpol'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-morlaix", name: "Le Port", location: "Morlaix", region: "Bretagne", latitude: 48.5833, longitude: -3.8333, imageUrl: vision('morlaix'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-brest-port", name: "Le Port", location: "Brest", region: "Bretagne", latitude: 48.3833, longitude: -4.4833, imageUrl: vision('brest-port'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-landeda", name: "Aber Wrac'h", location: "Landéda", region: "Bretagne", latitude: 48.5833, longitude: -4.5667, imageUrl: vision('landeda'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-portsall", name: "Le Port", location: "Ploudalmézeau", region: "Bretagne", latitude: 48.5667, longitude: -4.7000, imageUrl: vision('portsall'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-conquet", name: "Kermorvan", location: "Le Conquet", region: "Bretagne", latitude: 48.3667, longitude: -4.7833, imageUrl: vision('leconquet'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-plougonvelin", name: "La Côte", location: "Plougonvelin", region: "Bretagne", latitude: 48.3500, longitude: -4.7167, imageUrl: vision('plougonvelin'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-sein", name: "L'Île", location: "Île de Sein", region: "Bretagne", latitude: 48.0333, longitude: -4.8500, imageUrl: vision('ile-de-sein'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-pointe-raz", name: "Pointe du Raz", location: "Plogoff", region: "Bretagne", latitude: 48.0333, longitude: -4.7333, imageUrl: vision('pointe-du-raz'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-audierne-port", name: "Le Port", location: "Audierne", region: "Bretagne", latitude: 48.0167, longitude: -4.5333, imageUrl: vision('audierne-port'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-esquibien", name: "Le Pouldu", location: "Esquibien", region: "Bretagne", latitude: 48.0000, longitude: -4.5500, imageUrl: vision('esquibien-le-pouldu'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-douarnenez-port", name: "Port Rosmeur", location: "Douarnenez", region: "Bretagne", latitude: 48.1000, longitude: -4.3333, imageUrl: vision('douarnenez-rosmeur'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-douarnenez-plage", name: "Sables Blancs", location: "Douarnenez", region: "Bretagne", latitude: 48.1000, longitude: -4.3333, imageUrl: vision('douarnenez'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-houat", name: "L'Île", location: "Île de Houat", region: "Bretagne", latitude: 47.3833, longitude: -2.9500, imageUrl: vision('houat'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-penestin", name: "La Plage", location: "Pénestin", region: "Bretagne", latitude: 47.4667, longitude: -2.4667, imageUrl: vision('penestin'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-piriac", name: "Le Port", location: "Piriac-sur-Mer", region: "Bretagne", latitude: 47.3833, longitude: -2.5500, imageUrl: vision('piriac-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-bono", name: "Le Port", location: "Le Bono", region: "Bretagne", latitude: 47.6333, longitude: -2.9333, imageUrl: vision('le-bono'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gavres", name: "Port de Gâvres", location: "Larmor-Plage", region: "Bretagne", latitude: 47.6833, longitude: -3.3500, imageUrl: vision('gavres'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - NORMANDIE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-etretat", name: "Les Falaises", location: "Étretat", region: "Normandie", latitude: 49.7069, longitude: 0.2061, imageUrl: vision('etretat'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-fecamp", name: "Le Port", location: "Fécamp", region: "Normandie", latitude: 49.7500, longitude: 0.3667, imageUrl: vision('fecam'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-havre", name: "Fort Tourneville", location: "Le Havre", region: "Normandie", latitude: 49.4944, longitude: 0.1078, imageUrl: vision('tourneville'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-valery", name: "La Plage", location: "Saint-Valery-en-Caux", region: "Normandie", latitude: 49.8667, longitude: 0.7167, imageUrl: vision('saint-valery-en-caux-casino'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-dieppe", name: "La Plage", location: "Dieppe", region: "Normandie", latitude: 49.9256, longitude: 1.0828, imageUrl: vision('dieppe-ango'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-treport", name: "Le Port", location: "Le Tréport", region: "Normandie", latitude: 50.0667, longitude: 1.3833, imageUrl: vision('letreport'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-trouville", name: "Le Port", location: "Trouville-sur-Mer", region: "Normandie", latitude: 49.3653, longitude: 0.0786, imageUrl: vision('port-trouville-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cabourg", name: "Promenade Marcel Proust", location: "Cabourg", region: "Normandie", latitude: 49.2833, longitude: -0.1167, imageUrl: vision('cabourg2-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-houlgate", name: "La Plage", location: "Houlgate", region: "Normandie", latitude: 49.3000, longitude: -0.0833, imageUrl: vision('houlgate'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ouistreham", name: "Le Port", location: "Ouistreham", region: "Normandie", latitude: 49.2833, longitude: -0.2500, imageUrl: vision('ouistreham'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-langrune", name: "La Plage", location: "Langrune-sur-Mer", region: "Normandie", latitude: 49.3167, longitude: -0.3667, imageUrl: vision('langrune-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-luc-sur-mer", name: "La Plage", location: "Luc-sur-Mer", region: "Normandie", latitude: 49.3167, longitude: -0.3500, imageUrl: vision('luc-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-aubin", name: "La Plage", location: "Saint-Aubin-sur-Mer", region: "Normandie", latitude: 49.3333, longitude: -0.3833, imageUrl: vision('staubin'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-jullouville", name: "La Plage", location: "Jullouville", region: "Normandie", latitude: 48.7667, longitude: -1.5667, imageUrl: vision('jullouville'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-pirou", name: "La Plage", location: "Pirou", region: "Normandie", latitude: 49.1667, longitude: -1.5833, imageUrl: vision('pirou'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-germain", name: "La Plage", location: "Saint-Germain-sur-Ay", region: "Normandie", latitude: 49.2333, longitude: -1.6333, imageUrl: vision('stgermain'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - HAUTS-DE-FRANCE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-boulogne", name: "Le Port", location: "Boulogne-sur-Mer", region: "Hauts-de-France", latitude: 50.7333, longitude: 1.6000, imageUrl: vision('boulogne'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-wimereux", name: "La Plage", location: "Wimereux", region: "Hauts-de-France", latitude: 50.7667, longitude: 1.6167, imageUrl: vision('wimereux'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-wissant", name: "La Plage", location: "Wissant", region: "Hauts-de-France", latitude: 50.8833, longitude: 1.6667, imageUrl: vision('wissant'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-sangatte", name: "La Plage", location: "Sangatte", region: "Hauts-de-France", latitude: 50.9333, longitude: 1.7667, imageUrl: vision('sangatte'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gravelines", name: "Le Port", location: "Gravelines", region: "Hauts-de-France", latitude: 51.0000, longitude: 2.1333, imageUrl: vision('gravelines'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - PAYS DE LA LOIRE / VENDÉE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-la-baule", name: "La Plage", location: "La Baule", region: "Pays de la Loire", latitude: 47.2833, longitude: -2.3833, imageUrl: vision('labaule'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-noirmoutier", name: "Le Bois de la Chaize", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.9986, longitude: -2.2458, imageUrl: vision('noirmoutier'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gois", name: "Passage du Gois", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.9333, longitude: -2.1333, imageUrl: vision('gois'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-herbaudiere", name: "L'Herbaudière", location: "Noirmoutier", region: "Pays de la Loire", latitude: 47.0167, longitude: -2.3000, imageUrl: vision('herbaudiere'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-hilaire", name: "La Plage", location: "Saint-Hilaire-de-Riez", region: "Pays de la Loire", latitude: 46.7333, longitude: -1.9500, imageUrl: vision('sthilairederiez'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-jard", name: "La Plage", location: "Jard-sur-Mer", region: "Pays de la Loire", latitude: 46.4167, longitude: -1.5833, imageUrl: vision('jardsurmer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-la-tranche", name: "La Plage", location: "La Tranche-sur-Mer", region: "Pays de la Loire", latitude: 46.3500, longitude: -1.4333, imageUrl: vision('latranche'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CHARENTE-MARITIME
      // ═══════════════════════════════════════════════════════════
      { id: "ve-bourcefranc", name: "Le Port", location: "Bourcefranc-le-Chapus", region: "Nouvelle-Aquitaine", latitude: 45.8500, longitude: -1.1667, imageUrl: vision('bourcefranc'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-cotiniere", name: "La Cotinière", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 45.9167, longitude: -1.3333, imageUrl: vision('cotiniere'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-chassiron", name: "Phare Chassiron", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 46.0500, longitude: -1.4167, imageUrl: vision('chassiron'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-perroche", name: "La Perroche", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 45.8667, longitude: -1.2333, imageUrl: vision('perroche'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-huttes", name: "Les Huttes", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 45.9500, longitude: -1.3833, imageUrl: vision('oleron-les-huttes'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-trojan", name: "La Plage", location: "Saint-Trojan-les-Bains", region: "Nouvelle-Aquitaine", latitude: 45.8333, longitude: -1.2167, imageUrl: vision('saint-trojan-les-bains'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CÔTE D'AZUR / PACA
      // ═══════════════════════════════════════════════════════════
      { id: "ve-menton", name: "La Baie", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7750, longitude: 7.5000, imageUrl: vision('menton'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-villefranche", name: "La Rade", location: "Villefranche-sur-Mer", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7000, longitude: 7.3167, imageUrl: vision('villefranche-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-laurent", name: "La Plage", location: "Saint-Laurent-du-Var", region: "Provence-Alpes-Côte d'Azur", latitude: 43.6667, longitude: 7.1833, imageUrl: vision('saint-laurent-du-var'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cannes", name: "Plage Thales", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5500, longitude: 7.0167, imageUrl: vision('cannes'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cannes-quai", name: "Quai Laubeuf", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5500, longitude: 7.0167, imageUrl: vision('cannes-quai-laubeuf'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-issambres", name: "La Plage", location: "Les Issambres", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3333, longitude: 6.6833, imageUrl: vision('issambres'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres", name: "L'Almanarre", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0667, longitude: 6.1333, imageUrl: vision('hyeres3-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres-kite", name: "Plage Estagniers", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0667, longitude: 6.1333, imageUrl: vision('Hyeres-kite'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres-port", name: "Port Saint-Pierre", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0833, longitude: 6.1500, imageUrl: vision('hyeres2-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-mandrier", name: "Le Port", location: "Saint-Mandrier", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0833, longitude: 5.9333, imageUrl: vision('saint-mandrier'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-six-fours", name: "La Plage", location: "Six-Fours-les-Plages", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1000, longitude: 5.8167, imageUrl: vision('sixfours2'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-toulon", name: "Vieille Darse", location: "Toulon", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1167, longitude: 5.9333, imageUrl: vision('toulon-vieille-darse'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lavandou", name: "Aiguebelle", location: "Le Lavandou", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1333, longitude: 6.3667, imageUrl: vision('lavandou-aiguebelle'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-carro", name: "Le Port", location: "Carro", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3333, longitude: 5.0333, imageUrl: vision('carro'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-marseille-port", name: "Vieux Port", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2950, longitude: 5.3700, imageUrl: vision('marseilleport'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-marseille-samena", name: "Calanque Samena", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2333, longitude: 5.3500, imageUrl: vision('samena'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-sete", name: "Le Port", location: "Sète", region: "Occitanie", latitude: 43.4000, longitude: 3.7000, imageUrl: vision('sete'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CORSE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-ajaccio-port", name: "Port Tino Rossi", location: "Ajaccio", region: "Corse", latitude: 41.9167, longitude: 8.7333, imageUrl: vision('ajaccioport2'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ajaccio-pano", name: "Panoramique", location: "Ajaccio", region: "Corse", latitude: 41.9167, longitude: 8.7333, imageUrl: vision('ajaccio-panorama'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-bastia", name: "Le Port", location: "Bastia", region: "Corse", latitude: 42.7000, longitude: 9.4500, imageUrl: vision('bastia'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-bonifacio", name: "Le Port", location: "Bonifacio", region: "Corse", latitude: 41.3833, longitude: 9.1500, imageUrl: vision('bonifacio'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-propriano", name: "Le Port", location: "Propriano", region: "Corse", latitude: 41.6667, longitude: 8.9000, imageUrl: vision('propriano'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cargese", name: "Le Port", location: "Cargèse", region: "Corse", latitude: 42.1333, longitude: 8.6000, imageUrl: vision('cargese'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-rousse", name: "La Plage", location: "L'Île-Rousse", region: "Corse", latitude: 42.6333, longitude: 8.9333, imageUrl: vision('ile-rousse'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-porto-vecchio", name: "Santa Giulia", location: "Porto-Vecchio", region: "Corse", latitude: 41.5833, longitude: 9.2833, imageUrl: vision('santa-giulia'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-porto-vecchio-port", name: "Port Commerce", location: "Porto-Vecchio", region: "Corse", latitude: 41.5833, longitude: 9.2833, imageUrl: vision('portportovecchio'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - LACS
      // ═══════════════════════════════════════════════════════════
      { id: "ve-lac-madine", name: "Lac de Madine", location: "Nonsard-Lamarche", region: "Grand Est", latitude: 48.9333, longitude: 5.7167, imageUrl: vision('lac-de-madine'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lac-settons", name: "Lac des Settons", location: "Montsauche-les-Settons", region: "Bourgogne-Franche-Comté", latitude: 47.2000, longitude: 4.0667, imageUrl: vision('lac-des-settons'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lac-st-point", name: "Lac Saint-Point", location: "Malbuisson", region: "Bourgogne-Franche-Comté", latitude: 46.8000, longitude: 6.3000, imageUrl: vision('malbuisson'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // WINDSUP - WEBCAMS SPOTS
      // ═══════════════════════════════════════════════════════════
      // Normandie / Manche
      { id: "wu-asnelles", name: "Poste de secours", location: "Asnelles", region: "Normandie", latitude: 49.338, longitude: -0.583, imageUrl: windsup('130'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-jullouville", name: "Jullouville", location: "Jullouville", region: "Normandie", latitude: 48.767, longitude: -1.553, imageUrl: windsup('109'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-ouistreham", name: "Colleville", location: "Ouistreham", region: "Normandie", latitude: 49.277, longitude: -0.249, imageUrl: windsup('24'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // Nord / Hauts-de-France
      { id: "wu-berck", name: "Berck", location: "Berck", region: "Hauts-de-France", latitude: 50.405, longitude: 1.558, imageUrl: windsup('57'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // Bretagne
      { id: "wu-quiberon", name: "Quiberon", location: "Quiberon", region: "Bretagne", latitude: 47.551, longitude: -3.133, imageUrl: windsup('41'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // Aquitaine
      { id: "wu-sanguinet", name: "Sanguinet", location: "Sanguinet", region: "Nouvelle-Aquitaine", latitude: 44.483, longitude: -1.083, imageUrl: windsup('46'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // Occitanie
      { id: "wu-gruissan", name: "Gruissan", location: "Gruissan", region: "Occitanie", latitude: 43.110, longitude: 3.125, imageUrl: windsup('23'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-franqui", name: "Poste des Coussoules", location: "La Franqui", region: "Occitanie", latitude: 42.928, longitude: 3.007, imageUrl: windsup('1554'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-ganguise", name: "La Ganguise", location: "La Ganguise", region: "Occitanie", latitude: 43.342, longitude: 1.859, imageUrl: windsup('21'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-grande-motte", name: "La Grande-Motte", location: "La Grande-Motte", region: "Occitanie", latitude: 43.553, longitude: 4.084, imageUrl: windsup('135'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-nautique", name: "La Nautique", location: "Narbonne", region: "Occitanie", latitude: 43.156, longitude: 2.975, imageUrl: windsup('1572'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-les-aresquiers", name: "Étang d'Ingril", location: "Les Aresquiers", region: "Occitanie", latitude: 43.457, longitude: 3.749, imageUrl: windsup('3'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-saint-cyprien", name: "Saint Cyprien", location: "Saint-Cyprien", region: "Occitanie", latitude: 42.624, longitude: 3.031, imageUrl: windsup('83'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // PACA
      { id: "wu-carro", name: "Carro", location: "Martigues", region: "PACA", latitude: 43.331, longitude: 5.039, imageUrl: windsup('5'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-fos", name: "Plage Ouest", location: "Fos-sur-Mer", region: "PACA", latitude: 43.422, longitude: 4.940, imageUrl: windsup('1530'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-ciotat", name: "La Ciotat", location: "La Ciotat", region: "PACA", latitude: 43.174, longitude: 5.607, imageUrl: windsup('118'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-la-coudouliere", name: "La Coudoulière", location: "Six-Fours", region: "PACA", latitude: 43.083, longitude: 5.820, imageUrl: windsup('86'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-le-jai", name: "Le Jaï", location: "Marignane", region: "PACA", latitude: 43.396, longitude: 5.154, imageUrl: windsup('26'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-le-pradet", name: "Garonne", location: "Le Pradet", region: "PACA", latitude: 43.098, longitude: 6.029, imageUrl: windsup('1536'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-marseille", name: "Pointe Rouge Digue", location: "Marseille", region: "PACA", latitude: 43.246, longitude: 5.364, imageUrl: windsup('44'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-rognac", name: "Base Nautique", location: "Rognac", region: "PACA", latitude: 43.489, longitude: 5.230, imageUrl: windsup('1561'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-saint-cyr", name: "Saint Cyr les Lecques", location: "Saint-Cyr-sur-Mer", region: "PACA", latitude: 43.182, longitude: 5.700, imageUrl: windsup('14'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-saint-laurent", name: "Saint Laurent du Var", location: "Saint-Laurent-du-Var", region: "PACA", latitude: 43.667, longitude: 7.186, imageUrl: windsup('29'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      { id: "wu-six-fours", name: "Le Brusc", location: "Six-Fours", region: "PACA", latitude: 43.072, longitude: 5.807, imageUrl: windsup('49'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },
      // Centre
      { id: "wu-poitiers", name: "Base de loisirs St Cyr", location: "Poitiers", region: "Nouvelle-Aquitaine", latitude: 46.588, longitude: 0.355, imageUrl: windsup('1541'), streamUrl: null, source: "WindsUp", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // YOUTUBE - LIVE WEBCAMS (via SkylineWebcams)
      // ═══════════════════════════════════════════════════════════
      { id: "yt-mers-les-bains", name: "Plage", location: "Mers-les-Bains", region: "Hauts-de-France", latitude: 50.0658, longitude: 1.3867, imageUrl: youtube('Kq_9wTO0dhU'), streamUrl: 'https://www.youtube.com/embed/Kq_9wTO0dhU?autoplay=1&mute=1', source: "YouTube", refreshInterval: 300 },
      { id: "yt-le-treport", name: "Plage", location: "Le Tréport", region: "Normandie", latitude: 50.0597, longitude: 1.3722, imageUrl: youtube('8bRtD3VVbLY'), streamUrl: 'https://www.youtube.com/embed/8bRtD3VVbLY?autoplay=1&mute=1', source: "YouTube", refreshInterval: 300 },
      { id: "yt-jard-sur-mer", name: "Côte", location: "Jard-sur-Mer", region: "Pays de la Loire", latitude: 46.4142, longitude: -1.5764, imageUrl: youtube('5LTeT_ANQv4'), streamUrl: 'https://www.youtube.com/embed/5LTeT_ANQv4?autoplay=1&mute=1', source: "YouTube", refreshInterval: 300 },
      { id: "yt-villefranche", name: "Port", location: "Villefranche-sur-Mer", region: "PACA", latitude: 43.6958, longitude: 7.3103, imageUrl: youtube('zkEdGueUrek'), streamUrl: 'https://www.youtube.com/embed/zkEdGueUrek?autoplay=1&mute=1', source: "YouTube", refreshInterval: 300 },
    ];

    // Merge KV overrides (admin edits) and additions
    let mergedWebcams = [...webcams];
    try {
      const [overrides, additions] = await Promise.all([
        kv.hgetall('webcam_overrides'),
        kv.hgetall('webcam_additions')
      ]);

      if (overrides) {
        mergedWebcams = mergedWebcams.map(w => {
          const ov = overrides[w.id];
          if (!ov) return w;
          const parsed = typeof ov === 'string' ? JSON.parse(ov) : ov;
          if (parsed._hidden) return null;
          return { ...w, ...parsed };
        }).filter(Boolean);
      }

      if (additions) {
        for (const data of Object.values(additions)) {
          const parsed = typeof data === 'string' ? JSON.parse(data) : data;
          mergedWebcams.push(parsed);
        }
      }
    } catch (e) {
      // KV unavailable - use hardcoded list
      console.error('KV merge failed:', e.message);
    }

    // Populate streamUrl from QUANTEEC_STREAMS mapping (fallback only)
    // If admin set a streamUrl via KV override, it takes priority
    mergedWebcams = mergedWebcams.map(w => {
      if (w.streamUrl) return w;
      const streamUrl = QUANTEEC_STREAMS[w.id];
      if (streamUrl) {
        return { ...w, streamUrl };
      }
      return w;
    });

    // Auto-transform imageUrl for webcams with HLS streams (Quanteec)
    // This ensures webcams with Quanteec streams automatically get frame capture
    mergedWebcams = mergedWebcams.map(w => {
      if (!w.streamUrl?.includes('quanteec')) return w;
      if (w.imageUrl?.includes('viewsurf-stream') && w.imageUrl?.includes('streamUrl=')) return w;
      // Apply to Viewsurf webcams or any webcam with null/missing imageUrl
      if (w.source !== 'Viewsurf' && w.imageUrl) return w;

      // Transform imageUrl to use viewsurf-stream with the streamUrl parameter
      const encodedStreamUrl = encodeURIComponent(w.streamUrl);
      return {
        ...w,
        imageUrl: `https://api.levent.live/api/viewsurf-stream?id=${w.id}&streamUrl=${encodedStreamUrl}`
      };
    });

    // Filter webcams based on health status (unless includeAll is true)
    if (includeAll) {
      return res.status(200).json(mergedWebcams);
    }

    // Get health status and filter offline webcams
    const healthData = await getHealthStatus();

    if (!healthData || !healthData.webcams) {
      // No health data yet - return all webcams
      return res.status(200).json(mergedWebcams);
    }

    // Filter out offline webcams and attach lastCapture timestamp
    const onlineWebcams = mergedWebcams.filter(webcam => {
      // HLS webcams (with streamUrl) are always considered online — health check can't reliably test them
      if (webcam.streamUrl) return true;
      const status = healthData.webcams[webcam.id];
      // If no status for this webcam, assume it's online (new webcam)
      if (!status) return true;
      // Return only online webcams
      return status.online !== false;
    }).map(webcam => {
      const status = healthData.webcams[webcam.id];
      return {
        ...webcam,
        lastCapture: status?.lastSuccess || null,
      };
    });

    console.log(`Webcams: ${onlineWebcams.length}/${mergedWebcams.length} online`);
    res.status(200).json(onlineWebcams);
  } catch (error) {
    console.error('Webcams API error:', error);
    res.status(500).json({ error: 'Failed to fetch webcams' });
  }
}
