// Shared utility functions

/** Haversine distance in km */
export function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLon = (lon2 - lon1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

/** Wind speed (knots) → color */
export function getWindColor(knots: number): string {
  if (knots < 7) return '#B3EDFF'
  if (knots < 11) return '#54D9EB'
  if (knots < 17) return '#59E385'
  if (knots < 22) return '#F8E654'
  if (knots < 28) return '#FAAB3A'
  if (knots < 34) return '#F23842'
  if (knots < 41) return '#D433AB'
  if (knots < 48) return '#8C3EC8'
  return '#6440A0'
}

/** Wind speed (knots) → darker color for text on light backgrounds */
export function getWindColorDark(knots: number): string {
  if (knots < 7) return '#1A6B82'
  if (knots < 11) return '#14778A'
  if (knots < 17) return '#1E7438'
  if (knots < 22) return '#8A7508'
  if (knots < 28) return '#995E08'
  if (knots < 34) return '#A8161E'
  if (knots < 41) return '#8A1870'
  if (knots < 48) return '#5A2488'
  return '#3A2060'
}

/** Wave height (m) → color */
export function getWaveColor(hm0: number): string {
  if (hm0 < 0.5) return '#3b82f6'
  if (hm0 < 1.0) return '#22d3ee'
  if (hm0 < 1.5) return '#22c55e'
  if (hm0 < 2.0) return '#eab308'
  if (hm0 < 2.5) return '#f97316'
  return '#ef4444'
}

/** Degrees → French compass text */
export function degToCompassFR(degrees: number): string {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO']
  const index = Math.round(degrees / 45) % 8
  return directions[index]
}

/** Degrees → English compass text */
export function degToCompassEN(degrees: number): string {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
  const index = Math.round(degrees / 45) % 8
  return directions[index]
}

/** Format date for display (French locale) */
export function formatTimeFR(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
}

/** Format day name in French */
export function formatDayFR(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric' })
}
