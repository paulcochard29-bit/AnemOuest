// Viewsurf Stream Capture API
// Captures frames from Viewsurf HLS streams (Quanteec CDN)
// Approach: Fetch TS segment, extract I-frame, convert to JPEG
// Fallback: Store TS segment for client-side playback

import { put, list } from '../lib/storage.js';
import sharp from 'sharp';

// MPEG-TS packet size
const TS_PACKET_SIZE = 188;
const TS_SYNC_BYTE = 0x47;

// Try to extract a poster/thumbnail URL from the stream path
function getStreamPosterUrl(streamUrl) {
  // Quanteec sometimes has poster images at similar paths
  // Try common patterns for poster/thumbnail URLs
  // Handle both master.m3u8 and media_0.m3u8 formats
  const baseUrl = streamUrl
    .replace(/\/master\.m3u8$/, '')
    .replace(/\/media_\d+\.m3u8$/, '');
  return [
    `${baseUrl}/poster.jpg`,
    `${baseUrl}/thumbnail.jpg`,
    `${baseUrl}/cover.jpg`,
    streamUrl.replace('/media_0.m3u8', '/poster.jpg'),
    streamUrl.replace('/master.m3u8', '/poster.jpg'),
  ];
}

// Parse MPEG-TS to find video PES packets and extract H.264 NAL units
function extractVideoData(tsBuffer) {
  const packets = [];
  let pos = 0;

  // Find sync byte
  while (pos < tsBuffer.length && tsBuffer[pos] !== TS_SYNC_BYTE) {
    pos++;
  }

  // Parse TS packets
  while (pos + TS_PACKET_SIZE <= tsBuffer.length) {
    if (tsBuffer[pos] !== TS_SYNC_BYTE) {
      pos++;
      continue;
    }

    const packet = tsBuffer.slice(pos, pos + TS_PACKET_SIZE);
    const pid = ((packet[1] & 0x1f) << 8) | packet[2];
    const hasPayload = (packet[3] & 0x10) !== 0;
    const hasAdaptation = (packet[3] & 0x20) !== 0;

    if (hasPayload && pid !== 0 && pid !== 0x1fff) {
      let payloadStart = 4;
      if (hasAdaptation) {
        payloadStart += 1 + packet[4];
      }

      if (payloadStart < TS_PACKET_SIZE) {
        packets.push({
          pid,
          payload: packet.slice(payloadStart)
        });
      }
    }

    pos += TS_PACKET_SIZE;
  }

  return packets;
}

// Known Viewsurf m3u8 stream URLs (from Quanteec CDN)
const VIEWSURF_STREAMS = {
  // Bretagne - Finistère
  'vs-fouesnant-capi': 'https://ds1-cache.quanteec.com/contents/encodings/live/99ef199d-276c-4858-3731-3230-6d61-63-8ae5-83cef40fc28bd/media_0.m3u8',
  'vs-benodet': 'https://ds2-cache.quanteec.com/contents/encodings/live/56caa721-02b2-4031-3430-3130-6d61-63-b9f9-f23307135ec5d/media_0.m3u8',
  'vs-penmarch': 'https://ds2-cache.quanteec.com/contents/encodings/live/068f1c25-1be9-4494-3439-3330-6d61-63-837f-3e21424f20a2d/media_0.m3u8',
  'vs-penmarch-st-guenole': 'https://ds2-cache.quanteec.com/contents/encodings/live/42de5499-f4e1-425f-3236-3130-6d61-63-8320-013bf9662d2cd/media_0.m3u8',
  'vs-guilvinec': 'https://ds2-cache.quanteec.com/contents/encodings/live/7b24320f-47ce-4242-3333-3230-6d61-63-9244-9275136a96bdd/media_0.m3u8',
  'vs-cap-coz': 'https://ds2-cache.quanteec.com/contents/encodings/live/5a3840a9-818c-432d-3831-3230-6d61-63-b94e-ec74c6293339d/media_0.m3u8',
  'vs-crozon': 'https://ds2-cache.quanteec.com/contents/encodings/live/a57d6076-bcdd-4e1b-3738-3130-6d61-63-ba69-112b409efb73d/media_0.m3u8',
  'vs-mousterlin': 'https://ds2-cache.quanteec.com/contents/encodings/live/357fc1ec-7bbe-404f-3631-3230-6d61-63-a54d-53c79aaee76ed/media_0.m3u8',
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
  'vs-dieppe-2': 'https://ds2-cache.quanteec.com/contents/encodings/live/90182dbb-0d89-45e1-3531-3730-6d61-63-8bf8-edad6928536ed/media_0.m3u8',
  'vs-siouville': 'https://ds2-cache.quanteec.com/contents/encodings/live/a89f3474-9d1c-40dd-3437-3230-6d61-63-a5fd-58da85d36f6cd/media_0.m3u8',
  'vs-goury': 'https://ds2-cache.quanteec.com/contents/encodings/live/ae1a4a8c-784b-4571-3537-3230-6d61-63-a65b-ceb2396bd8add/media_0.m3u8',
  'vs-barneville': 'https://ds2-cache.quanteec.com/contents/encodings/live/273a3e7a-b125-4cb1-3839-3030-6d61-63-a49f-22af76e7fbf2d/media_0.m3u8',

  // Hauts-de-France
  'vs-dunkerque': 'https://ds2-cache.quanteec.com/contents/encodings/live/8d9f7a17-a395-4be6-3739-3130-6d61-63-b32b-4069d95be7a5d/media_0.m3u8',
  'vs-bray-dunes': 'https://ds2-cache.quanteec.com/contents/encodings/live/4e0100d6-7bc4-43be-3839-3130-6d61-63-bd66-bcfd64e27574d/media_0.m3u8',
  'vs-zuydcoote': 'https://ds2-cache.quanteec.com/contents/encodings/live/8f0170c0-1b41-48f9-3030-3230-6d61-63-98e4-bc495cd8d793d/media_0.m3u8',
  'vs-calais': 'https://ds2-cache.quanteec.com/contents/encodings/live/d5e9f551-7435-4ea6-3532-3130-6d61-63-916e-ff1d72543cced/media_0.m3u8',
  'vs-hardelot': 'https://ds2-cache.quanteec.com/contents/encodings/live/16d1ad82-49dc-491a-3433-3230-6d61-63-a59d-fc77596c2e6dd/media_0.m3u8',

  // Pays Basque
  'vs-anglet': 'https://ds2-cache.quanteec.com/contents/encodings/live/c56ac32d-4df6-4924-3430-3030-6d61-63-9e97-d84cc86e129bd/media_0.m3u8',

  // Côte d'Azur
  'vs-nice': 'https://ds2-cache.quanteec.com/contents/encodings/live/44325ee8-0cde-4f0c-3737-3330-6d61-63-a448-371421fe696ad/media_0.m3u8',

  // Custom webcams (from KV additions)
  'new-1770302739665': 'https://ds1-cache.quanteec.com/contents/encodings/live/5a3840a9-818c-432d-3831-3230-6d61-63-b94e-ec74c6293339d/media_0.m3u8', // Cap Coz
  'new-1770303647286': 'https://ds2-cache.quanteec.com/contents/encodings/live/42de5499-f4e1-425f-3236-3130-6d61-63-8320-013bf9662d2cd/media_0.m3u8', // Le Port Penmarch
  'new-1770303809736': 'https://ds1-cache.quanteec.com/contents/encodings/live/068f1c25-1be9-4494-3439-3330-6d61-63-837f-3e21424f20a2d/media_0.m3u8', // Le Port Kerity

  // Vision-Environnement webcams (Quanteec CDN)
  've-binic': 'https://visionenvironnement.quanteec.com/contents/encodings/live/eaf789b3-a03f-4137-746c-7561-6665-64-9685-3288bd76a811d/media_0.m3u8',
  've-perros-port': 'https://visionenvironnement.quanteec.com/contents/encodings/live/0bbb7e52-0b32-4070-746c-7561-6665-64-8a7c-2ba5adb3143dd/media_0.m3u8',
  've-perros-trestraou': 'https://visionenvironnement.quanteec.com/contents/encodings/live/87a59365-6a80-4e3b-746c-7561-6665-64-8e67-a5d4fdced41cd/media_0.m3u8',
  've-ploumanach': 'https://visionenvironnement.quanteec.com/contents/encodings/live/6726ebb0-fe34-4734-746c-7561-6665-64-b54d-72cc36d09f92d/media_0.m3u8',
  've-tregastel': 'https://visionenvironnement.quanteec.com/contents/encodings/live/eb282cec-a15f-4a35-746c-7561-6665-64-818a-cedda620ee9dd/media_0.m3u8',
  've-locquirec': 'https://visionenvironnement.quanteec.com/contents/encodings/live/f805f657-0d7f-4d9e-746c-7561-6665-64-a08c-2306bf8dfd65d/media_0.m3u8',
  've-brest-port': 'https://visionenvironnement.quanteec.com/contents/encodings/live/43563c6a-f168-4ff2-746c-7561-6665-64-a238-ef6b7454e47ed/media_0.m3u8',
  've-portsall': 'https://visionenvironnement.quanteec.com/contents/encodings/live/25eb1639-dd59-4861-746c-7561-6665-64-97e3-3118969944e0d/media_0.m3u8',
  've-conquet': 'https://visionenvironnement.quanteec.com/contents/encodings/live/23a9a824-6db4-4ae2-746c-7561-6665-64-9f20-b489dda0d6d6d/media_0.m3u8',
  've-ile-sein': 'https://visionenvironnement.quanteec.com/contents/encodings/live/3665df87-975d-4e72-746c-7561-6665-64-9547-dc2c348448c1d/media_0.m3u8',
  've-pointe-raz': 'https://visionenvironnement.quanteec.com/contents/encodings/live/0c6e6ed3-7436-48c8-746c-7561-6665-64-9230-1f27453a1a3bd/media_0.m3u8',
  've-audierne-port': 'https://visionenvironnement.quanteec.com/contents/encodings/live/917376b5-2fd1-4282-746c-7561-6665-64-b293-6479a76ee9cad/media_0.m3u8',
  've-esquibien': 'https://visionenvironnement.quanteec.com/contents/encodings/live/754f14bd-21c6-4ffb-746c-7561-6665-64-a179-4545dd743885d/media_0.m3u8',
  've-douarnenez-plage': 'https://visionenvironnement.quanteec.com/contents/encodings/live/1f1a5b37-b247-4e15-746c-7561-6665-64-aa5e-d27be2eaf3d7d/media_0.m3u8',
  've-penestin': 'https://visionenvironnement.quanteec.com/contents/encodings/live/6c8db124-f44e-4da1-746c-7561-6665-64-a7db-77db9ffc8c43d/media_0.m3u8',
  've-gavres': 'https://visionenvironnement.quanteec.com/contents/encodings/live/3d1106a9-4c03-45b6-746c-7561-6665-64-90db-5c15b5f9deb2d/media_0.m3u8',
  've-gois': 'https://visionenvironnement.quanteec.com/contents/encodings/live/b5e7710b-94c9-48a0-746c-7561-6665-64-aeac-6a516e868621d/media_0.m3u8',
  've-herbaudiere': 'https://visionenvironnement.quanteec.com/contents/encodings/live/c2262b2a-ed62-416b-746c-7561-6665-64-8740-7af835c1d5d5d/media_0.m3u8',
  've-toulon': 'https://visionenvironnement.quanteec.com/contents/encodings/live/ab36f88f-c448-4f69-746c-7561-6665-64-9f13-cd6067dc2a80d/media_0.m3u8',
  've-ajaccio-pano': 'https://visionenvironnement.quanteec.com/contents/encodings/live/a38bc0bb-2cf8-48e4-746c-7561-6665-64-bb18-9b9ffc7bff63d/media_0.m3u8',
  've-propriano': 'https://visionenvironnement.quanteec.com/contents/encodings/live/50e032b9-8e2c-4fc4-746c-7561-6665-64-b640-ebc6bfede494d/media_0.m3u8',
  've-cargese': 'https://visionenvironnement.quanteec.com/contents/encodings/live/41e2c7ad-2e0f-42f6-746c-7561-6665-64-8465-8bb7389e4290d/media_0.m3u8',
};

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { id, action, quality, width, streamUrl: dynamicStreamUrl, timestamp } = req.query;

  // List available streams
  if (action === 'list') {
    return res.status(200).json({
      streams: Object.keys(VIEWSURF_STREAMS),
      count: Object.keys(VIEWSURF_STREAMS).length
    });
  }

  if (!id) {
    return res.status(400).json({ error: 'Missing id parameter' });
  }

  // Dynamic streamUrl parameter takes priority over hardcoded list
  // This allows admin overrides to change the stream for any webcam
  let streamUrl;
  if (dynamicStreamUrl) {
    streamUrl = dynamicStreamUrl;
  } else {
    streamUrl = VIEWSURF_STREAMS[id];
  }

  if (!streamUrl && !timestamp) {
    return res.status(404).json({
      error: 'Stream not found',
      id,
      note: 'Pass streamUrl parameter for webcams not in hardcoded list'
    });
  }

  // Historical image: serve from Blob storage
  if (timestamp) {
    try {
      const ts = parseInt(timestamp);
      const prefix = `webcams/${id}/${ts}.jpg`;
      const { blobs } = await list({ prefix, limit: 1 });

      if (blobs.length > 0 && blobs[0].pathname === prefix) {
        const blobResponse = await fetch(blobs[0].url);
        if (blobResponse.ok) {
          const imageBuffer = Buffer.from(await blobResponse.arrayBuffer());
          res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=86400');
          res.setHeader('Content-Type', 'image/jpeg');
          res.setHeader('X-Image-Timestamp', ts.toString());
          res.setHeader('X-Source', 'blob-history');
          return res.status(200).send(imageBuffer);
        }
      }

      // Blob not found for this timestamp
      if (!streamUrl) {
        return res.status(404).json({ error: 'Historical image not found', id, timestamp: ts });
      }
      // Fall through to live capture if streamUrl available
    } catch (e) {
      console.log(`Blob history lookup failed for ${id}/${timestamp}:`, e.message);
      if (!streamUrl) {
        return res.status(404).json({ error: 'Historical image not found', id });
      }
    }
  }

  try {
    // Step 0: Try poster/thumbnail URLs first (fastest path)
    const posterUrls = getStreamPosterUrl(streamUrl);
    for (const posterUrl of posterUrls) {
      try {
        const posterResponse = await fetch(posterUrl, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
            'Accept': 'image/*',
            'Origin': 'https://www.viewsurf.com',
            'Referer': 'https://www.viewsurf.com/',
          },
          signal: AbortSignal.timeout(3000),
        });

        if (posterResponse.ok) {
          const contentType = posterResponse.headers.get('content-type');
          if (contentType && contentType.includes('image')) {
            const imageBuffer = Buffer.from(await posterResponse.arrayBuffer());
            if (imageBuffer.length > 5000) {
              console.log(`Found poster image at ${posterUrl}`);

              // Process with sharp
              const targetWidth = parseInt(width) || 1200;
              const targetQuality = parseInt(quality) || 80;

              const processedImage = await sharp(imageBuffer)
                .resize(targetWidth, null, { withoutEnlargement: true })
                .jpeg({ quality: targetQuality, progressive: true })
                .toBuffer();

              const timestamp = Math.floor(Date.now() / 1000);

              // Save to blob if action=capture
              if (action === 'capture') {
                const blobPath = `webcams/${id}/${timestamp}.jpg`;
                const blob = await put(blobPath, processedImage, {
                  access: 'public',
                  contentType: 'image/jpeg',
                });
                return res.status(200).json({
                  success: true,
                  id,
                  timestamp,
                  imageUrl: blob.url,
                  source: 'poster',
                  size: processedImage.length
                });
              }

              // Return image directly
              res.setHeader('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=120');
              res.setHeader('Content-Type', 'image/jpeg');
              res.setHeader('X-Image-Timestamp', timestamp.toString());
              res.setHeader('X-Source', 'poster');
              return res.status(200).send(processedImage);
            }
          }
        }
      } catch (e) {
        // Poster not available, continue
      }
    }

    // Step 1: Fetch the m3u8 playlist
    console.log(`Fetching playlist for ${id}: ${streamUrl}`);
    const playlistResponse = await fetch(streamUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        'Accept': '*/*',
        'Origin': 'https://www.viewsurf.com',
        'Referer': 'https://www.viewsurf.com/',
      }
    });

    if (!playlistResponse.ok) {
      console.log(`Playlist fetch failed: ${playlistResponse.status}`);
      return res.status(502).json({
        error: 'Failed to fetch stream playlist',
        status: playlistResponse.status
      });
    }

    let playlist = await playlistResponse.text();
    console.log(`Playlist size: ${playlist.length} bytes`);

    // Step 2: If master playlist, follow to first media playlist
    let lines = playlist.split('\n').filter(l => l.trim());
    let segmentUrls = lines.filter(l => l.endsWith('.ts') || l.includes('.ts?'));

    if (segmentUrls.length === 0) {
      // Check if this is a master playlist with sub-playlists
      const subPlaylists = lines.filter(l => l.endsWith('.m3u8') || l.includes('.m3u8?'));
      if (subPlaylists.length > 0) {
        let subUrl = subPlaylists[0];
        if (!subUrl.startsWith('http')) {
          const baseUrl = streamUrl.substring(0, streamUrl.lastIndexOf('/') + 1);
          subUrl = baseUrl + subUrl;
        }
        console.log(`Master playlist detected, following to: ${subUrl}`);
        const subResponse = await fetch(subUrl, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
            'Accept': '*/*',
            'Origin': 'https://www.viewsurf.com',
            'Referer': 'https://www.viewsurf.com/',
          }
        });
        if (subResponse.ok) {
          playlist = await subResponse.text();
          lines = playlist.split('\n').filter(l => l.trim());
          segmentUrls = lines.filter(l => l.endsWith('.ts') || l.includes('.ts?'));
          // Update streamUrl for relative segment URL resolution
          streamUrl = subUrl;
        }
      }
    }

    if (segmentUrls.length === 0) {
      console.log('No segments found in playlist');
      return res.status(404).json({ error: 'No video segments found in playlist' });
    }

    // Get the last segment (most recent)
    let segmentUrl = segmentUrls[segmentUrls.length - 1];

    // Make URL absolute if relative
    if (!segmentUrl.startsWith('http')) {
      const baseUrl = streamUrl.substring(0, streamUrl.lastIndexOf('/') + 1);
      segmentUrl = baseUrl + segmentUrl;
    }

    console.log(`Fetching segment: ${segmentUrl}`);

    // Step 3: Fetch the TS segment
    const segmentResponse = await fetch(segmentUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        'Accept': '*/*',
        'Origin': 'https://www.viewsurf.com',
        'Referer': 'https://www.viewsurf.com/',
      }
    });

    if (!segmentResponse.ok) {
      console.log(`Segment fetch failed: ${segmentResponse.status}`);
      return res.status(502).json({
        error: 'Failed to fetch video segment',
        status: segmentResponse.status
      });
    }

    const segmentBuffer = Buffer.from(await segmentResponse.arrayBuffer());
    console.log(`Segment size: ${segmentBuffer.length} bytes`);

    if (segmentBuffer.length < 1000) {
      return res.status(502).json({ error: 'Segment too small, likely invalid' });
    }

    // Step 4: Try to extract frame data from TS segment
    // Parse the TS to find video data
    const videoPackets = extractVideoData(segmentBuffer);
    console.log(`Found ${videoPackets.length} video packets in segment`);

    const timestamp = Math.floor(Date.now() / 1000);

    // Combine video packet payloads to look for JPEG/image data
    // Some streams embed thumbnail images
    const combinedPayload = Buffer.concat(videoPackets.map(p => p.payload));

    // Look for JPEG magic bytes (FFD8)
    let jpegStart = -1;
    let jpegEnd = -1;
    for (let i = 0; i < combinedPayload.length - 1; i++) {
      if (combinedPayload[i] === 0xff && combinedPayload[i + 1] === 0xd8) {
        jpegStart = i;
      }
      if (jpegStart >= 0 && combinedPayload[i] === 0xff && combinedPayload[i + 1] === 0xd9) {
        jpegEnd = i + 2;
        break;
      }
    }

    // If we found embedded JPEG data
    if (jpegStart >= 0 && jpegEnd > jpegStart) {
      const jpegBuffer = combinedPayload.slice(jpegStart, jpegEnd);
      console.log(`Found embedded JPEG: ${jpegBuffer.length} bytes`);

      try {
        const targetWidth = parseInt(width) || 1200;
        const targetQuality = parseInt(quality) || 80;

        const processedImage = await sharp(jpegBuffer)
          .resize(targetWidth, null, { withoutEnlargement: true })
          .jpeg({ quality: targetQuality, progressive: true })
          .toBuffer();

        if (action === 'capture') {
          const blobPath = `webcams/${id}/${timestamp}.jpg`;
          const blob = await put(blobPath, processedImage, {
            access: 'public',
            contentType: 'image/jpeg',
          });
          return res.status(200).json({
            success: true,
            id,
            timestamp,
            imageUrl: blob.url,
            source: 'embedded',
            size: processedImage.length
          });
        }

        res.setHeader('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=120');
        res.setHeader('Content-Type', 'image/jpeg');
        res.setHeader('X-Image-Timestamp', timestamp.toString());
        res.setHeader('X-Source', 'embedded');
        return res.status(200).send(processedImage);
      } catch (e) {
        console.log('Failed to process embedded JPEG:', e.message);
      }
    }

    // Fallback: Return stream info for client-side HLS playback
    // Client can use video.js, hls.js, or native HLS to display the stream
    res.setHeader('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=120');
    return res.status(200).json({
      id,
      streamUrl,
      hlsUrl: streamUrl,
      latestSegment: segmentUrl,
      segmentSize: segmentBuffer.length,
      timestamp,
      videoPackets: videoPackets.length,
      note: 'HLS stream available - use hls.js or native player for live view'
    });

  } catch (error) {
    console.error('Viewsurf stream error:', error);
    res.status(500).json({ error: 'Failed to process stream', message: error.message });
  }
}
