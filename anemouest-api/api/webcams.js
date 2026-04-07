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
        latitude: 47.87008560,
        longitude: -3.91108990,
        imageUrl: skaping('concarneau'),
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
      { id: "sk-arzon-navalo", name: "Port Navalo", location: "Arzon", region: "Bretagne", latitude: 47.5479, longitude: -2.9182, imageUrl: skaping('arzon/port-navalo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-arzon-crouesty", name: "Port du Crouesty", location: "Arzon", region: "Bretagne", latitude: 47.5429, longitude: -2.8947, imageUrl: skaping('port-du-crouesty/panoramique', 'data3'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-damgan", name: "Grande Plage", location: "Damgan", region: "Bretagne", latitude: 47.5177, longitude: -2.5830, imageUrl: skaping('damgan/grande-plage/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-manech", name: "Port Manec'h SNSM", location: "Nevez", region: "Bretagne", latitude: 47.8002, longitude: -3.7381, imageUrl: skaping('snsm/port-manech'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-belon", name: "Port de Belon", location: "Moëlan-sur-Mer", region: "Bretagne", latitude: 47.8127, longitude: -3.7067, imageUrl: skaping('moelan-sur-mer/port-de-belon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pont-aven", name: "Pont-Aven", location: "Pont-Aven", region: "Bretagne", latitude: 47.8534, longitude: -3.7479, imageUrl: skaping('pont-aven/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-plage", name: "Les Perdrix", location: "Loctudy", region: "Bretagne", latitude: 47.8358, longitude: -4.1697, imageUrl: skaping('loctudy/les-perdrix'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-port", name: "Port de Plaisance", location: "Loctudy", region: "Bretagne", latitude: 47.8371, longitude: -4.1766, imageUrl: skaping('loctudy/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-trebeurden", name: "Pors Termen", location: "Trébeurden", region: "Bretagne", latitude: 48.7731, longitude: -3.5840, imageUrl: skaping('trebeurden/pors-termen/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient", name: "Rade Panoramique", location: "Lorient", region: "Bretagne", latitude: 47.75138300, longitude: -3.50963000, imageUrl: skaping('lorient/guidel-fort-du-loch'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guidel", name: "Port de Plaisance", location: "Guidel", region: "Bretagne", latitude: 47.71136800, longitude: -3.35671900, imageUrl: skaping('port-de-plaisance/port-louis'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lampaul", name: "La Corniche", location: "Lampaul-Plouarzel", region: "Bretagne", latitude: 48.4618, longitude: -4.7696, imageUrl: skaping('lampaul-plouarzel/la-corniche'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-brignogan", name: "Plage", location: "Plounéour-Brignogan", region: "Bretagne", latitude: 48.6664, longitude: -4.3261, imageUrl: skaping('plouneour-brignogan-plages'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-andre", name: "Casino Plage", location: "Pléneuf-Val-André", region: "Bretagne", latitude: 48.5909, longitude: -2.5530, imageUrl: skaping('pleneuf-val-andre/casino'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-la-foret", name: "Port La Forêt", location: "La Forêt-Fouesnant", region: "Bretagne", latitude: 47.89907300, longitude: -3.97391000, imageUrl: skaping('port-la-foret'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morlaix-ile", name: "Île aux Dames", location: "Baie de Morlaix", region: "Bretagne", latitude: 48.6861, longitude: -3.8841, imageUrl: skaping('morlaix/ile-aux-dames'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-trinite-sur-mer", name: "Port Panoramique", location: "La Trinité-sur-Mer", region: "Bretagne", latitude: 47.5861, longitude: -3.0292, imageUrl: skaping('port-de-la-trinite-sur-mer/pano'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-quiberon", name: "Panoramique", location: "Quiberon", region: "Bretagne", latitude: 47.47929500, longitude: -3.11778300, imageUrl: skaping('quiberon/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-malo-sablons", name: "Port des Sablons", location: "Saint-Malo", region: "Bretagne", latitude: 48.63812600, longitude: -2.02701600, imageUrl: skaping('saint-malo/port-des-sablons'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-briac", name: "Capitainerie", location: "Saint-Briac-sur-Mer", region: "Bretagne", latitude: 48.62510313, longitude: -2.13843886, imageUrl: skaping('saint-briac/capitainerie/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aber-wrach", name: "Sémaphore", location: "Landéda", region: "Bretagne", latitude: 48.62474146, longitude: -4.56627836, imageUrl: skaping('les-abers/pointe-de-castel-ac-h/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-du-vilh", name: "Port du Vilh", location: "Landéda", region: "Bretagne", latitude: 48.57518921, longitude: -4.60868378, imageUrl: skaping('les-abers/port-du-vilh/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient-kernevel", name: "Port Kernevel", location: "Larmor-Plage", region: "Bretagne", latitude: 47.72641700, longitude: -3.36452000, imageUrl: skaping('lorient/rade/port-kernevel'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lorient-keroman", name: "Port Keroman", location: "Lorient", region: "Bretagne", latitude: 47.72641700, longitude: -3.36452000, imageUrl: skaping('lorient/rade/port-keroman'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loctudy-langoz", name: "Plage Langoz", location: "Loctudy", region: "Bretagne", latitude: 47.82935400, longitude: -4.16190000, imageUrl: skaping('loctudy/langoz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lampaul-porspaul", name: "Porspaul", location: "Lampaul-Plouarzel", region: "Bretagne", latitude: 48.44586400, longitude: -4.77688100, imageUrl: skaping('lampaul-plouarzel/porspaul'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-quimper", name: "Quai de l'Odet", location: "Quimper", region: "Bretagne", latitude: 47.99373400, longitude: -4.10616700, imageUrl: skaping('quimper/quai-de-l-odet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - NORMANDIE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-granville", name: "Port", location: "Granville", region: "Normandie", latitude: 48.8347, longitude: -1.5951, imageUrl: skaping('8-milles-nautic/granville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gouville", name: "Plage", location: "Gouville-sur-Mer", region: "Normandie", latitude: 49.0993, longitude: -1.6096, imageUrl: skaping('gouville/sur/mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-jullouville", name: "Plage", location: "Jullouville", region: "Normandie", latitude: 48.77085980, longitude: -1.57000959, imageUrl: skaping('8-milles-nautic/jullouville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-havre-port", name: "Port de Plaisance", location: "Le Havre", region: "Normandie", latitude: 49.48984338, longitude: 0.09710133, imageUrl: skaping('le-havre/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - HAUTS-DE-FRANCE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-baie-somme", name: "Cap Hornu", location: "Saint-Valery-sur-Somme", region: "Hauts-de-France", latitude: 50.1903, longitude: 1.6116, imageUrl: skaping('baie-de-somme/cap-hornu'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-touquet", name: "Base Nord", location: "Le Touquet", region: "Hauts-de-France", latitude: 50.5367, longitude: 1.5942, imageUrl: skaping('le-touquet/base-nord'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-merlimont", name: "Plage", location: "Merlimont", region: "Hauts-de-France", latitude: 50.4629, longitude: 1.5725, imageUrl: skaping('merlimont'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-portel", name: "Plage Live", location: "Le Portel", region: "Hauts-de-France", latitude: 50.7075, longitude: 1.5722, imageUrl: null, streamUrl: null, source: "Skaping", refreshInterval: 300 },
      { id: "sk-berck-authie", name: "Baie d'Authie", location: "Berck-sur-Mer", region: "Hauts-de-France", latitude: 50.39461300, longitude: 1.56085500, imageUrl: skaping('berck-sur-mer/baie-d-authie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-berck-eole", name: "Éole Kite", location: "Berck-sur-Mer", region: "Hauts-de-France", latitude: 50.41167468, longitude: 1.56187713, imageUrl: skaping('berck-sur-mer/eole'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-touquet-sud", name: "Base Sud", location: "Le Touquet", region: "Hauts-de-France", latitude: 50.51694900, longitude: 1.57864200, imageUrl: skaping('le-touquet/base-sud'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - PAYS DE LA LOIRE / VENDÉE
      // ═══════════════════════════════════════════════════════════
      { id: "sk-pornichet", name: "Plage", location: "Pornichet", region: "Pays de la Loire", latitude: 47.2645, longitude: -2.3449, imageUrl: skaping('pornichet/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-govelle", name: "La Govelle", location: "Batz-sur-Mer", region: "Pays de la Loire", latitude: 47.26655700, longitude: -2.45394200, imageUrl: skaping('batz-sur-mer/la-govelle'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guerande", name: "Panoramique", location: "Guérande", region: "Pays de la Loire", latitude: 47.3275, longitude: -2.4264, imageUrl: skaping('guerande/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-noirmoutier-barbatre", name: "Plage de Barbâtre", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.9372, longitude: -2.1808, imageUrl: skaping('noirmoutier/plage-de-barbatre'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-du-bec", name: "Port du Bec", location: "Beauvoir-sur-Mer", region: "Pays de la Loire", latitude: 46.9356, longitude: -2.0713, imageUrl: skaping('port-du-bec'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-fromentine", name: "Centre Nautique", location: "La Barre-de-Monts", region: "Pays de la Loire", latitude: 46.8902, longitude: -2.1438, imageUrl: skaping('la-barre-de-monts/centre-nautique-360'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-batz-valentin", name: "Plage Valentin", location: "Batz-sur-Mer", region: "Pays de la Loire", latitude: 47.27887100, longitude: -2.49517500, imageUrl: skaping('batz-sur-mer/plage-valentin/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pornic-port", name: "Port de Plaisance", location: "Pornic", region: "Pays de la Loire", latitude: 47.11042300, longitude: -2.11207213, imageUrl: skaping('pornic/port-de-plaisance/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-st-jean-monts", name: "Front de Mer", location: "Saint-Jean-de-Monts", region: "Pays de la Loire", latitude: 46.78865100, longitude: -2.08437900, imageUrl: skaping('saint-jean-de-monts/base-nautique-360'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sables-olona", name: "Port Olona", location: "Les Sables-d'Olonne", region: "Pays de la Loire", latitude: 46.50156300, longitude: -1.78846800, imageUrl: skaping('sables-d-olonne/port-olona/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

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
      { id: "sk-larochelle-minimes", name: "Port des Minimes", location: "La Rochelle", region: "Nouvelle-Aquitaine", latitude: 47.71136800, longitude: -3.35671900, imageUrl: skaping('port-de-plaisance/port-louis'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-rivedoux", name: "Plage Nord", location: "Rivedoux-Plage", region: "Nouvelle-Aquitaine", latitude: 46.1595, longitude: -1.2723, imageUrl: skaping('rivedoux-salle-des-fetes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-porge", name: "Plage Océan", location: "Le Porge", region: "Nouvelle-Aquitaine", latitude: 44.89474390, longitude: -1.21720752, imageUrl: skaping('medoc-plein-sud/le-porge-ocean/live'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-st-vincent-jard", name: "Panoramique", location: "Saint-Vincent-sur-Jard", region: "Pays de la Loire", latitude: 46.40694070, longitude: -1.54670119, imageUrl: skaping('saint-vincent-sur-jard/plage-clemenceau'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-bourgenay", name: "Port Panoramique", location: "Talmont-Saint-Hilaire", region: "Pays de la Loire", latitude: 46.43894370, longitude: -1.67706192, imageUrl: skaping('port-bourgenay/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

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
      { id: "sk-port-la-nouvelle", name: "Port", location: "Port-la-Nouvelle", region: "Occitanie", latitude: 43.0139, longitude: 3.0652, imageUrl: skaping('port-la-nouvelle'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-narbonne-plage", name: "Plage", location: "Narbonne-Plage", region: "Occitanie", latitude: 43.1691, longitude: 3.1812, imageUrl: skaping('narbonne/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gruissan", name: "Capitainerie", location: "Gruissan", region: "Occitanie", latitude: 43.10759100, longitude: 3.09926500, imageUrl: skaping('gruissan/capitainerie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

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
        imageUrl: skaping('saint-cyr-sur-mer'),
        streamUrl: null,
        source: "Skaping",
        refreshInterval: 600
      },
      { id: "sk-mandelieu", name: "Panoramique", location: "Mandelieu-la-Napoule", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5340, longitude: 6.9509, imageUrl: skaping('mandelieu/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-port-grimaud", name: "Capitainerie", location: "Port Grimaud", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2723, longitude: 6.5858, imageUrl: skaping('port-grimaud/capitainerie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-menton-sablettes", name: "Plage des Sablettes", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.77719400, longitude: 7.50943200, imageUrl: skaping('menton/plage-des-sablettes/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-marseille-wtc", name: "WTC Panoramique", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3123, longitude: 5.3676, imageUrl: skaping('marseille/world-trade-center'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // CORSE
      // ═══════════════════════════════════════════════════════════
      // Note: Skaping n'a pas encore de webcams installées en Corse

      // ═══════════════════════════════════════════════════════════
      // SKAPING - LACS
      // ═══════════════════════════════════════════════════════════
      { id: "sk-lac-bourget", name: "Port de Chatillon", location: "Lac du Bourget", region: "Auvergne-Rhône-Alpes", latitude: 45.79898700, longitude: 5.84435500, imageUrl: skaping('grand-lac/port-de-chatillon-360'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-aiguebelette", name: "Saint-Alban", location: "Lac d'Aiguebelette", region: "Auvergne-Rhône-Alpes", latitude: 45.55145200, longitude: 5.78422400, imageUrl: skaping('lac-d-aiguebelette/st-alban'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-serre-poncon", name: "Plage Embrun", location: "Lac de Serre-Ponçon", region: "Provence-Alpes-Côte d'Azur", latitude: 44.55061200, longitude: 6.47693500, imageUrl: skaping('lac-serre-poncon/plage-embrun'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-sainte-croix", name: "Bord de Lac", location: "Sainte-Croix-du-Verdon", region: "Provence-Alpes-Côte d'Azur", latitude: 43.76007989, longitude: 6.15593791, imageUrl: skaping('sainte-croix-du-verdon/bord-de-lac'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

      // ═══════════════════════════════════════════════════════════
      // SKAPING - AUTO-ADDED FROM API
      // ═══════════════════════════════════════════════════════════
      { id: "sk-agon-coutainville", name: "Agon-Coutainville", location: "Agon-Coutainville", region: "France", latitude: 49.04819190, longitude: -1.60121441, imageUrl: skaping('coutances/agon-coutainville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aiguines-lac-de-sainte-croix", name: "Aiguines - Lac de Sainte Croix", location: "Aiguines", region: "France", latitude: 43.77687600, longitude: 6.24368400, imageUrl: skaping('aiguines'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-2100m", name: "Alpe d'Huez - 2100m", location: "Alpe d'Huez", region: "France", latitude: 45.10509100, longitude: 6.08402400, imageUrl: skaping('alpedhuez/2100m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-2700m", name: "Alpe d'Huez - 2700m", location: "Alpe d'Huez", region: "France", latitude: 45.11792000, longitude: 6.10382200, imageUrl: skaping('alpedhuez/2700m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-3060m", name: "Alpe d'Huez - 3060m", location: "Alpe d'Huez", region: "France", latitude: 45.11395300, longitude: 6.11997900, imageUrl: skaping('alpedhuez/3060m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-herpie", name: "Alpe d'Huez - Herpie", location: "Alpe d'Huez", region: "France", latitude: 45.10534600, longitude: 6.12523600, imageUrl: skaping('alpedhuez/herpie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-le-signal", name: "Alpe d'Huez - Le Signal", location: "Alpe d'Huez", region: "France", latitude: 45.10027800, longitude: 6.05978000, imageUrl: skaping('alpedhuez/lesignal'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-alpe-d-huez-pic-blanc", name: "Alpe d'Huez - Pic Blanc", location: "Alpe d'Huez", region: "France", latitude: 45.12499300, longitude: 6.12729300, imageUrl: skaping('alpedhuez/pic-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-amboise-ch-teau-gaillard", name: "Amboise - Château Gaillard", location: "Amboise", region: "France", latitude: 47.40933413, longitude: 0.99875271, imageUrl: skaping('amboise/chateau-gaillard'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-amboise-la-pagode", name: "Amboise - La Pagode", location: "Amboise", region: "France", latitude: 47.39088846, longitude: 0.97233832, imageUrl: skaping('amboise/la-pagode'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-amboise-quais-de-loire", name: "Amboise - Quais de Loire", location: "Amboise", region: "France", latitude: 47.41746506, longitude: 0.98116941, imageUrl: skaping('amboise-quais-loire/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-angers-la-villa", name: "Angers - La Villa", location: "Angers", region: "France", latitude: 47.46848900, longitude: -0.56339300, imageUrl: skaping('angers/panorama'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-anglet-chambre-d-amour", name: "Anglet - Chambre d'Amour", location: "Anglet", region: "France", latitude: 43.49961000, longitude: -1.54314240, imageUrl: skaping('anglet/chambre-d-amour'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-anz-re-pas-de-maimbr", name: "Anzère - Pas de Maimbré", location: "Anzère", region: "France", latitude: 46.31208605, longitude: 7.38607407, imageUrl: skaping('anzere/pas-de-maimbre'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-arb-ost-col-du-soulor", name: "Arbéost - Col du Soulor", location: "Arbéost", region: "France", latitude: 42.96112445, longitude: -0.26121497, imageUrl: skaping('arbeost/col-du-soulor'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-arradon-port-de-plaisance", name: "Arradon - Port de plaisance", location: "Arradon", region: "France", latitude: 47.61611307, longitude: -2.82748403, imageUrl: skaping('port-arradon/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aubagne-place-de-l-glise", name: "Aubagne - Place de l'Église", location: "Aubagne", region: "France", latitude: 43.29350871, longitude: 5.57029903, imageUrl: skaping('aubagne/centre'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-auris-signal-de-l-homme", name: "Auris - Signal de l'Homme", location: "Auris", region: "France", latitude: 45.06766700, longitude: 6.08512400, imageUrl: skaping('alpedhuez/auris'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-auris-station", name: "Auris - Station", location: "Auris", region: "France", latitude: 45.05693400, longitude: 6.07867200, imageUrl: skaping('alpedhuez/auris-station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aussois-domaine-nordique-du-monolithe", name: "Aussois - Domaine nordique du Monolithe", location: "Aussois", region: "France", latitude: 45.24188357, longitude: 6.77830696, imageUrl: skaping('aussois/domaine-nordique-du-monolithe'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aussois-front-de-neige", name: "Aussois - Front de neige", location: "Aussois", region: "France", latitude: 45.23200542, longitude: 6.74041271, imageUrl: skaping('aussois/front-de-neige/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aussois-le-village", name: "Aussois - Le Village", location: "Aussois", region: "France", latitude: 45.22788870, longitude: 6.74148560, imageUrl: skaping('aussois/le-village'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aussois-sommet-de-l-armoise", name: "Aussois - Sommet de l'Armoise", location: "Aussois", region: "France", latitude: 45.26239745, longitude: 6.73723698, imageUrl: skaping('aussois/sommet-armoise'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-aussois-sommet-grand-jeu", name: "Aussois - Sommet Grand Jeu", location: "Aussois", region: "France", latitude: 45.24852345, longitude: 6.73582077, imageUrl: skaping('aussois/sommet-grand-jeu'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-autun", name: "Autun", location: "Autun", region: "France", latitude: 46.93401540, longitude: 4.28706050, imageUrl: skaping('autun/panorama'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-avoriaz-arare", name: "Avoriaz - Arare", location: "Avoriaz", region: "France", latitude: 46.17944000, longitude: 6.77786200, imageUrl: skaping('portes-du-soleil/avoriaz/arare'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-avoriaz-fornet", name: "Avoriaz - Fornet", location: "Avoriaz", region: "France", latitude: 46.16536313, longitude: 6.79433048, imageUrl: skaping('avoriaz/fornet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-avoriaz-pistes", name: "Avoriaz - Pistes", location: "Avoriaz", region: "France", latitude: 46.19354800, longitude: 6.77317700, imageUrl: skaping('avoriaz/pistes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-avoriaz-station", name: "Avoriaz - Station", location: "Avoriaz", region: "France", latitude: 46.19248600, longitude: 6.77360900, imageUrl: skaping('avoriaz/station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-ballon-d-alsace-front-de-neige", name: "Ballon d'Alsace - Front de neige", location: "Ballon d'Alsace", region: "France", latitude: 47.80092807, longitude: 6.85017407, imageUrl: skaping('ballon-d-alsace/front-de-neige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-ballon-d-alsace-sommet-t-l-ski", name: "Ballon d'Alsace - Sommet téléski", location: "Ballon d'Alsace", region: "France", latitude: 47.80658781, longitude: 6.85109052, imageUrl: skaping('ballon-d-alsace/sommet-teleski'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bar-ges-la-mongie-liaison", name: "Barèges - La Mongie - Liaison", location: "Barèges", region: "France", latitude: 42.90565200, longitude: 0.14732500, imageUrl: skaping('grandtourmalet/liaison'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bar-ges-laquette-1700m", name: "Barèges - Laquette - 1700m", location: "Barèges", region: "France", latitude: 42.89575100, longitude: 0.09159100, imageUrl: skaping('grandtourmalet/laquette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bar-ges-lienz-1500m", name: "Barèges - Lienz - 1500m", location: "Barèges", region: "France", latitude: 42.89490700, longitude: 0.07868300, imageUrl: skaping('grandtourmalet/baregeslienz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bar-ges-tourmalet", name: "Barèges - Tourmalet", location: "Barèges", region: "France", latitude: 42.90562300, longitude: 0.13028800, imageUrl: skaping('grandtourmalet/baregestourmalet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bar-ges-tournaboup-1450m", name: "Barèges - Tournaboup - 1450m", location: "Barèges", region: "France", latitude: 42.90345500, longitude: 0.10310800, imageUrl: skaping('grandtourmalet/baregestournaboup'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-beauvais-cath-drale-saint-pierre", name: "Beauvais - Cathédrale Saint-Pierre", location: "Beauvais", region: "France", latitude: 49.43149504, longitude: 2.08256364, imageUrl: skaping('beauvais/cathedrale-saint-pierre'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-blois-observatoire-loire", name: "Blois - Observatoire Loire", location: "Blois", region: "France", latitude: 47.59872000, longitude: 1.36033700, imageUrl: skaping('blois-chambord/observatoire-loire-pano'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-blois-pont-quai-villebois", name: "Blois - Pont & Quai Villebois", location: "Blois", region: "France", latitude: 47.58403200, longitude: 1.33899900, imageUrl: skaping('blois-chambord/pont-jacques-gabriel'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-bourg-l-s-valence-parc-girodet", name: "Bourg lès Valence - Parc Girodet", location: "Bourg lès Valence", region: "France", latitude: 44.94329603, longitude: 4.88628388, imageUrl: skaping('bourg-les-valence/parc-girodet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-brian-on-cit-vauban", name: "Briançon - Cité Vauban", location: "Briançon", region: "France", latitude: 44.89997511, longitude: 6.64425552, imageUrl: skaping('serre-chevalier/briancon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cambre-d-aze-eyne", name: "Cambre d'Aze - Eyne", location: "Cambre d'Aze", region: "France", latitude: 42.47272300, longitude: 2.10486200, imageUrl: skaping('cambredaze/eyne'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cambre-d-aze-pla", name: "Cambre d'Aze - Pla", location: "Cambre d'Aze", region: "France", latitude: 42.47265400, longitude: 2.11821400, imageUrl: skaping('cambredaze/pla'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cauterets-cascade-pont-d-espagne", name: "Cauterets - Cascade Pont d'Espagne", location: "Cauterets", region: "France", latitude: 42.85111000, longitude: -0.13969800, imageUrl: skaping('cauterets/pontdespagne'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cauterets-cirque-du-lys", name: "Cauterets - Cirque du Lys", location: "Cauterets", region: "France", latitude: 42.88241400, longitude: -0.15586500, imageUrl: skaping('cauterets/cirque-du-lys/panorama'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cauterets-les-cr-tes", name: "Cauterets - Les Crêtes", location: "Cauterets", region: "France", latitude: 42.88170732, longitude: -0.17417192, imageUrl: skaping('cauterets/les-cretes/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cauterets-village", name: "Cauterets - Village", location: "Cauterets", region: "France", latitude: 42.89098800, longitude: -0.11351100, imageUrl: skaping('cauterets/village'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cauterets-casino", name: "Cauterets - Casino", location: "Cauterets", region: "France", latitude: 42.88690366, longitude: -0.11454105, imageUrl: skaping('cauterets/village/casino'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chalets-d-iraty", name: "Chalets d'Iraty", location: "Chalets d'Iraty", region: "France", latitude: 43.04037400, longitude: -1.02594200, imageUrl: skaping('chalets-iraty'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamb-ry-palais-de-justice", name: "Chambéry - Palais de justice", location: "Chambéry", region: "France", latitude: 45.56787400, longitude: 5.91889500, imageUrl: skaping('chambery/palais-de-justice'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chambon-sur-lignon-centre-ville", name: "Chambon sur Lignon - Centre ville", location: "Chambon sur Lignon", region: "France", latitude: 45.06037740, longitude: 4.30246240, imageUrl: skaping('haut-lignon/chambon-sur-lignon/centre-ville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chambon-sur-lignon-plage", name: "Chambon sur Lignon - Plage", location: "Chambon sur Lignon", region: "France", latitude: 45.05209861, longitude: 4.31737647, imageUrl: skaping('haut-lignon/chambon-sur-lignon/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-aiguille-du-midi", name: "Chamonix - Aiguille du Midi", location: "Chamonix", region: "France", latitude: 45.87920700, longitude: 6.88705500, imageUrl: skaping('chamonix/aiguille-du-midi'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-balme-charamillon", name: "Chamonix - Balme - Charamillon", location: "Chamonix", region: "France", latitude: 46.01940636, longitude: 6.95872307, imageUrl: skaping('chamonix/balme/charamillon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-br-vent", name: "Chamonix - Brévent", location: "Chamonix", region: "France", latitude: 45.93370700, longitude: 6.83779500, imageUrl: skaping('chamonix/brevent'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-fl-gere", name: "Chamonix - Flégere", location: "Chamonix", region: "France", latitude: 45.95981900, longitude: 6.88630900, imageUrl: skaping('chamonix-flegere-G1'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-index", name: "Chamonix - Index", location: "Chamonix", region: "France", latitude: 45.96839700, longitude: 6.87292000, imageUrl: skaping('chamonix/flegere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-montenvers", name: "Chamonix - Montenvers", location: "Chamonix", region: "France", latitude: 45.93171627, longitude: 6.91780329, imageUrl: skaping('chamonix/montenvers'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-plan-praz", name: "Chamonix - Plan Praz", location: "Chamonix", region: "France", latitude: 45.93814149, longitude: 6.84985883, imageUrl: skaping('chamonix/plan-praz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-plateau-de-lognan", name: "Chamonix - Plateau de Lognan", location: "Chamonix", region: "France", latitude: 45.96791000, longitude: 6.94297200, imageUrl: skaping('chamonix/plateau-de-lognan'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-t-te-de-balme", name: "Chamonix - Tête de Balme", location: "Chamonix", region: "France", latitude: 46.03042300, longitude: 6.96245500, imageUrl: skaping('chamonix/tete-de-balme'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamonix-ville", name: "Chamonix - Ville", location: "Chamonix", region: "France", latitude: 45.92702700, longitude: 6.87162300, imageUrl: skaping('chamonix-mont-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamrousse-casserousse", name: "Chamrousse - Casserousse", location: "Chamrousse", region: "France", latitude: 45.12847884, longitude: 5.88693372, imageUrl: skaping('chamrousse/panorama-casserousse'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamrousse-la-croix", name: "Chamrousse - La Croix", location: "Chamrousse", region: "France", latitude: 45.12567000, longitude: 5.90400200, imageUrl: skaping('chamrousse/la-croix'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamrousse-le-recoin", name: "Chamrousse - Le Recoin", location: "Chamrousse", region: "France", latitude: 45.12603513, longitude: 5.87984204, imageUrl: skaping('chamrousse/recoin/archives'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamrousse-les-cr-tes", name: "Chamrousse - Les crêtes", location: "Chamrousse", region: "France", latitude: 45.11877000, longitude: 5.89723400, imageUrl: skaping('chamrousse/les-cretes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chamrousse-roche-b-ranger", name: "Chamrousse - Roche Béranger", location: "Chamrousse", region: "France", latitude: 45.11031400, longitude: 5.87695200, imageUrl: skaping('chamrousse/roche-beranger'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-ch-teau-de-chambord", name: "Château de Chambord", location: "Château de Chambord", region: "France", latitude: 47.61860000, longitude: 1.51522600, imageUrl: skaping('blois-chambord/chateau-de-chambord'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-chatel-lac-de-vonnes", name: "Chatel - Lac de Vonnes", location: "Chatel", region: "France", latitude: 46.25535500, longitude: 6.84353200, imageUrl: skaping('chatel/lac-de-vonnes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-cogolin-port-de-plaisance", name: "Cogolin - Port de Plaisance", location: "Cogolin", region: "France", latitude: 43.26546218, longitude: 6.58805788, imageUrl: skaping('cogolin/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-col-de-porte-biathlon", name: "Col de Porte - Biathlon", location: "Col de Porte", region: "France", latitude: 45.29505700, longitude: 5.77009400, imageUrl: skaping('col-de-porte/biathlon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-col-de-porte-chamechaude", name: "Col de Porte - Chamechaude", location: "Col de Porte", region: "France", latitude: 45.29015944, longitude: 5.76736376, imageUrl: skaping('grenoble/col-de-porte'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-col-de-porte-la-prairie", name: "Col de Porte - La Prairie", location: "Col de Porte", region: "France", latitude: 45.29445900, longitude: 5.76479500, imageUrl: skaping('col-de-porte/ski-alpin'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-collet-d-allevard-les-plagnes", name: "Collet d'Allevard - Les Plagnes", location: "Collet d'Allevard", region: "France", latitude: 45.38616200, longitude: 6.14679200, imageUrl: skaping('collet-d-allevard/sommet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-combloux-pertuis", name: "Combloux - Pertuis", location: "Combloux", region: "France", latitude: 45.87892900, longitude: 6.58839400, imageUrl: skaping('combloux/sommet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-coudeville-sur-mer", name: "Coudeville-sur-Mer", location: "Coudeville-sur-Mer", region: "France", latitude: 48.88817200, longitude: -1.57142000, imageUrl: skaping('granville-terre-mer/coudeville-sur-mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-courchevel-chenus", name: "Courchevel - Chenus", location: "Courchevel", region: "France", latitude: 45.40591700, longitude: 6.61459600, imageUrl: skaping('courchevel/chenus'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-courchevel-la-croisette", name: "Courchevel - La Croisette", location: "Courchevel", region: "France", latitude: 45.41507900, longitude: 6.63268800, imageUrl: skaping('courchevel/la-croisette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-courchevel-la-tania-bouc-blanc", name: "Courchevel - La Tania Bouc Blanc", location: "Courchevel", region: "France", latitude: 45.41771900, longitude: 6.60844200, imageUrl: skaping('courchevel/bouc-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-courchevel-saulire", name: "Courchevel - Saulire", location: "Courchevel", region: "France", latitude: 45.38229700, longitude: 6.61512000, imageUrl: skaping('courchevel/saulire'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crans-montana-aminona", name: "Crans Montana - Aminona", location: "Crans Montana", region: "France", latitude: 46.35348700, longitude: 7.51980500, imageUrl: skaping('crans-montana/la-tsa'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crans-montana-cry-d-er", name: "Crans Montana - Cry d'Er", location: "Crans Montana", region: "France", latitude: 46.33118100, longitude: 7.48197300, imageUrl: skaping('crans-montana/cryder'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crans-montana-les-violettes", name: "Crans Montana - Les Violettes", location: "Crans Montana", region: "France", latitude: 46.34258000, longitude: 7.49880100, imageUrl: skaping('crans-montana/les-violettes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crans-montana-plaine-morte", name: "Crans Montana - Plaine Morte", location: "Crans Montana", region: "France", latitude: 46.37020000, longitude: 7.48891100, imageUrl: skaping('crans-montana/plaine-morte'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crest-voland-le-cernix", name: "Crest Voland - Le Cernix", location: "Crest Voland", region: "France", latitude: 45.78636100, longitude: 6.51994400, imageUrl: skaping('crest-voland/le-cernix'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crest-voland-le-village", name: "Crest Voland - Le Village", location: "Crest Voland", region: "France", latitude: 45.79275000, longitude: 6.50308300, imageUrl: skaping('crest-voland/lalogere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-crest-voland-mont-lachat", name: "Crest Voland - Mont Lachat", location: "Crest Voland", region: "France", latitude: 45.78710300, longitude: 6.52207400, imageUrl: skaping('crest-voland/lachat'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-digoin", name: "Digoin", location: "Digoin", region: "France", latitude: 46.47802323, longitude: 3.98164296, imageUrl: skaping('digoin'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-donville-les-bains", name: "Donville-les-Bains", location: "Donville-les-Bains", region: "France", latitude: 48.84493400, longitude: -1.59103700, imageUrl: skaping('granville-terre-mer/donville-les-bains'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-doussard-douss-plage", name: "Doussard - Douss'Plage", location: "Doussard", region: "France", latitude: 45.79317400, longitude: 6.21698900, imageUrl: skaping('sources-du-lac-annecy/douss-plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-epinal-quai-jules-ferry", name: "Epinal - Quai Jules Ferry", location: "Epinal", region: "France", latitude: 48.17397181, longitude: 6.44866997, imageUrl: skaping('epinal/quai-jules-ferry'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-esparron-de-verdon", name: "Esparron De Verdon", location: "Esparron De Verdon", region: "France", latitude: 43.73090600, longitude: 5.97337200, imageUrl: skaping('esparron-de-verdon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-est-rel-roquebrune-sur-argens-les-issambres", name: "Estérel - Roquebrune-sur-Argens - Les Issambres", location: "Estérel", region: "France", latitude: 43.36310900, longitude: 6.67761000, imageUrl: skaping('esterel/roquebrune-sur-argens-les-issambres'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-esterel-caravaning", name: "Esterel Caravaning", location: "Esterel Caravaning", region: "France", latitude: 43.45313600, longitude: 6.83352800, imageUrl: skaping('esterel-caravaning'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tretat-falaises", name: "Étretat - Falaises", location: "Étretat", region: "France", latitude: 49.70761705, longitude: 0.20140707, imageUrl: skaping('etretat/falaises'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-evian-capitainerie", name: "Evian - Capitainerie", location: "Evian", region: "France", latitude: 46.40261000, longitude: 6.60548800, imageUrl: skaping('evian/capitainerie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-evian-centre-nautique", name: "Evian - Centre Nautique", location: "Evian", region: "France", latitude: 46.40060700, longitude: 6.58055000, imageUrl: skaping('evian/centrenautique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-evron", name: "Evron", location: "Evron", region: "France", latitude: 48.15583600, longitude: -0.40354500, imageUrl: skaping('evron/ville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-excenevex-plage", name: "Excenevex - Plage", location: "Excenevex", region: "France", latitude: 46.35020600, longitude: 6.35822700, imageUrl: skaping('excenevex/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-flaine-d-sert-blanc-2395m", name: "Flaine - Désert Blanc - 2395m", location: "Flaine", region: "France", latitude: 45.99240000, longitude: 6.72901500, imageUrl: skaping('flaine/desert-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-flaine-v-ret-2310m", name: "Flaine - Véret - 2310m", location: "Flaine", region: "France", latitude: 46.00985600, longitude: 6.71366100, imageUrl: skaping('flaine/veret'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-fr-jus", name: "Fréjus", location: "Fréjus", region: "France", latitude: 43.43294100, longitude: 6.73699200, imageUrl: skaping('esterel/frejus'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-g-nelard", name: "Génelard", location: "Génelard", region: "France", latitude: 46.57769667, longitude: 4.23524022, imageUrl: skaping('genelard'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-giez-source-du-lac", name: "Giez - Source du Lac", location: "Giez", region: "France", latitude: 45.75102015, longitude: 6.24759922, imageUrl: skaping('sources-du-lac-annecy/giez'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-givry", name: "Givry", location: "Givry", region: "France", latitude: 46.79029800, longitude: 4.74156100, imageUrl: skaping('givry'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-golf-du-gouverneur", name: "Golf du Gouverneur", location: "Golf du Gouverneur", region: "France", latitude: 45.96698011, longitude: 4.93294716, imageUrl: skaping('golf-du-gouverneur'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gouville-sur-mer", name: "Gouville-sur-mer", location: "Gouville-sur-mer", region: "France", latitude: 49.09932292, longitude: -1.60956144, imageUrl: skaping('coutances/gouville-sur-mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-goz-n", name: "Gozón", location: "Gozón", region: "France", latitude: 43.58595880, longitude: -5.88127387, imageUrl: skaping('gozon/webcam'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grand-lac-bourget-du-lac", name: "Grand Lac - Bourget du Lac", location: "Grand Lac", region: "France", latitude: 45.65609000, longitude: 5.86210900, imageUrl: skaping('grandlac/bourgetdulac'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grand-lac-foyer-du-ski-de-fond-de-crolles", name: "Grand Lac - Foyer du ski de fond de Crolles", location: "Grand Lac", region: "France", latitude: 45.67855800, longitude: 5.99869200, imageUrl: skaping('aix-les-bains/foyer-du-ski-de-fond-de-crolles'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grand-lac-grand-port", name: "Grand Lac - Grand Port", location: "Grand Lac", region: "France", latitude: 45.70353400, longitude: 5.88629400, imageUrl: skaping('grandlac/grandport'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grand-lac-revard-info-neige", name: "Grand Lac - Revard Info Neige", location: "Grand Lac", region: "France", latitude: 45.68060000, longitude: 5.97792800, imageUrl: skaping('grandlac/revardinfoneige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grenoble-bastille", name: "Grenoble - Bastille", location: "Grenoble", region: "France", latitude: 45.19865600, longitude: 5.72470700, imageUrl: skaping('grenoble/bastille'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grenoble-h-tel-de-ville", name: "Grenoble - Hôtel de Ville", location: "Grenoble", region: "France", latitude: 45.18653500, longitude: 5.73618300, imageUrl: skaping('grenoble/hotel-de-ville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grenoble-les-vouillants", name: "Grenoble - Les Vouillants", location: "Grenoble", region: "France", latitude: 45.17443800, longitude: 5.67434300, imageUrl: skaping('grenoble/les-vouillants'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-gr-oli-res-les-huskies", name: "Gréolières - Les Huskies", location: "Gréolières", region: "France", latitude: 43.82219652, longitude: 6.97240535, imageUrl: skaping('greolieres/huskies'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-grimaud-le-village", name: "Grimaud - Le village", location: "Grimaud", region: "France", latitude: 43.27452100, longitude: 6.52242900, imageUrl: skaping('grimaud/mairie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guidel-camping-pen-er-malo", name: "Guidel - Camping Pen Er Malo ", location: "Guidel", region: "France", latitude: 47.74644000, longitude: -3.50339800, imageUrl: skaping('camping-pen-er-malo-guidel'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-guidel-port", name: "Guidel - Port", location: "Guidel", region: "France", latitude: 47.77240100, longitude: -3.52852200, imageUrl: skaping('guidel/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-hauteville-sur-mer", name: "Hauteville-sur-mer", location: "Hauteville-sur-mer", region: "France", latitude: 48.97762602, longitude: -1.56277247, imageUrl: skaping('coutances/hauteville-sur-mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-hendaye-ch-teau-abbadia", name: "Hendaye - Château Abbadia", location: "Hendaye", region: "France", latitude: 43.37755400, longitude: -1.74954500, imageUrl: skaping('hendaye/abbadia'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-ile-des-embiez", name: "Ile des Embiez", location: "Ile des Embiez", region: "France", latitude: 43.07520077, longitude: 5.78271389, imageUrl: skaping('ile-des-embiez'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-jullouville-granville", name: "Jullouville - Granville", location: "Jullouville", region: "France", latitude: 48.76790400, longitude: -1.57056300, imageUrl: skaping('granville-terre-mer/jullouville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-jura-sur-leman-la-d-le-les-rousses", name: "Jura-sur-Leman - La Dôle - Les Rousses", location: "Jura-sur-Leman", region: "France", latitude: 46.42583529, longitude: 6.09965980, imageUrl: skaping('jura-sur-leman/la-dole/vue-les-rousses'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-jura-sur-leman-la-d-le-mont-blanc", name: "Jura-sur-Leman - La Dôle - Mont Blanc", location: "Jura-sur-Leman", region: "France", latitude: 46.42549881, longitude: 6.10013187, imageUrl: skaping('jura-sur-leman/la-dole/vue-mont-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-kerguelen-centre-nautique", name: "Kerguelen - Centre Nautique", location: "Kerguelen", region: "France", latitude: 47.70305100, longitude: -3.40972100, imageUrl: skaping('kerguelen/centre-nautique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-l-ile-aux-moines-port-blanc", name: "L'ile aux Moines - Port Blanc", location: "L'ile aux Moines", region: "France", latitude: 47.60108660, longitude: -2.85188556, imageUrl: skaping('port-blanc/ile-aux-moines/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-baule", name: "La Baule", location: "La Baule", region: "France", latitude: 47.28170917, longitude: -2.39467621, imageUrl: skaping('la-baule/plage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-baule-yacht-club", name: "La Baule - Yacht Club", location: "La Baule", region: "France", latitude: 47.27469259, longitude: -2.42412284, imageUrl: skaping('yacht-club-la-baule'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-bresse-front-de-neige", name: "La Bresse - Front de neige", location: "La Bresse", region: "France", latitude: 48.03709100, longitude: 6.97113800, imageUrl: skaping('labresse/front-de-neige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-bresse-haut-de-vologne", name: "La Bresse - Haut de Vologne", location: "La Bresse", region: "France", latitude: 48.03404600, longitude: 6.98800100, imageUrl: skaping('la-bresse/haut-de-vologne'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-bresse-lispach", name: "La Bresse - Lispach", location: "La Bresse", region: "France", latitude: 48.05176880, longitude: 6.94394946, imageUrl: skaping('la-bresse/lispach'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-bresse-sommet-chitelet", name: "La Bresse - Sommet Chitelet", location: "La Bresse", region: "France", latitude: 48.03276000, longitude: 6.99861200, imageUrl: skaping('la-bresse/hohneck'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-bresse-sommet-petit-artimont", name: "La Bresse - Sommet Petit Artimont", location: "La Bresse", region: "France", latitude: 48.02652151, longitude: 6.97992325, imageUrl: skaping('la-bresse/sommet-petit-artimont'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-clusaz-espace-nordique", name: "La Clusaz - Espace Nordique", location: "La Clusaz", region: "France", latitude: 45.92003200, longitude: 6.47850800, imageUrl: skaping('la-clusaz/espace-nordique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-f-claz-orionde", name: "La Féclaz - Orionde", location: "La Féclaz", region: "France", latitude: 45.64660200, longitude: 5.97082100, imageUrl: skaping('la-feclaz/orionde'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-giettaz-torraz", name: "La Giettaz - Torraz ", location: "La Giettaz", region: "France", latitude: 45.86188600, longitude: 6.53264300, imageUrl: skaping('la-giettaz/sommet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-grave-2400m", name: "La Grave - 2400m", location: "La Grave", region: "France", latitude: 45.02612400, longitude: 6.28942900, imageUrl: skaping('lagrave/2400m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-grave-3200m", name: "La Grave - 3200m", location: "La Grave", region: "France", latitude: 45.00956300, longitude: 6.26389100, imageUrl: skaping('lagrave/3200m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-grave-village", name: "La Grave - Village", location: "La Grave", region: "France", latitude: 45.04421100, longitude: 6.30310800, imageUrl: skaping('la-grave/hotel-castillan'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-haye-pesnel", name: "La Haye Pesnel", location: "La Haye Pesnel", region: "France", latitude: 48.79651300, longitude: -1.39701300, imageUrl: skaping('granville-terre-mer/la-haye-pesnel'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-mongie-4-termes-2250m", name: "La Mongie - 4 termes - 2250m ", location: "La Mongie", region: "France", latitude: 42.89494600, longitude: 0.16460900, imageUrl: skaping('grandtourmalet/lamongie4termes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-mongie-col-du-tourmalet-2115m", name: "La Mongie - Col du Tourmalet - 2115m", location: "La Mongie", region: "France", latitude: 42.90836600, longitude: 0.14740700, imageUrl: skaping('grandtourmalet/coldutourmalet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-mongie-pourteilh-2250m", name: "La Mongie - Pourteilh - 2250m", location: "La Mongie", region: "France", latitude: 42.89524100, longitude: 0.16401000, imageUrl: skaping('grandtourmalet/lamongiepourteilh'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-mongie-tourmalet-1800m", name: "La Mongie - Tourmalet - 1800m", location: "La Mongie", region: "France", latitude: 42.90588900, longitude: 0.16304900, imageUrl: skaping('grandtourmalet/lamongietourmalet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-mongie-village-1750m", name: "La Mongie - village - 1750m", location: "La Mongie", region: "France", latitude: 42.91032000, longitude: 0.17635000, imageUrl: skaping('grandtourmalet/lamongievillage'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-norma-carrelet", name: "La Norma - Carrelet", location: "La Norma", region: "France", latitude: 45.18396519, longitude: 6.70473397, imageUrl: skaping('la-norma/carrelet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-norma-fontaine-aux-oiseaux", name: "La Norma - Fontaine aux oiseaux", location: "La Norma", region: "France", latitude: 45.19985459, longitude: 6.69862390, imageUrl: skaping('la-norma/fontaine-aux-oiseaux'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-roche-sur-yon-moulin-de-rambourg", name: "La Roche sur Yon - Moulin de Rambourg", location: "La Roche sur Yon", region: "France", latitude: 46.60623900, longitude: -1.39479800, imageUrl: skaping('la-roche-sur-yon/moulin-de-rambourg'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-roche-sur-yon-place-napol-on", name: "La Roche sur Yon - Place Napoléon", location: "La Roche sur Yon", region: "France", latitude: 46.67013200, longitude: -1.42655600, imageUrl: skaping('la-roche-sur-yon/place-napoleon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-rochelle", name: "La Rochelle", location: "La Rochelle", region: "France", latitude: 46.15713200, longitude: -1.14986800, imageUrl: skaping('larochelle-tourisme'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-rochelle-port-de-plaisance", name: "La Rochelle - Port de plaisance", location: "La Rochelle", region: "France", latitude: 46.14463723, longitude: -1.17257059, imageUrl: skaping('port-de-plaisance-la-rochelle/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-sambuy", name: "La Sambuy", location: "La Sambuy", region: "France", latitude: 45.69850000, longitude: 6.27211000, imageUrl: skaping('sambuy'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-schlucht", name: "La Schlucht", location: "La Schlucht", region: "France", latitude: 48.06349871, longitude: 7.02220559, imageUrl: skaping('la-schlucht/front-de-neige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-toussuire-chaput", name: "La Toussuire - Chaput", location: "La Toussuire", region: "France", latitude: 45.26635700, longitude: 6.24370800, imageUrl: skaping('latoussuire/chaput'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-toussuire-front-de-neige", name: "La Toussuire - Front de Neige", location: "La Toussuire", region: "France", latitude: 45.25569500, longitude: 6.25595748, imageUrl: skaping('la-toussuire/front-de-neige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-toussuire-les-lutins", name: "La Toussuire - Les Lutins", location: "La Toussuire", region: "France", latitude: 45.25312900, longitude: 6.25989300, imageUrl: skaping('latoussuire/les-lutins'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-toussuire-pierre-du-turc", name: "La Toussuire - Pierre du Turc", location: "La Toussuire", region: "France", latitude: 45.25019600, longitude: 6.22352400, imageUrl: skaping('latoussuire/pierre-du-turc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-la-turballe-port-de-plaisance", name: "La Turballe - Port de plaisance", location: "La Turballe", region: "France", latitude: 47.34847200, longitude: -2.51175918, imageUrl: skaping('port-de-plaisance-de-la-turballe'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-de-payolle-restaurant", name: "Lac de Payolle - Restaurant", location: "Lac de Payolle", region: "France", latitude: 42.93527974, longitude: 0.29975345, imageUrl: skaping('campan/lac-de-payolle'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-lac-des-sapins", name: "Lac des Sapins", location: "Lac des Sapins", region: "France", latitude: 46.00930500, longitude: 4.37733200, imageUrl: skaping('lac-des-sapins'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-champ-du-feu-chalet", name: "Le Champ du Feu - Chalet", location: "Le Champ du Feu", region: "France", latitude: 48.40586068, longitude: 7.26031601, imageUrl: skaping('le-champ-du-feu/chalet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-champ-du-feu-pistes", name: "Le Champ du Feu - Pistes", location: "Le Champ du Feu", region: "France", latitude: 48.40969769, longitude: 7.26089001, imageUrl: skaping('le-champ-du-feu/pistes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-corbier-front-de-neige", name: "Le Corbier - Front de neige", location: "Le Corbier", region: "France", latitude: 45.23979854, longitude: 6.26871943, imageUrl: skaping('le-corbier/front-de-neige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-croisic-port-de-plaisance", name: "Le Croisic - Port de plaisance", location: "Le Croisic", region: "France", latitude: 47.29362981, longitude: -2.50856280, imageUrl: skaping('le-croisic/port-de-plaisance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-auberge-nordique", name: "Le Grand-Bornand - Auberge Nordique", location: "Le Grand-Bornand", region: "France", latitude: 45.94325300, longitude: 6.50066800, imageUrl: skaping('le-grand-bornand/auberge-nordique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-chinaillon", name: "Le Grand-Bornand - Chinaillon", location: "Le Grand-Bornand", region: "France", latitude: 45.97613900, longitude: 6.45477000, imageUrl: skaping('le-grand-bornand/chinaillon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-la-taverne", name: "Le Grand-Bornand - La Taverne", location: "Le Grand-Bornand", region: "France", latitude: 45.95614600, longitude: 6.45717000, imageUrl: skaping('le-grand-bornand/taverne'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-le-maroly-terres-rouges", name: "Le Grand-Bornand - Le Maroly - Terres Rouges", location: "Le Grand-Bornand", region: "France", latitude: 45.96715900, longitude: 6.49695100, imageUrl: skaping('le-grand-bornand/terresrouges'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-mont-lachat", name: "Le Grand-Bornand - Mont Lachat", location: "Le Grand-Bornand", region: "France", latitude: 45.95978900, longitude: 6.47592500, imageUrl: skaping('le-grand-bornand/mont-lachat'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-grand-bornand-village", name: "Le Grand-Bornand - Village", location: "Le Grand-Bornand", region: "France", latitude: 45.94186100, longitude: 6.42776700, imageUrl: skaping('le-grand-bornand/village'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-puy-en-velay", name: "Le Puy-en-Velay", location: "Le Puy-en-Velay", region: "France", latitude: 45.04699000, longitude: 3.88541500, imageUrl: skaping('lepuyenvelay/notredamedefrance'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-sal-ve-t-l-ph-rique", name: "Le Salève - Téléphérique", location: "Le Salève", region: "France", latitude: 46.15426910, longitude: 6.19328499, imageUrl: skaping('telepherique-du-saleve'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-le-schnepfenried", name: "Le Schnepfenried", location: "Le Schnepfenried", region: "France", latitude: 47.98434579, longitude: 7.04678535, imageUrl: skaping('le-schnepfenried/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-3200m", name: "Les 2 Alpes - 3200m", location: "Les 2 Alpes", region: "France", latitude: 44.99752700, longitude: 6.20452200, imageUrl: skaping('les2alpes/3200m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-3400m", name: "Les 2 Alpes - 3400m", location: "Les 2 Alpes", region: "France", latitude: 44.99768400, longitude: 6.22220700, imageUrl: skaping('les2alpes/3400m'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-bellecombe", name: "Les 2 Alpes - Bellecombe", location: "Les 2 Alpes", region: "France", latitude: 44.99214000, longitude: 6.16207700, imageUrl: skaping('les2alpes/bellecombe'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-grande-aiguille", name: "Les 2 Alpes - Grande Aiguille", location: "Les 2 Alpes", region: "France", latitude: 45.01730289, longitude: 6.14295545, imageUrl: skaping('les2alpes/grande-aiguille'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-la-f-e", name: "Les 2 Alpes - La Fée", location: "Les 2 Alpes", region: "France", latitude: 45.00375600, longitude: 6.16838300, imageUrl: skaping('les2alpes/la-fee'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-super-diable", name: "Les 2 Alpes - Super Diable", location: "Les 2 Alpes", region: "France", latitude: 44.99697100, longitude: 6.14687900, imageUrl: skaping('les2alpes/super-diable'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-2-alpes-vall-e-blanche", name: "Les 2 Alpes - Vallée Blanche", location: "Les 2 Alpes", region: "France", latitude: 45.00907482, longitude: 6.10571778, imageUrl: skaping('les2alpes/vallee-blanche'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-7-laux-pipay-grand-cerf", name: "Les 7 Laux - Pipay - Grand Cerf", location: "Les 7 Laux", region: "France", latitude: 45.25705198, longitude: 6.03051392, imageUrl: skaping('les7laux/pipay/grand-cerf'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-7-laux-pleynet-les-loups", name: "Les 7 Laux - Pleynet - Les Loups", location: "Les 7 Laux", region: "France", latitude: 45.26937471, longitude: 6.03720188, imageUrl: skaping('les7laux/pleynet/les-loups'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-7-laux-pleynet-oursi-re", name: "Les 7 Laux - Pleynet - Oursière", location: "Les 7 Laux", region: "France", latitude: 45.25333400, longitude: 6.03294700, imageUrl: skaping('les7laux/pleynet/oursiere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-7-laux-prapoutel-secteur-d-butant-du-plan", name: "Les 7 Laux - Prapoutel - Secteur débutant du Plan", location: "Les 7 Laux", region: "France", latitude: 45.25126800, longitude: 6.00159500, imageUrl: skaping('les7laux/prapoutel/sommetdesbouquetins'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-aillons-marg-riaz-1000", name: "Les Aillons - Margériaz - 1000", location: "Les Aillons", region: "France", latitude: 45.60822900, longitude: 6.10189900, imageUrl: skaping('aillons-margeriaz/1000'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-aillons-marg-riaz-1400", name: "Les Aillons - Margériaz - 1400", location: "Les Aillons", region: "France", latitude: 45.64242059, longitude: 6.06199360, imageUrl: skaping('les-aillons/margeriaz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-aillons-marg-riaz-les-cr-tes", name: "Les Aillons - Margériaz - Les crêtes", location: "Les Aillons", region: "France", latitude: 45.62983800, longitude: 6.04187400, imageUrl: skaping('aillons-margeriaz/roc-de-margeriaz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-estables-domaine-nordique", name: "Les Estables - Domaine nordique", location: "Les Estables", region: "France", latitude: 44.91337900, longitude: 4.16933200, imageUrl: skaping('les-estables/ski-nordique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-estables-lugik-parc", name: "Les Estables - Lugik Parc", location: "Les Estables", region: "France", latitude: 44.90832700, longitude: 4.15580100, imageUrl: skaping('lugik-parc/sommet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-estables-ski-alpin", name: "Les Estables - Ski Alpin", location: "Les Estables", region: "France", latitude: 44.90551000, longitude: 4.15659100, imageUrl: skaping('les-estables/ski-alpin/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-houches-blue-ice", name: "Les Houches - Blue Ice", location: "Les Houches", region: "France", latitude: 45.89130300, longitude: 6.79058400, imageUrl: skaping('blue-ice'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-houches-prarion", name: "Les Houches - Prarion", location: "Les Houches", region: "France", latitude: 45.88610429, longitude: 6.75257921, imageUrl: skaping('les-houches/prarion'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-houches-village", name: "Les Houches - Village", location: "Les Houches", region: "France", latitude: 45.88989700, longitude: 6.79843600, imageUrl: skaping('chamonix/les-houches'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-bruy-res", name: "Les Menuires - Bruyères", location: "Les Menuires", region: "France", latitude: 45.31466336, longitude: 6.54179313, imageUrl: skaping('les-menuires/bruyeres/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-clocher", name: "Les Menuires - Clocher", location: "Les Menuires", region: "France", latitude: 45.32277500, longitude: 6.53744600, imageUrl: skaping('les-menuires/clocher'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-la-croisette", name: "Les Menuires - La Croisette", location: "Les Menuires", region: "France", latitude: 45.32365400, longitude: 6.54158200, imageUrl: skaping('lesmenuires/croisette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-la-masse", name: "Les Menuires - La Masse", location: "Les Menuires", region: "France", latitude: 45.29672900, longitude: 6.50952500, imageUrl: skaping('les-menuires/la-masse'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-lac-du-lou", name: "Les Menuires - Lac du Lou", location: "Les Menuires", region: "France", latitude: 45.29432611, longitude: 6.52997732, imageUrl: skaping('les-menuires/lac-du-lou'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-menuires-les-enverses", name: "Les Menuires - Les Enverses", location: "Les Menuires", region: "France", latitude: 45.31501200, longitude: 6.52252800, imageUrl: skaping('les-menuires/les-enverses'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-orres-pousterle", name: "Les Orres - Pousterle", location: "Les Orres", region: "France", latitude: 44.46800800, longitude: 6.57120500, imageUrl: skaping('les-orres/pousterle'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-sables-d-olonne-quai-dingler", name: "Les Sables d'Olonne - Quai Dingler", location: "Les Sables d'Olonne", region: "France", latitude: 46.49328300, longitude: -1.79303000, imageUrl: skaping('les-sables-d-olonne/quai-dingler'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-saisies-le-manant", name: "Les Saisies - Le Manant", location: "Les Saisies", region: "France", latitude: 45.74832700, longitude: 6.52348800, imageUrl: skaping('les-saisies/le-manant'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-sybelles-charvin-express", name: "Les Sybelles - Charvin Express", location: "Les Sybelles", region: "France", latitude: 45.22559220, longitude: 6.25497043, imageUrl: skaping('les-sybelles/charvin-express/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-sybelles-l-ouillon", name: "Les Sybelles - L'Ouillon", location: "Les Sybelles", region: "France", latitude: 45.24179500, longitude: 6.21469300, imageUrl: skaping('les-sybelles/ouillon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-les-sybelles-saint-sorlin-d-arves", name: "Les Sybelles - Saint-Sorlin-d'Arves", location: "Les Sybelles", region: "France", latitude: 45.20911852, longitude: 6.18279219, imageUrl: skaping('les-sybelles/saint-sorlin-d-arves/le-rouet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-locmiqu-lic-port-de-plaisance", name: "Locmiquélic - Port de plaisance", location: "Locmiquélic", region: "France", latitude: 47.72470083, longitude: -3.34841699, imageUrl: skaping('port-de-locmiquelic/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-loudenvielle-tour-de-g-nos", name: "Loudenvielle - Tour de Génos", location: "Loudenvielle", region: "France", latitude: 42.80956500, longitude: 0.40497400, imageUrl: skaping('loudenvielle/tour-de-genos'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-luz-ardiden-aulian", name: "Luz Ardiden - Aulian", location: "Luz Ardiden", region: "France", latitude: 42.88499144, longitude: -0.06073058, imageUrl: skaping('luz-ardiden/aulian'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-luz-ardiden-caperette", name: "Luz Ardiden - Caperette", location: "Luz Ardiden", region: "France", latitude: 42.87948242, longitude: -0.07091761, imageUrl: skaping('luz-ardiden/caperette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-luz-ardiden-pourtere", name: "Luz Ardiden - Pourtere", location: "Luz Ardiden", region: "France", latitude: 42.87845643, longitude: -0.06018877, imageUrl: skaping('luz-ardiden/pourtere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-luz-ardiden-snowpark", name: "Luz Ardiden - Snowpark", location: "Luz Ardiden", region: "France", latitude: 42.88346830, longitude: -0.06181955, imageUrl: skaping('luz-ardiden/snowpark'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-m-con", name: "Mâcon", location: "Mâcon", region: "France", latitude: 46.30865293, longitude: 4.83481586, imageUrl: skaping('macon/ville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-manigod-cabeau", name: "Manigod - Cabeau", location: "Manigod", region: "France", latitude: 45.86690700, longitude: 6.40838500, imageUrl: skaping('manigod/cabeau'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-manigod-croix-fry", name: "Manigod - Croix Fry", location: "Manigod", region: "France", latitude: 45.87553500, longitude: 6.40131400, imageUrl: skaping('manigod/croix-fry'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-manigod-merdassier", name: "Manigod - Merdassier ", location: "Manigod", region: "France", latitude: 45.86283200, longitude: 6.41721100, imageUrl: skaping('manigod/merdassier'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-cote-2000", name: "Megève - Cote 2000", location: "Megève", region: "France", latitude: 45.80404352, longitude: 6.63766387, imageUrl: skaping('megeve/cote-2000'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-fontaine", name: "Megève - Fontaine", location: "Megève", region: "France", latitude: 45.81727022, longitude: 6.62291050, imageUrl: skaping('megeve/fontaine'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-jaillet", name: "Megève - Jaillet", location: "Megève", region: "France", latitude: 45.87090400, longitude: 6.59799800, imageUrl: skaping('jaillet/sommet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-la-livraz", name: "Megève - La Livraz", location: "Megève", region: "France", latitude: 45.83568781, longitude: 6.64140165, imageUrl: skaping('megeve/la-livraz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-mont-et-lac-d-arbois", name: "Megève - Mont et Lac d'Arbois", location: "Megève", region: "France", latitude: 45.85843518, longitude: 6.66204929, imageUrl: skaping('megeve/mont-d-arbois'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-rochebrune", name: "Megève - Rochebrune", location: "Megève", region: "France", latitude: 45.83318183, longitude: 6.61336720, imageUrl: skaping('megeve/rochebrune'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-meg-ve-village", name: "Megève - Village", location: "Megève", region: "France", latitude: 45.85707346, longitude: 6.61796334, imageUrl: skaping('megeve/village'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-m-ribel-mont-vallon", name: "Méribel - Mont Vallon", location: "Méribel", region: "France", latitude: 45.32849700, longitude: 6.61000400, imageUrl: skaping('meribel/mont-vallon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-m-ribel-roc-de-fer", name: "Méribel - Roc de fer", location: "Méribel", region: "France", latitude: 45.39254906, longitude: 6.53600693, imageUrl: skaping('meribel/roc-de-fer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-millau-brunas", name: "Millau - Brunas", location: "Millau", region: "France", latitude: 44.07146600, longitude: 3.06466500, imageUrl: skaping('millau/brunas/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-millau-pouncho", name: "Millau - Pouncho", location: "Millau", region: "France", latitude: 44.11006800, longitude: 3.10122900, imageUrl: skaping('millau/pouncho/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-montpinchon", name: "Montpinchon", location: "Montpinchon", region: "France", latitude: 49.02220523, longitude: -1.31561000, imageUrl: skaping('coutances/montpinchon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-montriond-lac", name: "Montriond - Lac", location: "Montriond", region: "France", latitude: 46.20920900, longitude: 6.72159800, imageUrl: skaping('montriond/lac'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-montriond-plateau-des-lindarets", name: "Montriond - Plateau des Lindarets", location: "Montriond", region: "France", latitude: 46.20875400, longitude: 6.77886900, imageUrl: skaping('montriond/ardent'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-montriond-village-des-lindarets", name: "Montriond - Village des Lindarets", location: "Montriond", region: "France", latitude: 46.21164539, longitude: 6.77388668, imageUrl: skaping('montriond/village-des-lindarets'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morzine-chamossi-re", name: "Morzine - Chamossière", location: "Morzine", region: "France", latitude: 46.13418677, longitude: 6.72554255, imageUrl: skaping('morzine/chamossiere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morzine-nyon", name: "Morzine - Nyon", location: "Morzine", region: "France", latitude: 46.15740999, longitude: 6.71167016, imageUrl: skaping('portes-du-soleil/morzine'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morzine-pleney", name: "Morzine - Pleney", location: "Morzine", region: "France", latitude: 46.16847245, longitude: 6.69283080, imageUrl: skaping('morzine/pleney'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-morzine-village", name: "Morzine - Village", location: "Morzine", region: "France", latitude: 46.18144239, longitude: 6.70358598, imageUrl: skaping('morzine/office-de-tourisme'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-muides-sur-loire", name: "Muides sur Loire", location: "Muides sur Loire", region: "France", latitude: 47.67486000, longitude: 1.52668100, imageUrl: skaping('blois-chambord/muides-sur-loire'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-mulhouse-place-de-la-r-union", name: "Mulhouse - Place de la Réunion", location: "Mulhouse", region: "France", latitude: 47.74695100, longitude: 7.33787200, imageUrl: skaping('mulhouse/reunion'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-najac", name: "Najac", location: "Najac", region: "France", latitude: 44.21889550, longitude: 1.97623570, imageUrl: skaping('bastides-gorges-aveyron/najac'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-nancy-place-de-la-carri-re", name: "Nancy - Place de la Carrière", location: "Nancy", region: "France", latitude: 48.69671799, longitude: 6.18106484, imageUrl: skaping('nancy/place-carriere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-nancy-place-stanislas", name: "Nancy - Place Stanislas", location: "Nancy", region: "France", latitude: 48.69324085, longitude: 6.18388653, imageUrl: skaping('nancy/place-stanislas'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-nay-h-tel-de-ville", name: "Nay - Hôtel de Ville", location: "Nay", region: "France", latitude: 43.17973629, longitude: -0.26178246, imageUrl: skaping('nay/hotel-de-ville'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-niort-notre-dame", name: "Niort - Notre-Dame", location: "Niort - Notre-Dame", region: "France", latitude: 46.32262124, longitude: -0.46602845, imageUrl: skaping('niort/notredame/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-orci-res-la-favue", name: "Orcières - La Favue", location: "Orcières", region: "France", latitude: 44.70835100, longitude: 6.30835200, imageUrl: skaping('orcieres/la-favue/panorama'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-orci-res-plateau-de-rocherousse", name: "Orcières – Plateau de Rocherousse", location: "Orcières – Plateau de Rocherousse", region: "France", latitude: 44.71741000, longitude: 6.33447900, imageUrl: skaping('orcieres/plateau-de-rocherousse'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-orl-ans-beffroi", name: "Orléans - Beffroi", location: "Orléans", region: "France", latitude: 47.90078400, longitude: 1.90575500, imageUrl: skaping('orleans/beffroi'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-orl-ans-parc-floral", name: "Orléans - Parc Floral", location: "Orléans", region: "France", latitude: 47.85235700, longitude: 1.93525400, imageUrl: skaping('orleans/parc-floral'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-oz-3300-station", name: "Oz 3300 - Station", location: "Oz 3300", region: "France", latitude: 45.12633500, longitude: 6.07061384, imageUrl: skaping('oz-en-oisans/station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-paray-le-monial", name: "Paray Le Monial", location: "Paray Le Monial", region: "France", latitude: 46.45320100, longitude: 4.13031600, imageUrl: skaping('paray-le-monial'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-parc-de-fierbois", name: "Parc de Fierbois", location: "Parc de Fierbois", region: "France", latitude: 47.14957920, longitude: 0.65255310, imageUrl: skaping('parc-de-fierbois/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-parentis-en-born-club-nautique", name: "Parentis-en-Born - Club nautique", location: "Parentis-en-Born", region: "France", latitude: 44.34707969, longitude: -1.10355416, imageUrl: skaping('parentis-en-born/club-nautique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-parentis-en-born-office-de-tourisme", name: "Parentis-en-Born - Office de Tourisme", location: "Parentis-en-Born", region: "France", latitude: 44.34865685, longitude: -1.07172489, imageUrl: skaping('parentis-en-born/office-de-tourisme'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-parentis-en-born-port", name: "Parentis-en-Born - Port", location: "Parentis-en-Born", region: "France", latitude: 44.34161502, longitude: -1.09821221, imageUrl: skaping('parentis-en-born/port'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-passy-plaine-joux-station", name: "Passy Plaine Joux - Station", location: "Passy Plaine Joux", region: "France", latitude: 45.94988472, longitude: 6.73982379, imageUrl: skaping('passy-plaine-joux/station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-passy-plaine-joux-barmus", name: "Passy Plaine-Joux - Barmus", location: "Passy Plaine-Joux", region: "France", latitude: 45.95807536, longitude: 6.75142050, imageUrl: skaping('passy-plaine-joux/barmus'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pays-de-fayence-a-rodrome", name: "Pays de Fayence - Aérodrome", location: "Pays de Fayence", region: "France", latitude: 43.60761797, longitude: 6.69436455, imageUrl: skaping('pays-de-fayence/aerodrome'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pays-de-fayence-mons", name: "Pays de Fayence - Mons", location: "Pays de Fayence", region: "France", latitude: 43.68902630, longitude: 6.71257433, imageUrl: skaping('pays-de-fayence/mons'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pays-de-fayence-saint-cassien", name: "Pays de Fayence - Saint Cassien", location: "Pays de Fayence", region: "France", latitude: 43.58125400, longitude: 6.80482400, imageUrl: skaping('esterel/paysdefayence'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pays-voironnais-paladru", name: "Pays Voironnais - Paladru", location: "Pays Voironnais", region: "France", latitude: 45.45236100, longitude: 5.52253300, imageUrl: skaping('ot-pays-voironnais/lac-de-paladru/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-peyragudes-cap-de-pales", name: "Peyragudes - Cap de Pales", location: "Peyragudes", region: "France", latitude: 42.77529851, longitude: 0.45604527, imageUrl: skaping('peyragudes/cap-de-pales'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-peyragudes-cap-de-pales-belv-d-re", name: "Peyragudes - Cap de Pales - Belvédère", location: "Peyragudes", region: "France", latitude: 42.77449511, longitude: 0.45630813, imageUrl: skaping('peyragudes/belvedere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-peyragudes-les-agudes", name: "Peyragudes - Les Agudes", location: "Peyragudes", region: "France", latitude: 42.78715900, longitude: 0.47749500, imageUrl: skaping('peyragudes/les-agudes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-peyragudes-peyresourde", name: "Peyragudes - Peyresourde", location: "Peyragudes", region: "France", latitude: 42.78969600, longitude: 0.44827900, imageUrl: skaping('peyragudes/peyresourde'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-piau-engaly-lac-d-or-don", name: "Piau Engaly - Lac d'Orédon", location: "Piau Engaly", region: "France", latitude: 42.82716500, longitude: 0.16901700, imageUrl: skaping('neouvielle/lac-oredon'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pic-du-midi", name: "Pic du Midi", location: "Pic du Midi", region: "France", latitude: 42.93631504, longitude: 0.14247651, imageUrl: skaping('pic-du-midi'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-portes-du-soleil-les-gets-ranfoilly", name: "Portes du soleil - Les Gets- Ranfoilly", location: "Portes du soleil", region: "France", latitude: 46.13139000, longitude: 6.70469200, imageUrl: skaping('portes-du-soleil/les-gets'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-portes-du-soleil-torgon-plan-de-croix", name: "Portes du soleil - Torgon - Plan de Croix", location: "Portes du soleil", region: "France", latitude: 46.30591500, longitude: 6.85028400, imageUrl: skaping('portes-du-soleil/chatel/torgon/plan-de-croix'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pra-loup-clos-du-serre-1820m", name: "Pra Loup - Clos du Serre - 1820m", location: "Pra Loup", region: "France", latitude: 44.36097000, longitude: 6.60417300, imageUrl: skaping('pra-loup/molanes'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pra-loup-peguieou", name: "Pra Loup - Peguieou", location: "Pra Loup", region: "France", latitude: 44.34864500, longitude: 6.57744000, imageUrl: skaping('pra-loup/peguieou'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-pra-loup-station", name: "Pra Loup - Station", location: "Pra Loup", region: "France", latitude: 44.36476200, longitude: 6.60062200, imageUrl: skaping('pra-loup/station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-puget-sur-argens", name: "Puget sur Argens", location: "Puget sur Argens", region: "France", latitude: 43.45590600, longitude: 6.68452400, imageUrl: skaping('esterel/puget-sur-argens'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-reims-cath-drale", name: "Reims - Cathédrale", location: "Reims", region: "France", latitude: 49.25350827, longitude: 4.03148926, imageUrl: skaping('reims/cathedrale'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-revard-tesson", name: "Revard - Tesson", location: "Revard", region: "France", latitude: 45.68323486, longitude: 5.98805845, imageUrl: skaping('revard/tesson'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-rivedoux-plage-nord", name: "Rivedoux - Plage Nord", location: "Rivedoux", region: "France", latitude: 46.15946900, longitude: -1.27230100, imageUrl: skaping('rivedoux-plage-nord'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-rivedoux-plage-sud", name: "Rivedoux - Plage Sud", location: "Rivedoux", region: "France", latitude: 46.15736600, longitude: -1.26478300, imageUrl: skaping('rivedoux-plage-sud'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-brevin-serpent-d-oc-an", name: "Saint Brevin - Serpent d'Océan", location: "Saint Brevin", region: "France", latitude: 47.26785400, longitude: -2.17019500, imageUrl: skaping('saint-brevin-les-pins/serpent-d-ocean'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-chaffrey-place-du-t-l-ph-rique", name: "Saint Chaffrey - Place du téléphérique", location: "Saint Chaffrey", region: "France", latitude: 44.93341916, longitude: 6.58740342, imageUrl: skaping('serre-chevalier/saint-chaffrey'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-chamond", name: "Saint Chamond", location: "Saint Chamond", region: "France", latitude: 45.46157171, longitude: 4.52086329, imageUrl: skaping('saint-chamond'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-fran-ois-longchamp-le-fr-ne", name: "Saint François Longchamp - Le Frêne", location: "Saint François Longchamp", region: "France", latitude: 45.43040200, longitude: 6.39578200, imageUrl: skaping('saint-francois-longchamp/le-frene'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-jans-cappel", name: "Saint Jans Cappel", location: "Saint Jans Cappel", region: "France", latitude: 50.76344300, longitude: 2.71725300, imageUrl: skaping('saint-jans-cappel/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-jean-d-aulps-roc-d-enfer-sommet-des-t-tes", name: "Saint Jean d'Aulps - Roc d'Enfer - Sommet des Têtes", location: "Saint Jean d'Aulps", region: "France", latitude: 46.20705300, longitude: 6.62900800, imageUrl: skaping('rocdenfer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-lary-bouleaux", name: "Saint Lary - Bouleaux", location: "Saint Lary", region: "France", latitude: 42.81369006, longitude: 0.26519537, imageUrl: skaping('saint-lary/bouleaux/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-lary-tourette", name: "Saint Lary - Tourette", location: "Saint Lary", region: "France", latitude: 42.82880292, longitude: 0.23747206, imageUrl: skaping('saint-lary/tourette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-lumine-de-coutais", name: "Saint Lumine de Coutais", location: "Saint Lumine de Coutais", region: "France", latitude: 47.05537326, longitude: -1.72608733, imageUrl: skaping('saint-lumine-de-coutais'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-gervais-mont-blanc-mont-joux", name: "Saint-Gervais Mont-Blanc - Mont Joux", location: "Saint-Gervais Mont-Blanc", region: "France", latitude: 45.84624714, longitude: 6.67612016, imageUrl: skaping('saint-gervais-mont-blanc/mont-joux'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-lary-les-merlans", name: "Saint-Lary - Les Merlans", location: "Saint-Lary", region: "France", latitude: 42.82837815, longitude: 0.22058487, imageUrl: skaping('saint-lary/les-merlans'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-lary-pla-d-adet", name: "Saint-Lary - Pla d'Adet", location: "Saint-Lary", region: "France", latitude: 42.81178928, longitude: 0.29245734, imageUrl: skaping('saint-lary/pla-d-adet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-martin-de-belleville", name: "Saint-Martin-de-Belleville", location: "Saint-Martin-de-Belleville", region: "France", latitude: 45.37901600, longitude: 6.50535100, imageUrl: skaping('saintmartindebelleville/village'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-saint-pair-sur-mer", name: "Saint-Pair-sur-Mer", location: "Saint-Pair-sur-Mer", region: "France", latitude: 48.81434500, longitude: -1.57246800, imageUrl: skaping('granville-terre-mer/saint-pair-sur-mer'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-samo-ns-t-te-des-saix-2120m", name: "Samoëns - Tête des Saix - 2120m", location: "Samoëns", region: "France", latitude: 46.03163821, longitude: 6.69841591, imageUrl: skaping('tete-des-saix'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sappey-en-chartreuse", name: "Sappey en Chartreuse", location: "Sappey en Chartreuse", region: "France", latitude: 45.26008900, longitude: 5.77756500, imageUrl: skaping('sappey-en-chartreuse'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sarzeau-pano", name: "Sarzeau - Panoramique", location: "Sarzeau", region: "France", latitude: 47.48620300, longitude: -2.79180100, imageUrl: skaping('port-saint-jacques/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-col-du-lautaret", name: "Serre Chevalier - Col du Lautaret", location: "Serre Chevalier", region: "France", latitude: 45.03505027, longitude: 6.40566230, imageUrl: skaping('serrechevalier/coldulautaret'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-cucumelle", name: "Serre Chevalier - Cucumelle", location: "Serre Chevalier", region: "France", latitude: 44.93163400, longitude: 6.51019600, imageUrl: skaping('serre-chevalier/cucumelle'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-m-a", name: "Serre Chevalier - Méa", location: "Serre Chevalier", region: "France", latitude: 44.92150232, longitude: 6.52896504, imageUrl: skaping('serre-chevalier/mea'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-monetier", name: "Serre Chevalier - Monetier", location: "Serre Chevalier", region: "France", latitude: 44.94933200, longitude: 6.50061100, imageUrl: skaping('serrechevalier/monetier'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-prorel", name: "Serre Chevalier - Prorel", location: "Serre Chevalier", region: "France", latitude: 44.90393636, longitude: 6.57465219, imageUrl: skaping('serre-chevalier/prorel'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-serre-chevalier-refuge-du-cl-t-des-vaches", name: "Serre Chevalier - Refuge du Clôt des Vaches", location: "Serre Chevalier", region: "France", latitude: 45.03196800, longitude: 6.48446800, imageUrl: skaping('monetier-les-bains/refuge-clot-vaches'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-sisteron-buech-montagne-de-chabre", name: "Sisteron Buech - Montagne de Chabre ", location: "Sisteron Buech", region: "France", latitude: 44.29768413, longitude: 5.76361656, imageUrl: skaping('sisteron-buech/montagne-de-chabre'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-solaison-la-fruiti-re", name: "Solaison - La Fruitière", location: "Solaison", region: "France", latitude: 46.03321300, longitude: 6.42805800, imageUrl: skaping('plateau-de-solaison/la-fruitiere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tence-mairie", name: "Tence - Mairie", location: "Tence", region: "France", latitude: 45.11465235, longitude: 4.29045146, imageUrl: skaping('haut-lignon/tence/mairie'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tence-pont-de-tence", name: "Tence - Pont de Tence", location: "Tence", region: "France", latitude: 45.11495815, longitude: 4.28624612, imageUrl: skaping('haut-lignon/tence/pont'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-thonon-les-bains-belv-d-re", name: "Thonon-les-Bains - Belvédère", location: "Thonon-les-Bains", region: "France", latitude: 46.26995839, longitude: 6.46382332, imageUrl: skaping('thonon-les-bains/evenements'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-thonon-les-bains-port-de-rives", name: "Thonon-les-Bains - Port de Rives", location: "Thonon-les-Bains", region: "France", latitude: 46.37904729, longitude: 6.48021072, imageUrl: skaping('thonon-les-bains/port-de-rives'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-toulon-mont-faron", name: "Toulon - Mont Faron", location: "Toulon", region: "France", latitude: 43.13882500, longitude: 5.95093400, imageUrl: skaping('Toulon/mont-faron'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tournon", name: "Tournon", location: "Tournon", region: "France", latitude: 45.06965600, longitude: 4.82716100, imageUrl: skaping('tournon/tain'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tournus", name: "Tournus", location: "Tournus", region: "France", latitude: 46.56374300, longitude: 4.91530500, imageUrl: skaping('tournus'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-tramway-du-mont-blanc-gare-de-bellevue", name: "Tramway du Mont-Blanc - Gare de Bellevue", location: "Tramway du Mont-Blanc", region: "France", latitude: 45.87311931, longitude: 6.77790999, imageUrl: skaping('les-houches/tramway-du-mont-blanc'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-arly-mont-rond", name: "Val d'Arly - Mont Rond", location: "Val d'Arly", region: "France", latitude: 45.79135856, longitude: 6.55844092, imageUrl: skaping('val-d-arly/mont-rond/panoramique'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-azun-col-de-couraduque", name: "Val d'Azun - Col de Couraduque", location: "Val d'Azun", region: "France", latitude: 42.99113866, longitude: -0.20308614, imageUrl: skaping('val-d-azun/col-de-couraduque'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-borsat", name: "Val d'Isère - Borsat", location: "Val d'Isère", region: "France", latitude: 45.43283300, longitude: 6.92547800, imageUrl: skaping('valdisere/borsat'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-fornet", name: "Val d'Isère - Fornet", location: "Val d'Isère", region: "France", latitude: 45.44262000, longitude: 7.01766000, imageUrl: skaping('valdisere/fornet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-la-daille", name: "Val d'Isère - La Daille", location: "Val d'Isère", region: "France", latitude: 45.46116600, longitude: 6.96429100, imageUrl: skaping('valdisere/la-daille'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-pisaillas", name: "Val d'Isère - Pisaillas", location: "Val d'Isère", region: "France", latitude: 45.42200218, longitude: 7.04027295, imageUrl: skaping('valdisere/pisaillas'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-refuge-du-prariond", name: "Val d'Isère - Refuge du Prariond", location: "Val d'Isère", region: "France", latitude: 45.45555657, longitude: 7.07104285, imageUrl: skaping('valdisere/refuge-du-prariond'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-solaise", name: "Val d'Isère - Solaise", location: "Val d'Isère", region: "France", latitude: 45.43165700, longitude: 6.99315100, imageUrl: skaping('valdisere/solaise'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-d-is-re-vall-e-du-manchet", name: "Val d'Isère - Vallée du Manchet", location: "Val d'Isère", region: "France", latitude: 45.43073500, longitude: 6.97217000, imageUrl: skaping('valdisere/vallee-du-manchet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-3-vall-es", name: "Val Thorens - 3 Vallées", location: "Val Thorens", region: "France", latitude: 45.31247300, longitude: 6.58236200, imageUrl: skaping('valthorens/3vallees'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-boismint", name: "Val Thorens - Boismint", location: "Val Thorens", region: "France", latitude: 45.28226200, longitude: 6.55008800, imageUrl: skaping('valthorens/boismint'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-cime-caron", name: "Val Thorens - Cime Caron", location: "Val Thorens", region: "France", latitude: 45.26356982, longitude: 6.55984640, imageUrl: skaping('val-thorens/cime-caron'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-funitel-thorens", name: "Val Thorens - Funitel Thorens", location: "Val Thorens", region: "France", latitude: 45.26604600, longitude: 6.59532900, imageUrl: skaping('valthorens/funitelthorens'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-la-maison", name: "Val Thorens - La Maison", location: "Val Thorens", region: "France", latitude: 45.29788100, longitude: 6.58120800, imageUrl: skaping('valthorens/lamaison'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-lac-blanc", name: "Val Thorens - Lac Blanc", location: "Val Thorens", region: "France", latitude: 45.29692800, longitude: 6.60662600, imageUrl: skaping('valthorens/stade'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-prosneige", name: "Val Thorens - Prosneige", location: "Val Thorens", region: "France", latitude: 45.29663800, longitude: 6.57743000, imageUrl: skaping('valthorens/prosneige'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-rond-point-des-pistes", name: "Val Thorens - Rond point des pistes", location: "Val Thorens", region: "France", latitude: 45.29504900, longitude: 6.58073100, imageUrl: skaping('valthorens/station'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-snow-cam", name: "Val Thorens - Snow Cam", location: "Val Thorens", region: "France", latitude: 45.29710400, longitude: 6.57351100, imageUrl: skaping('valthorens/snowcam'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-val-thorens-tyrolienne", name: "Val Thorens - Tyrolienne", location: "Val Thorens", region: "France", latitude: 45.29058438, longitude: 6.57618642, imageUrl: skaping('val-thorens/tyrolienne-la-bee'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valence", name: "Valence", location: "Valence", region: "France", latitude: 44.93050000, longitude: 4.89014400, imageUrl: skaping('webcam-valence'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valfr-jus-punta-bagna", name: "Valfréjus - Punta Bagna", location: "Valfréjus", region: "France", latitude: 45.14431700, longitude: 6.67060800, imageUrl: skaping('valfrejus/puntabagna'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valfr-jus-tc-arrondaz", name: "Valfréjus - TC Arrondaz", location: "Valfréjus", region: "France", latitude: 45.17308400, longitude: 6.65226500, imageUrl: skaping('valfrejus/tc-arrondaz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vall-e-des-maranges", name: "Vallée des Maranges", location: "Vallée des Maranges", region: "France", latitude: 46.91405911, longitude: 4.65964615, imageUrl: skaping('saone-et-loire/vallee-des-maranges'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valloire-crey-du-quart", name: "Valloire - Crey du quart", location: "Valloire", region: "France", latitude: 45.15922400, longitude: 6.47054700, imageUrl: skaping('valloire/crey-du-quart'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valloire-poingt-ravier", name: "Valloire - Poingt Ravier", location: "Valloire", region: "France", latitude: 45.16836819, longitude: 6.42384768, imageUrl: skaping('valloire/poingt_ravier'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valmeinier-front-de-neige", name: "Valmeinier - Front de neige", location: "Valmeinier", region: "France", latitude: 45.17436627, longitude: 6.49383187, imageUrl: skaping('valmeinier/front-de-neige/photo'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valmeinier-la-sandoni-re", name: "Valmeinier - La Sandonière", location: "Valmeinier", region: "France", latitude: 45.17010229, longitude: 6.53317451, imageUrl: skaping('Valmeinier/sandoniere'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valmorel-col-du-mottet", name: "Valmorel - Col du Mottet", location: "Valmorel", region: "France", latitude: 45.42895800, longitude: 6.43298700, imageUrl: skaping('valmorel/col-du-mottet'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-valmorel-planchamp", name: "Valmorel - Planchamp", location: "Valmorel", region: "France", latitude: 45.44940588, longitude: 6.42436266, imageUrl: skaping('valmorel/planchamp'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-chabri-res", name: "Vars - Chabrières", location: "Vars", region: "France", latitude: 44.56821400, longitude: 6.66364400, imageUrl: skaping('vars/chabrieres'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-col-de-crevoux", name: "Vars - Col de Crevoux", location: "Vars", region: "France", latitude: 44.55861600, longitude: 6.65158200, imageUrl: skaping('vars/col-de-crevoux'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-les-claux", name: "Vars - Les Claux", location: "Vars", region: "France", latitude: 44.57263733, longitude: 6.67950511, imageUrl: skaping('vars/les-claux'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-mayt", name: "Vars - Mayt", location: "Vars", region: "France", latitude: 44.58705943, longitude: 6.65314436, imageUrl: skaping('vars/mayt'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-peynier", name: "Vars - Peynier", location: "Vars", region: "France", latitude: 44.57546300, longitude: 6.69911500, imageUrl: skaping('vars/peynier'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-snowpark", name: "Vars - Snowpark", location: "Vars", region: "France", latitude: 44.56069136, longitude: 6.65934563, imageUrl: skaping('vars/snowpark'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vars-speed-master", name: "Vars - Speed Master", location: "Vars", region: "France", latitude: 44.57097500, longitude: 6.64339500, imageUrl: skaping('vars/speed-master'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vaujany-alpette", name: "Vaujany - Alpette", location: "Vaujany", region: "France", latitude: 45.13951522, longitude: 6.09310985, imageUrl: skaping('alpedhuez/vaujany/alpette'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-vaujany-montfrais", name: "Vaujany - Montfrais", location: "Vaujany", region: "France", latitude: 45.15972212, longitude: 6.10003258, imageUrl: skaping('alpedhuez/vaujany/montfrais'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-verbier-w", name: "Verbier - W ", location: "Verbier", region: "France", latitude: 46.09234653, longitude: 7.23320961, imageUrl: skaping('verbier/hotel-w'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-verdun-ciel", name: "Verdun Ciel", location: "Verdun Ciel", region: "France", latitude: 46.89612700, longitude: 5.02547100, imageUrl: skaping('verdun-sur-le-doubs'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-veretz-ch-teau", name: "Veretz - Château", location: "Veretz", region: "France", latitude: 47.36085686, longitude: 0.80481827, imageUrl: skaping('montlouis-vouvray/veretz'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-villar-d-ar-ne-nordique", name: "Villar d'Arène - Nordique", location: "Villar d'Arène", region: "France", latitude: 45.03082896, longitude: 6.36318147, imageUrl: skaping('villar-d-arene/arsine'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-villefranche-de-rouergue", name: "Villefranche de Rouergue", location: "Villefranche de Rouergue", region: "France", latitude: 44.35378990, longitude: 2.03671932, imageUrl: skaping('bastides-gorges-aveyron/villefranche-de-rouergue'), streamUrl: null, source: "Skaping", refreshInterval: 600 },
      { id: "sk-villeneuve", name: "Villeneuve", location: "Villeneuve", region: "France", latitude: 44.43770593, longitude: 2.03349531, imageUrl: skaping('bastides-gorges-aveyron/villeneuve'), streamUrl: null, source: "Skaping", refreshInterval: 600 },

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
      { id: "vs-landeda", name: "Panoramique HD", location: "Landéda", region: "Bretagne", latitude: 48.5976516, longitude: -4.5611901, imageUrl: viewsurf(19280), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
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
      { id: "vs-etretat", name: "Falaises Nord", location: "Étretat", region: "Normandie", latitude: 49.706435, longitude: 0.211127, imageUrl: viewsurf(17574), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-le-havre", name: "Le Port", location: "Le Havre", region: "Normandie", latitude: 49.5035623, longitude: 0.1211814, imageUrl: viewsurfStream('vs-le-havre'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-dieppe", name: "La Plage", location: "Dieppe", region: "Normandie", latitude: 49.9266519, longitude: 1.0793188, imageUrl: viewsurfStream('vs-dieppe'), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
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
      { id: "vs-la-tranche", name: "La Plage", location: "La Tranche-sur-Mer", region: "Pays de la Loire", latitude: 46.3418042, longitude: -1.3931204, imageUrl: viewsurf(18790), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
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
      { id: "vs-cannes", name: "La Croisette", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5442689, longitude: 6.9644383, imageUrl: viewsurf(18150), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-menton", name: "Panoramique HD", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7750, longitude: 7.5000, imageUrl: viewsurf(17702), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-tropez", name: "Le Port", location: "Saint-Tropez", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2667, longitude: 6.6333, imageUrl: viewsurf(19428), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-ste-maxime", name: "Vue Saint-Tropez", location: "Sainte-Maxime", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3167, longitude: 6.6333, imageUrl: viewsurf(11328), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-frejus", name: "La Plage", location: "Fréjus", region: "Provence-Alpes-Côte d'Azur", latitude: 43.4333, longitude: 6.7333, imageUrl: viewsurf(18360), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-st-raphael", name: "La Plage", location: "Saint-Raphaël", region: "Provence-Alpes-Côte d'Azur", latitude: 43.4167, longitude: 6.7667, imageUrl: viewsurf(16184), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-cavalaire", name: "La Plage", location: "Cavalaire-sur-Mer", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1667, longitude: 6.5333, imageUrl: viewsurf(14296), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
      { id: "vs-lavandou", name: "Le Port", location: "Le Lavandou", region: "Provence-Alpes-Côte d'Azur", latitude: 43.149296, longitude: 6.4017559, imageUrl: viewsurf(10514), streamUrl: null, source: "Viewsurf", refreshInterval: 300 },
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
      { id: "ve-st-cast", name: "La Plage", location: "Saint-Cast-le-Guildo", region: "Bretagne", latitude: 48.640456, longitude: -2.247707, imageUrl: vision('stcast'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-erquy", name: "Le Port", location: "Erquy", region: "Bretagne", latitude: 48.635612, longitude: -2.473293, imageUrl: vision('erquy'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-binic", name: "Le Port", location: "Binic", region: "Bretagne", latitude: 48.601485, longitude: -2.82492, imageUrl: vision('binic'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-quay", name: "Le Port", location: "Saint-Quay-Portrieux", region: "Bretagne", latitude: 48.656658, longitude: -2.837949, imageUrl: vision('sqpp'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-perros-port", name: "Le Port", location: "Perros-Guirec", region: "Bretagne", latitude: 48.8057137, longitude: -3.4424482, imageUrl: vision('portperrosguirec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-perros-trestraou", name: "Trestraou", location: "Perros-Guirec", region: "Bretagne", latitude: 48.8161733, longitude: -3.459455, imageUrl: vision('trestraou'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ploumanach", name: "Le Port", location: "Ploumanac'h", region: "Bretagne", latitude: 48.8281566, longitude: -3.4861887, imageUrl: vision('portploumanach'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/6726ebb0-fe34-4734-746c-7561-6665-64-b54d-72cc36d09f92d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-tregastel", name: "La Plage", location: "Trégastel", region: "Bretagne", latitude: 48.8327451, longitude: -3.5177063, imageUrl: vision('tregastel'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-locquirec", name: "La Plage", location: "Locquirec", region: "Bretagne", latitude: 48.692623, longitude: -3.645083, imageUrl: vision('locquirec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lannion", name: "La Ville", location: "Lannion", region: "Bretagne", latitude: 48.756639, longitude: -3.4723721, imageUrl: vision('lannion'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-plouescat", name: "La Plage", location: "Plouescat", region: "Bretagne", latitude: 48.658735, longitude: -4.222012, imageUrl: vision('plouescat'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-carantec", name: "La Plage", location: "Carantec", region: "Bretagne", latitude: 48.667815, longitude: -3.914055, imageUrl: vision('carantec'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-roscoff", name: "Le Port", location: "Roscoff", region: "Bretagne", latitude: 48.726102, longitude: -3.982375, imageUrl: vision('roscoff'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-batz", name: "L'Île", location: "Île de Batz", region: "Bretagne", latitude: 48.7452879, longitude: -4.0267446, imageUrl: vision('iledebatz'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-pol", name: "La Baie", location: "Saint-Pol-de-Léon", region: "Bretagne", latitude: 48.685113, longitude: -3.986533, imageUrl: vision('stpol'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-morlaix", name: "Le Port", location: "Morlaix", region: "Bretagne", latitude: 48.5846913, longitude: -3.834592, imageUrl: vision('morlaix'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-brest-port", name: "Moulin Blanc", location: "Brest", region: "Bretagne", latitude: 48.3921663, longitude: -4.4349039, imageUrl: vision('brest-port'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/43563c6a-f168-4ff2-746c-7561-6665-64-a238-ef6b7454e47ed/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-landeda", name: "Aber Wrac'h", location: "Landéda", region: "Bretagne", latitude: 48.5833, longitude: -4.5667, imageUrl: vision('landeda'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-portsall", name: "Le Port", location: "Ploudalmézeau", region: "Bretagne", latitude: 48.555362, longitude: -4.699514, imageUrl: vision('portsall'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-conquet", name: "Kermorvan", location: "Le Conquet", region: "Bretagne", latitude: 48.3625604, longitude: -4.7971308, imageUrl: vision('leconquet'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-plougonvelin", name: "La Plage", location: "Plougonvelin", region: "Bretagne", latitude: 48.346647, longitude: -4.704092, imageUrl: vision('plougonvelin'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/2d3150ea-fd0f-4d15-746c-7561-6665-64-9d2b-705100911459d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-sein", name: "L'Île", location: "Île de Sein", region: "Bretagne", latitude: 48.0354619, longitude: -4.8494872, imageUrl: vision('ile-de-sein'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-pointe-raz", name: "La Pointe", location: "Pointe du Raz", region: "Bretagne", latitude: 48.0400, longitude: -4.7404, imageUrl: vision('pointe-du-raz'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/0c6e6ed3-7436-48c8-746c-7561-6665-64-9230-1f27453a1a3bd/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-audierne-port", name: "Le Port", location: "Audierne", region: "Bretagne", latitude: 48.023898, longitude: -4.5381225, imageUrl: vision('audierne-port'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-esquibien", name: "Le Pouldu", location: "Esquibien", region: "Bretagne", latitude: 48.005941, longitude: -4.5584004, imageUrl: vision('esquibien'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/754f14bd-21c6-4ffb-746c-7561-6665-64-a179-4545dd743885d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-douarnenez-port", name: "Port Rosmeur", location: "Douarnenez", region: "Bretagne", latitude: 48.0954883, longitude: -4.3254745, imageUrl: vision('douarnenez-rosmeur'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/f240ba9d-e047-4f5b-746c-7561-6665-64-9cf5-f7b69e836909d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-douarnenez-plage", name: "Sables Blancs", location: "Douarnenez", region: "Bretagne", latitude: 48.102376, longitude: -4.353041, imageUrl: vision('douarnenez'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/1f1a5b37-b247-4e15-746c-7561-6665-64-aa5e-d27be2eaf3d7d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-houat", name: "L'Île", location: "Île de Houat", region: "Bretagne", latitude: 47.3921675, longitude: -2.9589522, imageUrl: vision('houat'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-penestin", name: "La Plage", location: "Pénestin", region: "Bretagne", latitude: 47.4671613, longitude: -2.491509, imageUrl: vision('penestin'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-piriac", name: "Le Port", location: "Piriac-sur-Mer", region: "Bretagne", latitude: 47.3808889, longitude: -2.5432384, imageUrl: vision('piriac-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-bono", name: "Le Port", location: "Le Bono", region: "Bretagne", latitude: 47.6392349, longitude: -2.9539792, imageUrl: vision('le-bono'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gavres", name: "Port de Gâvres", location: "Larmor-Plage", region: "Bretagne", latitude: 47.7188829, longitude: -3.3696132, imageUrl: vision('gavres'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/3d1106a9-4c03-45b6-746c-7561-6665-64-90db-5c15b5f9deb2d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - NORMANDIE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-etretat", name: "Les Falaises", location: "Étretat", region: "Normandie", latitude: 49.7069, longitude: 0.2061, imageUrl: vision('etretat'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/2fe83b0a-8f3f-4531-746c-7561-6665-64-b260-5af4b6d5cef8d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-fecamp", name: "Le Port", location: "Fécamp", region: "Normandie", latitude: 49.7636899, longitude: 0.3647388, imageUrl: vision('fecam'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-havre", name: "Fort Tourneville", location: "Le Havre", region: "Normandie", latitude: 49.4944, longitude: 0.1078, imageUrl: vision('tourneville'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-valery", name: "La Plage", location: "Saint-Valery-en-Caux", region: "Normandie", latitude: 49.8699859, longitude: 0.7155556, imageUrl: vision('saint-valery-en-caux-casino'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-dieppe", name: "La Plage", location: "Dieppe", region: "Normandie", latitude: 49.9256, longitude: 1.0828, imageUrl: vision('dieppe-ango'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-le-treport", name: "Le Port", location: "Le Tréport", region: "Normandie", latitude: 50.0682203, longitude: 1.4273016, imageUrl: vision('letreport'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/79c14f99-2f24-482f-746c-7561-6665-64-a07d-e4602273c06bd/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-trouville", name: "Le Port", location: "Trouville-sur-Mer", region: "Normandie", latitude: 49.3653, longitude: 0.0786, imageUrl: vision('port-trouville-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cabourg", name: "Promenade Marcel Proust", location: "Cabourg", region: "Normandie", latitude: 49.293729, longitude: -0.115551, imageUrl: vision('cabourg2-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-houlgate", name: "La Plage", location: "Houlgate", region: "Normandie", latitude: 49.3047013, longitude: -0.0756181, imageUrl: vision('houlgate'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ouistreham", name: "Le Port", location: "Ouistreham", region: "Normandie", latitude: 49.290291, longitude: -0.257038, imageUrl: vision('ouistreham'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-langrune", name: "La Plage", location: "Langrune-sur-Mer", region: "Normandie", latitude: 49.3250047, longitude: -0.3706106, imageUrl: vision('langrune-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-luc-sur-mer", name: "La Plage", location: "Luc-sur-Mer", region: "Normandie", latitude: 49.321635, longitude: -0.357836, imageUrl: vision('luc-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-aubin", name: "La Plage", location: "Saint-Aubin-sur-Mer", region: "Normandie", latitude: 49.893437, longitude: 0.870132, imageUrl: vision('staubin'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-jullouville", name: "La Plage", location: "Jullouville", region: "Normandie", latitude: 48.770885, longitude: -1.567332, imageUrl: vision('jullouville'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-pirou", name: "La Plage", location: "Pirou", region: "Normandie", latitude: 49.16703, longitude: -1.598253, imageUrl: vision('pirou'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-germain", name: "La Plage", location: "Saint-Germain-sur-Ay", region: "Normandie", latitude: 49.231019, longitude: -1.647477, imageUrl: vision('stgermain'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - HAUTS-DE-FRANCE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-boulogne", name: "Le Port", location: "Boulogne-sur-Mer", region: "Hauts-de-France", latitude: 50.7250585, longitude: 1.6000322, imageUrl: vision('boulogne'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-wimereux", name: "La Plage", location: "Wimereux", region: "Hauts-de-France", latitude: 50.7657372, longitude: 1.6040507, imageUrl: vision('wimereux'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-wissant", name: "La Plage", location: "Wissant", region: "Hauts-de-France", latitude: 50.8806922, longitude: 1.6569442, imageUrl: vision('wissant'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-sangatte", name: "La Plage", location: "Sangatte", region: "Hauts-de-France", latitude: 50.9523164, longitude: 1.770986, imageUrl: vision('sangatte'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gravelines", name: "Le Port", location: "Gravelines", region: "Hauts-de-France", latitude: 50.98379, longitude: 2.1176908, imageUrl: vision('gravelines'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - PAYS DE LA LOIRE / VENDÉE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-la-baule", name: "La Plage", location: "La Baule", region: "Pays de la Loire", latitude: 47.286918, longitude: -2.391378, imageUrl: vision('labaule'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-noirmoutier", name: "Le Bois de la Chaize", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.9986, longitude: -2.2458, imageUrl: vision('noirmoutier'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/ecefb736-517d-472b-746c-7561-6665-64-93d8-c840e8147268d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-gois", name: "Passage du Gois", location: "Noirmoutier", region: "Pays de la Loire", latitude: 46.921184, longitude: -2.10365, imageUrl: vision('gois'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/b5e7710b-94c9-48a0-746c-7561-6665-64-aeac-6a516e868621d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-herbaudiere", name: "L'Herbaudière", location: "Noirmoutier", region: "Pays de la Loire", latitude: 47.024028, longitude: -2.297358, imageUrl: vision('herbaudiere'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/c2262b2a-ed62-416b-746c-7561-6665-64-8740-7af835c1d5d5d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-hilaire", name: "La Plage", location: "Saint-Hilaire-de-Riez", region: "Pays de la Loire", latitude: 46.699504, longitude: -1.974041, imageUrl: vision('sthilairederiez'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-jard", name: "La Plage", location: "Jard-sur-Mer", region: "Pays de la Loire", latitude: 46.408912, longitude: -1.574044, imageUrl: vision('jardsurmer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-la-tranche", name: "La Plage", location: "La Tranche-sur-Mer", region: "Pays de la Loire", latitude: 46.3500, longitude: -1.4333, imageUrl: vision('latranche'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CHARENTE-MARITIME
      // ═══════════════════════════════════════════════════════════
      { id: "ve-bourcefranc", name: "Le Port", location: "Bourcefranc-le-Chapus", region: "Nouvelle-Aquitaine", latitude: 45.8547591, longitude: -1.1699266, imageUrl: vision('bourcefranc'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-cotiniere", name: "La Cotinière", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 45.9140475, longitude: -1.328655, imageUrl: vision('cotiniere'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-chassiron", name: "Phare Chassiron", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 46.046635, longitude: -1.410303, imageUrl: vision('chassiron'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-perroche", name: "La Perroche", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 45.900698, longitude: -1.2946657, imageUrl: vision('perroche'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-oleron-huttes", name: "Les Huttes", location: "Île d'Oléron", region: "Nouvelle-Aquitaine", latitude: 46.0055232, longitude: -1.3920446, imageUrl: vision('oleron-les-huttes'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-trojan", name: "La Plage", location: "Saint-Trojan-les-Bains", region: "Nouvelle-Aquitaine", latitude: 45.8297747, longitude: -1.1981307, imageUrl: vision('saint-trojan-les-bains'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CÔTE D'AZUR / PACA
      // ═══════════════════════════════════════════════════════════
      { id: "ve-menton", name: "La Baie", location: "Menton", region: "Provence-Alpes-Côte d'Azur", latitude: 43.7750, longitude: 7.5000, imageUrl: vision('menton'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-villefranche", name: "La Rade", location: "Villefranche-sur-Mer", region: "Provence-Alpes-Côte d'Azur", latitude: 43.6973658, longitude: 7.3044422, imageUrl: vision('villefranche-sur-mer'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-laurent", name: "La Plage", location: "Saint-Laurent-du-Var", region: "Provence-Alpes-Côte d'Azur", latitude: 43.6572529, longitude: 7.183128, imageUrl: vision('saint-laurent-du-var'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cannes", name: "Plage Thales", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5481294, longitude: 7.0095682, imageUrl: vision('cannes'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cannes-quai", name: "Quai Laubeuf", location: "Cannes", region: "Provence-Alpes-Côte d'Azur", latitude: 43.5500, longitude: 7.0167, imageUrl: vision('cannes-quai-laubeuf'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-issambres", name: "La Plage", location: "Les Issambres", region: "Provence-Alpes-Côte d'Azur", latitude: 43.3419742, longitude: 6.6909505, imageUrl: vision('issambres'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres", name: "L'Almanarre", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.080026, longitude: 6.123038, imageUrl: vision('hyeres3-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres-kite", name: "Plage Estagniers", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.049237, longitude: 6.1318845, imageUrl: vision('Hyeres-kite'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-hyeres-port", name: "Port Saint-Pierre", location: "Hyères", region: "Provence-Alpes-Côte d'Azur", latitude: 43.083026, longitude: 6.159904, imageUrl: vision('hyeres2-'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-st-mandrier", name: "Le Port", location: "Saint-Mandrier", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0803035, longitude: 5.9228415, imageUrl: vision('saint-mandrier'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/c3d76725-bb79-46ce-746c-7561-6665-64-a36b-d88a73472f6cd/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-six-fours", name: "La Plage", location: "Six-Fours-les-Plages", region: "Provence-Alpes-Côte d'Azur", latitude: 43.0729035, longitude: 5.7930941, imageUrl: vision('sixfours2'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-toulon", name: "Vieille Darse", location: "Toulon", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1167, longitude: 5.9333, imageUrl: vision('toulon-vieille-darse'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/8815ba41-8776-41d1-746c-7561-6665-64-b026-f40af303b567d/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lavandou", name: "Aiguebelle", location: "Le Lavandou", region: "Provence-Alpes-Côte d'Azur", latitude: 43.1333, longitude: 6.3667, imageUrl: vision('lavandou-aiguebelle'), streamUrl: "https://visionenvironnement.quanteec.com/contents/encodings/live/d804eeb7-602f-453b-746c-7561-6665-64-a47a-1bc3f1e9551ad/master.m3u8", source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-carro", name: "Le Port", location: "Carro", region: "Provence-Alpes-Côte d'Azur", latitude: 43.331839, longitude: 5.035459, imageUrl: vision('carro'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-marseille-port", name: "Vieux Port", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.2949332, longitude: 5.3723787, imageUrl: vision('marseilleport'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-marseille-samena", name: "Calanque Samena", location: "Marseille", region: "Provence-Alpes-Côte d'Azur", latitude: 43.228509, longitude: 5.351584, imageUrl: vision('samena'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-sete", name: "Le Port", location: "Sète", region: "Occitanie", latitude: 43.4014166, longitude: 3.6568807, imageUrl: vision('sete'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - CORSE
      // ═══════════════════════════════════════════════════════════
      { id: "ve-ajaccio-port", name: "Port Tino Rossi", location: "Ajaccio", region: "Corse", latitude: 41.9307955, longitude: 8.7402163, imageUrl: vision('ajaccioport2'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ajaccio-pano", name: "Panoramique", location: "Ajaccio", region: "Corse", latitude: 41.9118982, longitude: 8.7095553, imageUrl: vision('ajaccio-panorama'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-bastia", name: "Le Port", location: "Bastia", region: "Corse", latitude: 42.704454, longitude: 9.455541, imageUrl: vision('bastia'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-bonifacio", name: "Le Port", location: "Bonifacio", region: "Corse", latitude: 41.388678, longitude: 9.1565014, imageUrl: vision('bonifacio'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-propriano", name: "Le Port", location: "Propriano", region: "Corse", latitude: 41.6770794, longitude: 8.897552, imageUrl: vision('propriano'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-cargese", name: "Le Port", location: "Cargèse", region: "Corse", latitude: 42.1320085, longitude: 8.5960404, imageUrl: vision('cargese'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-ile-rousse", name: "La Plage", location: "L'Île-Rousse", region: "Corse", latitude: 42.641043, longitude: 8.936713, imageUrl: vision('ile-rousse'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-porto-vecchio", name: "Santa Giulia", location: "Porto-Vecchio", region: "Corse", latitude: 41.5309657, longitude: 9.280931, imageUrl: vision('santa-giulia'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-porto-vecchio-port", name: "Port Commerce", location: "Porto-Vecchio", region: "Corse", latitude: 41.5867395, longitude: 9.2909905, imageUrl: vision('portportovecchio'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

      // ═══════════════════════════════════════════════════════════
      // VISION-ENVIRONNEMENT - LACS
      // ═══════════════════════════════════════════════════════════
      { id: "ve-lac-madine", name: "Lac de Madine", location: "Nonsard-Lamarche", region: "Grand Est", latitude: 48.9280277, longitude: 5.7498388, imageUrl: vision('lac-de-madine'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lac-settons", name: "Lac des Settons", location: "Montsauche-les-Settons", region: "Bourgogne-Franche-Comté", latitude: 47.1882544, longitude: 4.0679986, imageUrl: vision('lac-des-settons'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },
      { id: "ve-lac-st-point", name: "Lac Saint-Point", location: "Malbuisson", region: "Bourgogne-Franche-Comté", latitude: 46.8024665, longitude: 6.3013528, imageUrl: vision('malbuisson'), streamUrl: null, source: "Vision-Env", refreshInterval: 300 },

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
