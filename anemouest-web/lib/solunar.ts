import type { MoonPhaseData, SolunarPeriod, SolunarData, FishingScoreBreakdown, FishSpecies } from './types'

const KNOWN_NEW_MOON_JD = 2451550.1
const SYNODIC_MONTH = 29.53059

function toJulianDate(date: Date): number {
  return date.getTime() / 86400000 + 2440587.5
}

export function getMoonPhase(date: Date): MoonPhaseData {
  const jd = toJulianDate(date)
  const daysSinceNew = jd - KNOWN_NEW_MOON_JD
  const cycles = daysSinceNew / SYNODIC_MONTH
  const phase = cycles - Math.floor(cycles)

  const illumination = Math.round((1 - Math.cos(phase * 2 * Math.PI)) / 2 * 100)

  const names = [
    'Nouvelle lune', 'Premier croissant', 'Premier quartier', 'Gibbeuse croissante',
    'Pleine lune', 'Gibbeuse decroissante', 'Dernier quartier', 'Dernier croissant',
  ]
  const nameIndex = Math.round(phase * 8) % 8

  // Transit hour
  const transitHour = (12 + phase * 24) % 24
  // Approximate rise/set (~6h offset from transit)
  const riseHour = (transitHour - 6 + 24) % 24
  const setHour = (transitHour + 6) % 24

  return { phase, name: names[nameIndex], illumination, transitHour, riseHour, setHour }
}

export function getSolunarPeriods(date: Date): SolunarPeriod[] {
  const moon = getMoonPhase(date)
  const transit = moon.transitHour
  const periods: SolunarPeriod[] = []

  const makeDate = (hour: number) => {
    const d = new Date(date)
    d.setHours(Math.floor(hour), (hour % 1) * 60, 0, 0)
    return d
  }

  // Major 1: transit
  const m1s = makeDate(transit)
  periods.push({ start: m1s, end: new Date(m1s.getTime() + 2 * 3600000), type: 'major' })

  // Major 2: underfoot (+12h)
  const m2h = (transit + 12) % 24
  const m2s = makeDate(m2h)
  if (m2s.getDate() === date.getDate()) {
    periods.push({ start: m2s, end: new Date(m2s.getTime() + 2 * 3600000), type: 'major' })
  }

  // Minor 1: rise
  const riseS = makeDate(moon.riseHour)
  if (riseS.getDate() === date.getDate()) {
    periods.push({ start: riseS, end: new Date(riseS.getTime() + 3600000), type: 'minor' })
  }

  // Minor 2: set
  const setS = makeDate(moon.setHour)
  if (setS.getDate() === date.getDate()) {
    periods.push({ start: setS, end: new Date(setS.getTime() + 3600000), type: 'minor' })
  }

  return periods.sort((a, b) => a.start.getTime() - b.start.getTime())
}

/** 5-factor fishing score matching iOS */
export function getFishingScoreBreakdown(
  date: Date,
  tideCoeff?: number,
  windKnots?: number,
  waveHeight?: number,
  pressure?: number,
): FishingScoreBreakdown {
  const periods = getSolunarPeriods(date)
  const now = date.getTime()

  // Solunar: 25 pts
  let solunar = 0
  for (const p of periods) {
    const mid = (p.start.getTime() + p.end.getTime()) / 2
    const distH = Math.abs(now - mid) / 3600000
    if (distH < 1) { solunar = p.type === 'major' ? 25 : 18; break }
    else if (distH < 2) solunar = Math.max(solunar, p.type === 'major' ? 15 : 10)
    else if (distH < 3) solunar = Math.max(solunar, 5)
  }

  // Tide: 20 pts
  let tide = 10
  if (tideCoeff !== undefined) {
    tide = Math.round(Math.min(20, Math.max(0, (tideCoeff - 20) / 100 * 20)))
  }

  // Wind: 20 pts (light wind best)
  let wind = 12
  if (windKnots !== undefined) {
    if (windKnots < 8) wind = 20
    else if (windKnots < 12) wind = 17
    else if (windKnots < 16) wind = 13
    else if (windKnots < 20) wind = 9
    else if (windKnots < 25) wind = 5
    else if (windKnots < 30) wind = 2
    else wind = 0
  }

  // Sea conditions: 20 pts (calm best)
  let sea = 12
  if (waveHeight !== undefined) {
    if (waveHeight < 0.3) sea = 20
    else if (waveHeight < 0.6) sea = 17
    else if (waveHeight < 1.0) sea = 14
    else if (waveHeight < 1.5) sea = 10
    else if (waveHeight < 2.0) sea = 6
    else if (waveHeight < 2.5) sea = 3
    else sea = 0
  }

  // Pressure: 15 pts (stable ~1013-1020 best, dropping pressure good too)
  let pressureScore = 8
  if (pressure !== undefined) {
    if (pressure >= 1010 && pressure <= 1025) pressureScore = 15
    else if (pressure >= 1000 && pressure <= 1030) pressureScore = 11
    else if (pressure >= 990) pressureScore = 6
    else pressureScore = 2
  }

  const total = Math.min(100, solunar + tide + wind + sea + pressureScore)
  return { solunar, tide, wind, sea, pressure: pressureScore, total }
}

export function getSolunarData(
  date: Date,
  tideCoeff?: number,
  windKnots?: number,
  waveHeight?: number,
  pressure?: number,
): SolunarData {
  const breakdown = getFishingScoreBreakdown(date, tideCoeff, windKnots, waveHeight, pressure)
  return {
    moonPhase: getMoonPhase(date),
    periods: getSolunarPeriods(date),
    fishingScore: breakdown.total,
    breakdown,
  }
}

// ===== Species Guide (Bretagne / Atlantique focus) =====

export const FISH_SPECIES: FishSpecies[] = [
  { name: 'Bar (Loup)', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [4,5,6,9,10], technique: 'Leurre, vif, surf casting', minimumSize: '42 cm', region: 'Atlantique' },
  { name: 'Maquereau', months: [4,5,6,7,8,9,10], peakMonths: [6,7,8], technique: 'Mitraillette, plume', minimumSize: '20 cm', region: 'Atlantique' },
  { name: 'Dorade royale', months: [5,6,7,8,9,10], peakMonths: [7,8,9], technique: 'Appât, surf casting', minimumSize: '23 cm', region: 'Atlantique' },
  { name: 'Lieu jaune', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [3,4,5,10,11], technique: 'Leurre souple, jig', minimumSize: '30 cm', region: 'Atlantique' },
  { name: 'Congre', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [6,7,8,9], technique: 'Fond, appât', region: 'Atlantique' },
  { name: 'Daurade grise (Griset)', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [10,11,12,1,2], technique: 'Fond, ver', minimumSize: '23 cm', region: 'Atlantique' },
  { name: 'Sole', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Surf casting, ver', minimumSize: '24 cm', region: 'Atlantique' },
  { name: 'Turbot', months: [3,4,5,6,7,8,9], peakMonths: [5,6,7], technique: 'Lancer, vif', minimumSize: '30 cm', region: 'Atlantique' },
  { name: 'Vieille', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [5,6,7,8], technique: 'Fond, crabe', region: 'Bretagne' },
  { name: 'Chinchard', months: [5,6,7,8,9,10], peakMonths: [7,8,9], technique: 'Mitraillette, sabiki', minimumSize: '15 cm', region: 'Atlantique' },
  { name: 'Orphie', months: [4,5,6,7], peakMonths: [5,6], technique: 'Flotteur, leurre', region: 'Atlantique' },
  { name: 'Sar', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Flotteur, appât', minimumSize: '25 cm', region: 'Méditerranée' },
  { name: 'Mulet', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [6,7,8,9], technique: 'Pain, flotteur', region: 'Atlantique' },
  { name: 'Éperlan', months: [1,2,3,4,5,10,11,12], peakMonths: [11,12,1,2], technique: 'Ligne, mitraillette', region: 'Atlantique' },
  { name: 'Tacaud', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [10,11,12,1], technique: 'Fond, ver', region: 'Atlantique' },
  { name: 'Merlan', months: [9,10,11,12,1,2,3], peakMonths: [11,12,1], technique: 'Fond, ver, leurre', minimumSize: '27 cm', region: 'Atlantique' },
  { name: 'Raie', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [4,5,6], technique: 'Fond, appât', region: 'Atlantique' },
  { name: 'Plie (Carrelet)', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Surf casting, ver', minimumSize: '27 cm', region: 'Atlantique' },
  { name: 'Seiche', months: [3,4,5,6,7,8,9,10], peakMonths: [4,5,6], technique: 'Turlutte, leurre', region: 'Atlantique' },
  { name: 'Calamar', months: [9,10,11,12,1,2], peakMonths: [10,11,12], technique: 'Turlutte, eging', region: 'Atlantique' },
  { name: 'Poulpe', months: [6,7,8,9,10], peakMonths: [7,8,9], technique: 'Turlutte, appât', region: 'Atlantique' },
  { name: 'Homard', months: [4,5,6,7,8,9], peakMonths: [6,7,8], technique: 'Casier', minimumSize: '8.7 cm (céphalothorax)', region: 'Bretagne' },
  { name: 'Araignée de mer', months: [4,5,6,7,8,9], peakMonths: [5,6,7], technique: 'Casier, plongée', minimumSize: '12 cm', region: 'Bretagne' },
  { name: 'Tourteau', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [5,6,7,8], technique: 'Casier', minimumSize: '14 cm', region: 'Atlantique' },
  { name: 'Crevette grise', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Haveneau, pousseux', region: 'Atlantique' },
  { name: 'Bouquet', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [8,9,10], technique: 'Épuisette, casier', region: 'Atlantique' },
  { name: 'Palourde', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [12,1,2,3], technique: 'Grattage, pêche à pied', minimumSize: '4 cm', region: 'Atlantique' },
  { name: 'Coque', months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Pêche à pied', minimumSize: '3 cm', region: 'Atlantique' },
  { name: 'Moule', months: [6,7,8,9,10,11,12], peakMonths: [9,10,11], technique: 'Cueillette, pêche à pied', minimumSize: '4 cm', region: 'Atlantique' },
  { name: 'Ormeau', months: [9,10,11,12,1,2,3], peakMonths: [12,1,2], technique: 'Plongée, pêche à pied', minimumSize: '9 cm', region: 'Bretagne' },
]
