import type { TideEvent, TideChartPoint } from './types'

/** Coefficient color and description */
export function getCoeffColor(coeff: number): string {
  if (coeff < 45) return '#3b82f6'  // Mortes-eaux (blue)
  if (coeff < 70) return '#22c55e'  // Moyen (green)
  if (coeff < 90) return '#f97316'  // Fort (orange)
  return '#ef4444'                   // Vives-eaux (red)
}

export function getCoeffLabel(coeff: number): string {
  if (coeff < 45) return 'Mortes-eaux'
  if (coeff < 70) return 'Moyen'
  if (coeff < 90) return 'Fort'
  return 'Vives-eaux'
}

/** Interpolate tide chart points between events using cosine */
export function interpolateTideCurve(events: TideEvent[], numPoints: number = 96): TideChartPoint[] {
  if (events.length < 2) return []

  const sorted = [...events].sort((a, b) => new Date(a.time).getTime() - new Date(b.time).getTime())
  const points: TideChartPoint[] = []

  for (let seg = 0; seg < sorted.length - 1; seg++) {
    const ev1 = sorted[seg]
    const ev2 = sorted[seg + 1]
    const t1 = new Date(ev1.time).getTime()
    const t2 = new Date(ev2.time).getTime()
    const h1 = ev1.height
    const h2 = ev2.height

    const segPoints = Math.max(4, Math.round(numPoints / Math.max(1, sorted.length - 1)))

    for (let i = 0; i < segPoints; i++) {
      const frac = i / segPoints
      const t = t1 + frac * (t2 - t1)
      // Cosine interpolation (smooth sinusoidal curve)
      const cosFrac = (1 - Math.cos(frac * Math.PI)) / 2
      const h = h1 + cosFrac * (h2 - h1)
      points.push({ time: t, height: h })
    }
  }

  // Add last point
  const last = sorted[sorted.length - 1]
  points.push({ time: new Date(last.time).getTime(), height: last.height })

  return points
}

/** Get current tide state (rising/falling/high/low) */
export function getTideState(events: TideEvent[]): { state: string; progress: number } {
  const now = Date.now()
  const sorted = [...events].sort((a, b) => new Date(a.time).getTime() - new Date(b.time).getTime())

  for (let i = 0; i < sorted.length - 1; i++) {
    const t1 = new Date(sorted[i].time).getTime()
    const t2 = new Date(sorted[i + 1].time).getTime()
    if (now >= t1 && now <= t2) {
      const progress = (now - t1) / (t2 - t1)
      const rising = sorted[i].type === 'BM' || sorted[i].type === 'low'
      return { state: rising ? 'Montante' : 'Descendante', progress }
    }
  }

  return { state: '', progress: 0 }
}
