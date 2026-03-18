//
//  SolunarService.swift
//  AnemOuest
//
//  Calculs astronomiques pour tables solunaires (peche)
//  Algorithmes simplifies bases sur Jean Meeus (Astronomical Algorithms)
//

import Foundation

// MARK: - Models

struct SolunarData {
    let date: Date
    let moonPhase: Double              // 0..1 (0 = nouvelle lune, 0.5 = pleine lune)
    let moonPhaseName: String
    let moonIllumination: Double       // 0..100%
    let moonRise: Date?
    let moonSet: Date?
    let moonTransit: Date?             // Passage au meridien
    let moonUnderfoot: Date?           // Anti-meridien (~12h apres transit)
    let sunRise: Date
    let sunSet: Date
    let majorPeriods: [SolunarPeriod]  // ~2h autour transit/underfoot
    let minorPeriods: [SolunarPeriod]  // ~1h autour lever/coucher lune
    let rating: Int                    // 1-5 etoiles
}

struct SolunarPeriod: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let type: PeriodType
    let peak: Date

    enum PeriodType {
        case major
        case minor

        var label: String {
            switch self {
            case .major: return "Majeure"
            case .minor: return "Mineure"
            }
        }

        var icon: String {
            switch self {
            case .major: return "star.fill"
            case .minor: return "star.leadinghalf.filled"
            }
        }
    }
}

// MARK: - Solunar Service

final class SolunarService {
    static let shared = SolunarService()
    private init() {}

    // Known new moon reference: January 29, 2025 12:36 UTC
    private let referenceNewMoon: TimeInterval = 1738151760 // 2025-01-29T12:36:00Z
    private let synodicMonth: Double = 29.53059 // days

    // MARK: - Public API

    func calculate(for date: Date, latitude: Double, longitude: Double) -> SolunarData {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date

        // Moon phase
        let phase = moonPhase(for: noon)
        let phaseName = moonPhaseName(phase)
        let illumination = moonIllumination(phase)

        // Sun rise/set
        let (sunRise, sunSet) = sunRiseSet(date: date, latitude: latitude, longitude: longitude)

        // Moon rise/set (approximation)
        let (moonRise, moonSet) = moonRiseSet(date: date, phase: phase, latitude: latitude, longitude: longitude)

        // Moon transit and underfoot
        let moonTransit = self.moonTransit(date: date, moonRise: moonRise, moonSet: moonSet)
        let moonUnderfoot: Date?
        if let transit = moonTransit {
            moonUnderfoot = transit.addingTimeInterval(12.37 * 3600) // ~12h22m later
        } else {
            moonUnderfoot = nil
        }

        // Build solunar periods
        var majorPeriods: [SolunarPeriod] = []
        var minorPeriods: [SolunarPeriod] = []

        // Major periods: ~1h before to ~1h after transit and underfoot
        let majorDuration: TimeInterval = 60 * 60 // 1h each side
        if let transit = moonTransit {
            majorPeriods.append(SolunarPeriod(
                start: transit.addingTimeInterval(-majorDuration),
                end: transit.addingTimeInterval(majorDuration),
                type: .major,
                peak: transit
            ))
        }
        if let underfoot = moonUnderfoot {
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = dayStart.addingTimeInterval(24 * 3600)
            // Only include if within the same day
            if underfoot >= dayStart && underfoot <= dayEnd {
                majorPeriods.append(SolunarPeriod(
                    start: underfoot.addingTimeInterval(-majorDuration),
                    end: underfoot.addingTimeInterval(majorDuration),
                    type: .major,
                    peak: underfoot
                ))
            }
        }

        // Minor periods: ~30min before to ~30min after moon rise/set
        let minorDuration: TimeInterval = 30 * 60 // 30min each side
        if let rise = moonRise {
            minorPeriods.append(SolunarPeriod(
                start: rise.addingTimeInterval(-minorDuration),
                end: rise.addingTimeInterval(minorDuration),
                type: .minor,
                peak: rise
            ))
        }
        if let set = moonSet {
            minorPeriods.append(SolunarPeriod(
                start: set.addingTimeInterval(-minorDuration),
                end: set.addingTimeInterval(minorDuration),
                type: .minor,
                peak: set
            ))
        }

        // Rating
        let rating = calculateRating(
            phase: phase,
            majorPeriods: majorPeriods,
            minorPeriods: minorPeriods,
            sunRise: sunRise,
            sunSet: sunSet
        )

        return SolunarData(
            date: date,
            moonPhase: phase,
            moonPhaseName: phaseName,
            moonIllumination: illumination,
            moonRise: moonRise,
            moonSet: moonSet,
            moonTransit: moonTransit,
            moonUnderfoot: moonUnderfoot,
            sunRise: sunRise,
            sunSet: sunSet,
            majorPeriods: majorPeriods,
            minorPeriods: minorPeriods,
            rating: rating
        )
    }

    /// Calculate solunar data for multiple days
    func calculate(days: Int, from startDate: Date, latitude: Double, longitude: Double) -> [SolunarData] {
        let calendar = Calendar.current
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            return calculate(for: date, latitude: latitude, longitude: longitude)
        }
    }

    // MARK: - Moon Phase

    func moonPhase(for date: Date) -> Double {
        let daysSinceRef = (date.timeIntervalSince1970 - referenceNewMoon) / 86400.0
        let phase = daysSinceRef.truncatingRemainder(dividingBy: synodicMonth) / synodicMonth
        return phase < 0 ? phase + 1.0 : phase
    }

    func moonPhaseName(_ phase: Double) -> String {
        switch phase {
        case 0..<0.025, 0.975...1.0:
            return "Nouvelle lune"
        case 0.025..<0.225:
            return "Premier croissant"
        case 0.225..<0.275:
            return "Premier quartier"
        case 0.275..<0.475:
            return "Gibbeuse croissante"
        case 0.475..<0.525:
            return "Pleine lune"
        case 0.525..<0.725:
            return "Gibbeuse decroissante"
        case 0.725..<0.775:
            return "Dernier quartier"
        case 0.775..<0.975:
            return "Dernier croissant"
        default:
            return "Nouvelle lune"
        }
    }

    func moonPhaseIcon(_ phase: Double) -> String {
        switch phase {
        case 0..<0.025, 0.975...1.0:
            return "moonphase.new.moon"
        case 0.025..<0.225:
            return "moonphase.waxing.crescent"
        case 0.225..<0.275:
            return "moonphase.first.quarter"
        case 0.275..<0.475:
            return "moonphase.waxing.gibbous"
        case 0.475..<0.525:
            return "moonphase.full.moon"
        case 0.525..<0.725:
            return "moonphase.waning.gibbous"
        case 0.725..<0.775:
            return "moonphase.last.quarter"
        case 0.775..<0.975:
            return "moonphase.waning.crescent"
        default:
            return "moonphase.new.moon"
        }
    }

    func moonIllumination(_ phase: Double) -> Double {
        // Illumination follows a cosine curve: 0% at new, 100% at full
        return (1.0 - cos(phase * 2.0 * .pi)) / 2.0 * 100.0
    }

    // MARK: - Sun Rise/Set (simplified algorithm)

    private func sunRiseSet(date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date) {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Solar declination (degrees)
        let declination = 23.45 * sin(toRadians(360.0 / 365.0 * (dayOfYear - 81)))
        let decRad = toRadians(declination)
        let latRad = toRadians(latitude)

        // Hour angle at sunrise/sunset
        let cosHA = -tan(latRad) * tan(decRad)
        let hourAngle: Double
        if cosHA < -1 { hourAngle = 180.0 } // Midnight sun
        else if cosHA > 1 { hourAngle = 0.0 } // Polar night
        else { hourAngle = toDegrees(acos(cosHA)) }

        // Solar noon (approximate using longitude)
        let solarNoonHours = 12.0 - longitude / 15.0

        // Time zone offset for Europe/Paris
        let tz = TimeZone(identifier: "Europe/Paris")!
        let tzOffsetHours = Double(tz.secondsFromGMT(for: date)) / 3600.0

        let riseHours = solarNoonHours - hourAngle / 15.0 + tzOffsetHours
        let setHours = solarNoonHours + hourAngle / 15.0 + tzOffsetHours

        let dayStart = calendar.startOfDay(for: date)
        let rise = dayStart.addingTimeInterval(riseHours * 3600)
        let set = dayStart.addingTimeInterval(setHours * 3600)

        return (rise, set)
    }

    // MARK: - Moon Rise/Set (approximation)

    private func moonRiseSet(date: Date, phase: Double, latitude: Double, longitude: Double) -> (rise: Date?, set: Date?) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        // Moon rise time shifts ~50 min later each day
        // At new moon: rises/sets ~same time as sun
        // At full moon: rises at sunset, sets at sunrise
        // At first quarter: rises at noon, sets at midnight
        // At last quarter: rises at midnight, sets at noon

        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let declination = 23.45 * sin(toRadians(360.0 / 365.0 * (dayOfYear - 81)))

        // Base sun noon
        let tz = TimeZone(identifier: "Europe/Paris")!
        let tzOffsetHours = Double(tz.secondsFromGMT(for: date)) / 3600.0
        let solarNoonHours = 12.0 - longitude / 15.0 + tzOffsetHours

        // Moon rise/set offset from sun based on phase
        // phase 0 (new) = offset 0h, phase 0.5 (full) = offset 12h
        let phaseOffset = phase * 24.0 // hours of offset

        // Day length factor from latitude
        let latRad = toRadians(latitude)
        let decRad = toRadians(declination)
        let cosHA = -tan(latRad) * tan(decRad)
        let hourAngle: Double
        if cosHA < -1 { hourAngle = 180.0 }
        else if cosHA > 1 { hourAngle = 0.0 }
        else { hourAngle = toDegrees(acos(cosHA)) }

        let sunRiseHours = solarNoonHours - hourAngle / 15.0
        let dayLengthHours = (hourAngle / 15.0) * 2.0

        // Moon rises approximately: sunrise + phaseOffset
        var moonRiseHours = sunRiseHours + phaseOffset
        // Moon is above horizon for roughly 12.5 hours
        let moonUpDuration = 12.5 + (dayLengthHours - 12.0) * 0.3 // slight latitude correction

        // Normalize to 0-48h range
        while moonRiseHours > 24 { moonRiseHours -= 24.0 }
        while moonRiseHours < 0 { moonRiseHours += 24.0 }

        var moonSetHours = moonRiseHours + moonUpDuration
        if moonSetHours > 24 { moonSetHours -= 24.0 }

        // Build dates - only return if within the day
        let rise: Date?
        if moonRiseHours >= 0 && moonRiseHours <= 24 {
            rise = dayStart.addingTimeInterval(moonRiseHours * 3600)
        } else {
            rise = nil
        }

        let set: Date?
        if moonSetHours >= 0 && moonSetHours <= 24 {
            set = dayStart.addingTimeInterval(moonSetHours * 3600)
        } else {
            set = nil
        }

        return (rise, set)
    }

    // MARK: - Moon Transit

    private func moonTransit(date: Date, moonRise: Date?, moonSet: Date?) -> Date? {
        guard let rise = moonRise else { return nil }

        if let set = moonSet, set > rise {
            // Transit is midpoint between rise and set
            return rise.addingTimeInterval(set.timeIntervalSince(rise) / 2.0)
        } else {
            // Moon set is next day, estimate transit ~6.25h after rise
            return rise.addingTimeInterval(6.25 * 3600)
        }
    }

    // MARK: - Rating

    private func calculateRating(
        phase: Double,
        majorPeriods: [SolunarPeriod],
        minorPeriods: [SolunarPeriod],
        sunRise: Date,
        sunSet: Date
    ) -> Int {
        // Base rating from moon phase
        var rating: Int
        let phaseDistance = min(phase, 1.0 - phase) // distance to new moon
        let fullDistance = abs(phase - 0.5)          // distance to full moon

        if phaseDistance < 0.05 {
            rating = 5 // Nouvelle lune
        } else if fullDistance < 0.05 {
            rating = 4 // Pleine lune
        } else if abs(phase - 0.25) < 0.05 || abs(phase - 0.75) < 0.05 {
            rating = 3 // Quartiers
        } else {
            rating = 2 // Croissants
        }

        // Bonus if a major period falls during daylight
        let hasDaylightMajor = majorPeriods.contains { period in
            period.peak >= sunRise && period.peak <= sunSet
        }
        if hasDaylightMajor && rating < 5 {
            rating += 1
        }

        return min(rating, 5)
    }

    // MARK: - Helpers

    private func toRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private func toDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
