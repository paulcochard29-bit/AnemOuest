// Admin page: View all Netatmo stations on a map + table
// GET /api/admin/netatmo

// Always use the public URL so the browser can reach it
const API_BASE = 'https://api.levent.live';

export default async function handler(req, res) {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache');

  const html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Admin - Netatmo Stations</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; }
  .header { padding: 16px 24px; background: #1e293b; border-bottom: 1px solid #334155; display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
  .header h1 { font-size: 20px; font-weight: 600; }
  .stats { display: flex; gap: 12px; flex-wrap: wrap; }
  .stat { background: #334155; padding: 6px 14px; border-radius: 8px; font-size: 13px; }
  .stat b { color: #60a5fa; }
  .controls { display: flex; gap: 8px; margin-left: auto; align-items: center; }
  .controls input { background: #1e293b; border: 1px solid #475569; color: #e2e8f0; padding: 6px 12px; border-radius: 6px; font-size: 13px; width: 220px; }
  .controls select { background: #1e293b; border: 1px solid #475569; color: #e2e8f0; padding: 6px 10px; border-radius: 6px; font-size: 13px; }
  .controls button { background: #3b82f6; color: white; border: none; padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 13px; }
  .controls button:hover { background: #2563eb; }
  .main { display: flex; height: calc(100vh - 60px); }
  #map { flex: 1; min-width: 50%; }
  .table-wrap { flex: 1; overflow: auto; background: #0f172a; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  thead { position: sticky; top: 0; background: #1e293b; z-index: 2; }
  th { padding: 8px 10px; text-align: left; font-weight: 600; color: #94a3b8; cursor: pointer; user-select: none; white-space: nowrap; }
  th:hover { color: #e2e8f0; }
  th.sorted { color: #60a5fa; }
  td { padding: 6px 10px; border-bottom: 1px solid #1e293b; white-space: nowrap; }
  tr:hover td { background: #1e293b; }
  .online { color: #34d399; }
  .offline { color: #f87171; }
  .wind-pill { display: inline-block; padding: 2px 8px; border-radius: 10px; font-weight: 600; font-size: 11px; }
  .clickable { cursor: pointer; color: #60a5fa; }
  .clickable:hover { text-decoration: underline; }
  .loading { display: flex; align-items: center; justify-content: center; height: 100vh; font-size: 18px; color: #94a3b8; }
  @media (max-width: 900px) { .main { flex-direction: column; } #map { min-height: 50vh; } }
</style>
</head>
<body>
<div class="header">
  <h1>Netatmo Stations</h1>
  <div class="stats" id="stats"></div>
  <div class="controls">
    <input type="text" id="search" placeholder="Rechercher une station...">
    <select id="filterStatus">
      <option value="all">Toutes</option>
      <option value="online">Online</option>
      <option value="offline">Offline</option>
    </select>
    <button onclick="loadData()">Rafraîchir</button>
  </div>
</div>
<div class="main">
  <div id="map"></div>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th data-sort="name">Nom</th>
          <th data-sort="wind">Vent</th>
          <th data-sort="gust">Raf.</th>
          <th data-sort="direction">Dir</th>
          <th data-sort="temperature">T°</th>
          <th data-sort="isOnline">Status</th>
          <th data-sort="lat">Lat</th>
          <th data-sort="lon">Lon</th>
          <th data-sort="ts">MAJ</th>
        </tr>
      </thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
</div>
<script>
const API = '${API_BASE}/api/netatmo';
let allStations = [];
let markers = {};
let sortCol = 'wind';
let sortAsc = false;

// Wind color scale
function windColor(kts) {
  if (kts < 7) return '#B3EDFF';
  if (kts < 12) return '#7ED4F5';
  if (kts < 16) return '#4CAF50';
  if (kts < 21) return '#FFD600';
  if (kts < 27) return '#FF9800';
  if (kts < 33) return '#F44336';
  if (kts < 40) return '#D32F2F';
  if (kts < 48) return '#9C27B0';
  return '#6440A0';
}

function dirLabel(deg) {
  if (deg == null) return '-';
  const dirs = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'];
  return dirs[Math.round(deg / 22.5) % 16];
}

function timeAgo(ts) {
  if (!ts) return '-';
  const diff = Date.now() - new Date(ts).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 1) return 'now';
  if (min < 60) return min + 'min';
  const h = Math.floor(min / 60);
  if (h < 24) return h + 'h';
  return Math.floor(h / 24) + 'j';
}

// Map setup
const map = L.map('map').setView([46.8, 2.5], 6);
L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
  attribution: '&copy; OSM & Carto',
  maxZoom: 19,
}).addTo(map);

function createMarkerIcon(station) {
  const color = station.isOnline ? windColor(station.wind) : '#475569';
  const label = station.isOnline ? station.wind.toFixed(0) : '—';
  return L.divIcon({
    className: '',
    html: '<div style="background:' + color + ';color:#000;font-size:11px;font-weight:700;padding:2px 6px;border-radius:10px;white-space:nowrap;text-align:center;border:1px solid rgba(0,0,0,0.3);min-width:24px;">' + label + '</div>',
    iconSize: [30, 20],
    iconAnchor: [15, 10],
  });
}

function updateMap(stations) {
  // Remove old markers
  Object.values(markers).forEach(m => map.removeLayer(m));
  markers = {};

  stations.forEach(s => {
    const m = L.marker([s.lat, s.lon], { icon: createMarkerIcon(s) });
    m.bindPopup(
      '<b>' + s.name + '</b><br>' +
      'Vent: ' + s.wind + ' kts | Raf: ' + s.gust + ' kts<br>' +
      'Dir: ' + s.direction + '° (' + dirLabel(s.direction) + ')<br>' +
      (s.temperature != null ? 'Temp: ' + s.temperature + '°C<br>' : '') +
      'Status: ' + (s.isOnline ? '<span class="online">Online</span>' : '<span class="offline">Offline</span>') + '<br>' +
      'MAJ: ' + (s.ts || '-') + '<br>' +
      '<small>ID: ' + s.id + '</small>'
    );
    m.addTo(map);
    markers[s.id] = m;
  });
}

function updateTable(stations) {
  const tbody = document.getElementById('tbody');
  tbody.innerHTML = stations.map(s => {
    const color = s.isOnline ? windColor(s.wind) : '#475569';
    return '<tr onclick="flyTo(\\'' + s.id + '\\')">' +
      '<td class="clickable">' + s.name + '</td>' +
      '<td><span class="wind-pill" style="background:' + color + ';color:#000">' + s.wind.toFixed(1) + '</span></td>' +
      '<td>' + s.gust.toFixed(1) + '</td>' +
      '<td>' + dirLabel(s.direction) + '</td>' +
      '<td>' + (s.temperature != null ? s.temperature.toFixed(1) + '°' : '-') + '</td>' +
      '<td class="' + (s.isOnline ? 'online' : 'offline') + '">' + (s.isOnline ? 'Online' : 'Offline') + '</td>' +
      '<td>' + s.lat.toFixed(4) + '</td>' +
      '<td>' + s.lon.toFixed(4) + '</td>' +
      '<td>' + timeAgo(s.ts) + '</td>' +
      '</tr>';
  }).join('');
}

function flyTo(id) {
  const m = markers[id];
  if (m) {
    map.flyTo(m.getLatLng(), 14);
    m.openPopup();
  }
}

function getFiltered() {
  const search = document.getElementById('search').value.toLowerCase();
  const status = document.getElementById('filterStatus').value;

  let filtered = allStations;
  if (search) {
    filtered = filtered.filter(s => s.name.toLowerCase().includes(search) || s.id.includes(search));
  }
  if (status === 'online') filtered = filtered.filter(s => s.isOnline);
  if (status === 'offline') filtered = filtered.filter(s => !s.isOnline);

  // Sort
  filtered.sort((a, b) => {
    let va = a[sortCol], vb = b[sortCol];
    if (typeof va === 'string') { va = va.toLowerCase(); vb = (vb || '').toLowerCase(); }
    if (va == null) va = sortAsc ? Infinity : -Infinity;
    if (vb == null) vb = sortAsc ? Infinity : -Infinity;
    return sortAsc ? (va > vb ? 1 : -1) : (va < vb ? 1 : -1);
  });

  return filtered;
}

function refresh() {
  const filtered = getFiltered();
  updateMap(filtered);
  updateTable(filtered);

  const online = allStations.filter(s => s.isOnline).length;
  const offline = allStations.length - online;
  const avgWind = online > 0 ? (allStations.filter(s => s.isOnline).reduce((sum, s) => sum + s.wind, 0) / online).toFixed(1) : 0;

  document.getElementById('stats').innerHTML =
    '<div class="stat">Total: <b>' + allStations.length + '</b></div>' +
    '<div class="stat">Affichées: <b>' + filtered.length + '</b></div>' +
    '<div class="stat">Online: <b style="color:#34d399">' + online + '</b></div>' +
    '<div class="stat">Offline: <b style="color:#f87171">' + offline + '</b></div>' +
    '<div class="stat">Vent moy: <b>' + avgWind + ' kts</b></div>';
}

async function loadData() {
  document.getElementById('stats').innerHTML = '<div class="stat">Chargement... (peut prendre ~40s au premier appel)</div>';
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 120000); // 2 min timeout
    const r = await fetch(API + '?t=' + Date.now(), { signal: controller.signal });
    clearTimeout(timeout);
    const data = await r.json();
    allStations = data.stations || [];
    if (allStations.length === 0 && !data.cached) {
      // Stale empty cache — retry after delay
      document.getElementById('stats').innerHTML = '<div class="stat">Cache vide, nouvelle tentative dans 5s...</div>';
      setTimeout(loadData, 5000);
      return;
    }
    refresh();
  } catch(e) {
    const msg = e.name === 'AbortError' ? 'Timeout (2 min). Réessayez.' : e.message;
    document.getElementById('stats').innerHTML = '<div class="stat" style="color:#f87171">Erreur: ' + msg + ' <button onclick="loadData()" style="margin-left:8px;background:#3b82f6;color:white;border:none;padding:4px 10px;border-radius:4px;cursor:pointer">Réessayer</button></div>';
  }
}

// Sort headers
document.querySelectorAll('th[data-sort]').forEach(th => {
  th.addEventListener('click', () => {
    const col = th.dataset.sort;
    if (sortCol === col) { sortAsc = !sortAsc; } else { sortCol = col; sortAsc = false; }
    document.querySelectorAll('th').forEach(t => t.classList.remove('sorted'));
    th.classList.add('sorted');
    refresh();
  });
});

// Search & filter
document.getElementById('search').addEventListener('input', refresh);
document.getElementById('filterStatus').addEventListener('change', refresh);

// Init
loadData();
</script>
</body>
</html>`;

  return res.send(html);
}
