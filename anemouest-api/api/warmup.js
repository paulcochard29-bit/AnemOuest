// Warmup endpoint to prevent cold starts on all API functions
// Called by cron every 3 minutes to keep functions hot

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const startTime = Date.now();
  const results = {};

  const baseUrl = 'http://localhost:3001';

  // Data endpoints (wind stations) — most critical for app startup
  const dataEndpoints = [
    { name: 'pioupiou', url: '/api/pioupiou' },
    { name: 'gowind', url: '/api/gowind' },
    { name: 'stations', url: '/api/stations' },
    { name: 'meteofrance', url: '/api/meteofrance' },
    { name: 'windcornouaille', url: '/api/windcornouaille' },
    { name: 'diabox', url: '/api/diabox' },
    { name: 'candhis', url: '/api/candhis' },
  ];

  // Image proxy endpoints
  const imageEndpoints = [
    { name: 'skaping', url: '/api/skaping?path=concarneau/panoramique&thumb=true&quality=10&width=100' },
    { name: 'viewsurf', url: '/api/viewsurf?id=17598&thumb=true&quality=10&width=100' },
    { name: 'vision', url: '/api/vision?url=https://www.vision-environnement.com/visio3/visio.php?source=8020&thumb=true&quality=10&width=100' },
  ];

  const allEndpoints = [...dataEndpoints, ...imageEndpoints];

  await Promise.allSettled(
    allEndpoints.map(async ({ name, url }) => {
      const start = Date.now();
      try {
        const response = await fetch(`${baseUrl}${url}`, {
          signal: AbortSignal.timeout(10000),
        });
        results[name] = {
          status: response.status,
          time: Date.now() - start,
          ok: response.ok,
        };
      } catch (error) {
        results[name] = {
          status: 'error',
          time: Date.now() - start,
          error: error.message,
        };
      }
    })
  );

  const totalTime = Date.now() - startTime;

  res.status(200).json({
    message: 'Warmup complete',
    totalTime,
    results,
    timestamp: new Date().toISOString(),
  });
}
