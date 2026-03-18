//
//  FishingService.swift
//  AnemOuest
//
//  Score composite de conditions de pêche
//

import SwiftUI

// MARK: - Models

struct FishingConditions {
    let score: Int              // 0-100
    let solunarScore: Int       // /25
    let tideScore: Int          // /20
    let windScore: Int          // /20
    let seaScore: Int           // /20
    let pressureScore: Int      // /15
    let details: [String]
    let bestWindows: [FishingWindow]

    var label: String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Bon"
        case 40..<60: return "Moyen"
        case 20..<40: return "Difficile"
        default: return "Défavorable"
        }
    }

    var color: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .orange
        case 20..<40: return .red
        default: return .gray
        }
    }
}

struct FishingWindow: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let reason: String
    let quality: WindowQuality

    enum WindowQuality {
        case excellent, good, moderate

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .cyan
            case .moderate: return .orange
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "star.fill"
            case .good: return "star.leadinghalf.filled"
            case .moderate: return "circle.fill"
            }
        }
    }
}

// MARK: - Seasonal Species

struct SeasonalSpecies: Identifiable {
    let id = UUID()
    let name: String
    let months: Set<Int>           // Mois où l'espèce est pêchable
    let peakMonths: Set<Int>       // Mois de meilleure pêche
    let technique: String
    let icon: String
    let minimumSize: String?       // Taille minimale réglementaire
    let closedMonths: Set<Int>     // Mois où la pêche est interdite
    let regulation: String?        // Note réglementaire (quota, limite/jour)

    init(name: String, months: Set<Int>, peakMonths: Set<Int>, technique: String, icon: String, minimumSize: String?, closedMonths: Set<Int> = [], regulation: String? = nil) {
        self.name = name
        self.months = months
        self.peakMonths = peakMonths
        self.technique = technique
        self.icon = icon
        self.minimumSize = minimumSize
        self.closedMonths = closedMonths
        self.regulation = regulation
    }

    var isInSeason: Bool {
        let month = Calendar.current.component(.month, from: Date())
        return months.contains(month)
    }

    var isInPeak: Bool {
        let month = Calendar.current.component(.month, from: Date())
        return peakMonths.contains(month)
    }

    /// Est-ce que la pêche de cette espèce est autorisée ce mois-ci ?
    var isFishingAllowed: Bool {
        let month = Calendar.current.component(.month, from: Date())
        return !closedMonths.contains(month)
    }
}

enum FishingRegion: String, CaseIterable, Identifiable {
    case manche = "Manche / Mer du Nord"
    case atlantiqueNord = "Atlantique Nord (Bretagne)"
    case atlantiqueSud = "Atlantique Sud"
    case mediterranee = "Méditerranée"

    var id: String { rawValue }

    var species: [SeasonalSpecies] {
        switch self {

        // MARK: Manche / Mer du Nord (Dunkerque → Mont-Saint-Michel)
        case .manche:
            return [
                // Poissons
                SeasonalSpecies(name: "Bar", months: [3,4,5,6,7,8,9,10,11], peakMonths: [5,6,7,8,9,10], technique: "Lancer, surf-casting", icon: "fish.fill", minimumSize: "42 cm", closedMonths: [1,2], regulation: "1/jour max"),
                SeasonalSpecies(name: "Lieu jaune", months: [3,4,5,6,7,8,9,10], peakMonths: [5,6,7,8], technique: "Lancer, traîne", icon: "fish.fill", minimumSize: "30 cm"),
                SeasonalSpecies(name: "Lieu noir", months: [3,4,5,6,7,8,9,10,11], peakMonths: [4,5,6,7,8,9], technique: "Lancer, fond", icon: "fish.fill", minimumSize: "35 cm"),
                SeasonalSpecies(name: "Cabillaud", months: [10,11,12,1,2,3], peakMonths: [11,12,1,2], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "35 cm"),
                SeasonalSpecies(name: "Maquereau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Mitraillette, plume", icon: "fish.fill", minimumSize: "20 cm"),
                SeasonalSpecies(name: "Merlan", months: [10,11,12,1,2,3], peakMonths: [11,12,1,2], technique: "Fond", icon: "fish.fill", minimumSize: "27 cm"),
                SeasonalSpecies(name: "Tacaud", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [3,4,5,9,10,11], technique: "Fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Sole", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "24 cm"),
                SeasonalSpecies(name: "Plie (Carrelet)", months: [3,4,5,6,7,8,9,10,11], peakMonths: [4,5,6,9,10], technique: "Surf-casting, fond", icon: "fish.fill", minimumSize: "27 cm"),
                SeasonalSpecies(name: "Dorade grise", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12,1], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "23 cm"),
                // Céphalopodes
                SeasonalSpecies(name: "Seiche", months: [3,4,5,6,9,10], peakMonths: [4,5,6], technique: "Turlutte, fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Encornet", months: [9,10,11,12,1], peakMonths: [10,11,12], technique: "Turlutte", icon: "fish.fill", minimumSize: nil),
                // Crustaces
                SeasonalSpecies(name: "Tourteau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Pêche à pied, casier", icon: "tortoise.fill", minimumSize: "14 cm"),
                SeasonalSpecies(name: "Homard", months: [4,5,6,7,8], peakMonths: [5,6,7], technique: "Casier", icon: "tortoise.fill", minimumSize: "8.7 cm (céphalothorax)", regulation: "5 max/sortie"),
                SeasonalSpecies(name: "Étrille", months: [4,5,6,7,8,9,10], peakMonths: [5,6,7,8], technique: "Pêche à pied", icon: "tortoise.fill", minimumSize: "6.5 cm"),
                SeasonalSpecies(name: "Crevette bouquet", months: [5,6,7,8,9,10], peakMonths: [7,8,9], technique: "Haveneau, épuisette", icon: "tortoise.fill", minimumSize: "5 cm"),
                // Coquillages
                SeasonalSpecies(name: "Moule", months: [6,7,8,9,10,11,12,1,2], peakMonths: [7,8,9,10], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm", regulation: "5 kg max/pers"),
                SeasonalSpecies(name: "Coque", months: [9,10,11,12,1,2,3,4,5], peakMonths: [10,11,12,1,2], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "3 cm"),
            ]

        // MARK: Atlantique Nord (Bretagne)
        case .atlantiqueNord:
            return [
                // Poissons
                SeasonalSpecies(name: "Bar", months: [3,4,5,6,7,8,9,10,11], peakMonths: [5,6,7,8,9,10], technique: "Lancer, surf-casting", icon: "fish.fill", minimumSize: "42 cm", closedMonths: [1,2], regulation: "2/jour max"),
                SeasonalSpecies(name: "Lieu jaune", months: [3,4,5,6,7,8,9,10], peakMonths: [4,5,6,7,8,9], technique: "Lancer, traîne", icon: "fish.fill", minimumSize: "30 cm"),
                SeasonalSpecies(name: "Maquereau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Mitraillette, plume", icon: "fish.fill", minimumSize: "20 cm"),
                SeasonalSpecies(name: "Dorade grise", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12,1], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "23 cm"),
                SeasonalSpecies(name: "Vieille", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [4,5,6,7,8,9], technique: "Roche, fond", icon: "fish.fill", minimumSize: "23 cm"),
                SeasonalSpecies(name: "Congre", months: [4,5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Fond, roche", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Turbot", months: [4,5,6,7,8,9], peakMonths: [5,6,7,8], technique: "Fond, traîne", icon: "fish.fill", minimumSize: "30 cm"),
                SeasonalSpecies(name: "Tacaud", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [3,4,5,9,10,11], technique: "Fond", icon: "fish.fill", minimumSize: nil),
                // Céphalopodes
                SeasonalSpecies(name: "Seiche", months: [3,4,5,6,9,10], peakMonths: [4,5,6], technique: "Turlutte, fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Poulpe", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Turlutte, roche", icon: "fish.fill", minimumSize: "750 g"),
                // Crustaces
                SeasonalSpecies(name: "Tourteau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Pêche à pied, casier", icon: "tortoise.fill", minimumSize: "14 cm"),
                SeasonalSpecies(name: "Araignée de mer", months: [4,5,6,7,8], peakMonths: [5,6,7], technique: "Casier, plongée", icon: "tortoise.fill", minimumSize: "12 cm (céphalothorax)"),
                SeasonalSpecies(name: "Homard", months: [4,5,6,7,8], peakMonths: [5,6,7], technique: "Casier", icon: "tortoise.fill", minimumSize: "8.7 cm (céphalothorax)", regulation: "5 max/sortie"),
                SeasonalSpecies(name: "Étrille", months: [4,5,6,7,8,9,10], peakMonths: [5,6,7,8], technique: "Pêche à pied", icon: "tortoise.fill", minimumSize: "6.5 cm"),
                // Coquillages
                SeasonalSpecies(name: "Palourde", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12,1,2], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm"),
                SeasonalSpecies(name: "Coque", months: [9,10,11,12,1,2,3,4,5], peakMonths: [10,11,12,1,2], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "3 cm"),
                SeasonalSpecies(name: "Ormeau", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12,1], technique: "Pêche à pied, plongée", icon: "fossil.shell.fill", minimumSize: "9 cm", closedMonths: [6,7,8], regulation: "20 max/pers"),
                SeasonalSpecies(name: "Moule", months: [6,7,8,9,10,11,12,1,2], peakMonths: [7,8,9,10], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm", regulation: "5 kg max/pers"),
            ]

        // MARK: Atlantique Sud (Vendée → Pays basque)
        case .atlantiqueSud:
            return [
                // Poissons
                SeasonalSpecies(name: "Bar", months: [3,4,5,6,7,8,9,10,11], peakMonths: [5,6,7,8,9,10], technique: "Surf-casting, lancer", icon: "fish.fill", minimumSize: "42 cm", closedMonths: [1,2], regulation: "2/jour max"),
                SeasonalSpecies(name: "Dorade royale", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "23 cm"),
                SeasonalSpecies(name: "Maigre", months: [5,6,7,8,9], peakMonths: [6,7,8], technique: "Fond, lancer", icon: "fish.fill", minimumSize: "45 cm"),
                SeasonalSpecies(name: "Sole", months: [10,11,12,1,2,3], peakMonths: [10,11,12], technique: "Fond, surf-casting", icon: "fish.fill", minimumSize: "24 cm"),
                SeasonalSpecies(name: "Maquereau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Mitraillette, plume", icon: "fish.fill", minimumSize: "20 cm"),
                SeasonalSpecies(name: "Mulet", months: [4,5,6,7,8,9,10], peakMonths: [5,6,7,8,9], technique: "Flotteur, pain", icon: "fish.fill", minimumSize: "20 cm"),
                SeasonalSpecies(name: "Chinchard", months: [5,6,7,8,9,10], peakMonths: [7,8,9], technique: "Mitraillette, fond", icon: "fish.fill", minimumSize: "15 cm"),
                // Céphalopodes
                SeasonalSpecies(name: "Seiche", months: [3,4,5,6,9,10], peakMonths: [4,5,6], technique: "Turlutte, fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Chipiron (Encornet)", months: [7,8,9,10], peakMonths: [8,9,10], technique: "Turlutte", icon: "fish.fill", minimumSize: nil),
                // Crustaces
                SeasonalSpecies(name: "Tourteau", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Pêche à pied, casier", icon: "tortoise.fill", minimumSize: "14 cm"),
                SeasonalSpecies(name: "Étrille", months: [4,5,6,7,8,9,10], peakMonths: [5,6,7,8], technique: "Pêche à pied", icon: "tortoise.fill", minimumSize: "6.5 cm"),
                SeasonalSpecies(name: "Crevette grise", months: [6,7,8,9,10], peakMonths: [7,8,9], technique: "Haveneau", icon: "tortoise.fill", minimumSize: nil),
                // Coquillages
                SeasonalSpecies(name: "Palourde", months: [9,10,11,12,1,2,3], peakMonths: [10,11,12,1,2], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm"),
                SeasonalSpecies(name: "Couteau", months: [10,11,12,1,2,3,4,5], peakMonths: [11,12,1,2], technique: "Pêche à pied (sel)", icon: "fossil.shell.fill", minimumSize: "10 cm"),
                SeasonalSpecies(name: "Huître plate", months: [9,10,11,12,1,2,3,4], peakMonths: [10,11,12,1,2,3], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: nil),
                SeasonalSpecies(name: "Moule", months: [6,7,8,9,10,11,12,1,2], peakMonths: [7,8,9,10], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm"),
            ]

        // MARK: Mediterranee
        case .mediterranee:
            return [
                // Poissons
                SeasonalSpecies(name: "Loup (Bar)", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [3,4,5,9,10,11], technique: "Lancer, rockfishing", icon: "fish.fill", minimumSize: "30 cm", regulation: "1/jour max"),
                SeasonalSpecies(name: "Dorade royale", months: [4,5,6,7,8,9,10,11], peakMonths: [6,7,8,9,10], technique: "Fond, surfcasting", icon: "fish.fill", minimumSize: "23 cm"),
                SeasonalSpecies(name: "Sar commun", months: [3,4,5,6,7,8,9,10,11], peakMonths: [4,5,6,9,10], technique: "Flotteur, roche", icon: "fish.fill", minimumSize: "23 cm"),
                SeasonalSpecies(name: "Denti", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Fond, traîne", icon: "fish.fill", minimumSize: "25 cm"),
                SeasonalSpecies(name: "Pageot", months: [4,5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Fond", icon: "fish.fill", minimumSize: "15 cm"),
                SeasonalSpecies(name: "Oblade", months: [4,5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Flotteur, pain", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Rascasse", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [5,6,7,8,9], technique: "Rockfishing, fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Bonite", months: [6,7,8,9,10], peakMonths: [7,8,9], technique: "Traîne, lancer", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Sériole", months: [6,7,8,9,10], peakMonths: [7,8,9,10], technique: "Traîne, jigging", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Mulet", months: [3,4,5,6,7,8,9,10,11], peakMonths: [5,6,7,8,9], technique: "Flotteur, pain", icon: "fish.fill", minimumSize: "20 cm"),
                // Céphalopodes
                SeasonalSpecies(name: "Poulpe", months: [5,6,7,8,9,10], peakMonths: [6,7,8,9], technique: "Turlutte, roche", icon: "fish.fill", minimumSize: "750 g"),
                SeasonalSpecies(name: "Seiche", months: [3,4,5,6,9,10], peakMonths: [4,5,6], technique: "Turlutte, fond", icon: "fish.fill", minimumSize: nil),
                SeasonalSpecies(name: "Encornet", months: [9,10,11,12,1], peakMonths: [10,11,12], technique: "Turlutte", icon: "fish.fill", minimumSize: nil),
                // Coquillages
                SeasonalSpecies(name: "Oursin", months: [11,12,1,2,3], peakMonths: [12,1,2], technique: "Plongée, pêche à pied", icon: "fossil.shell.fill", minimumSize: "5 cm (hors piquants)", closedMonths: [5,6,7,8,9,10], regulation: "4 douzaines max"),
                SeasonalSpecies(name: "Moule", months: [6,7,8,9,10,11,12,1,2], peakMonths: [7,8,9,10], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "4 cm"),
                SeasonalSpecies(name: "Clovisse", months: [9,10,11,12,1,2,3,4,5], peakMonths: [10,11,12,1], technique: "Pêche à pied", icon: "fossil.shell.fill", minimumSize: "2.5 cm"),
                SeasonalSpecies(name: "Violet", months: [1,2,3,4,5,6,7,8,9,10,11,12], peakMonths: [9,10,11,12,1,2], technique: "Plongée", icon: "fossil.shell.fill", minimumSize: nil),
            ]
        }
    }
}

// MARK: - Fishing Service

final class FishingService {
    static let shared = FishingService()
    private init() {}

    func evaluate(
        solunar: SolunarData,
        tideData: TideData?,
        wind: Double?,
        gust: Double?,
        pressureCurrent: Double?,
        pressureTrend: Double?,
        waveHeight: Double? = nil,
        wavePeriod: Double? = nil,
        seaTemp: Double? = nil
    ) -> FishingConditions {
        var details: [String] = []

        // --- Solunar score (25 pts) ---
        let solunarScore = evaluateSolunar(solunar: solunar, details: &details)

        // --- Tide score (20 pts) ---
        let tideScore = evaluateTide(tideData: tideData, details: &details)

        // --- Wind score (20 pts) ---
        let windScore = evaluateWind(wind: wind, gust: gust, details: &details)

        // --- Sea state score (20 pts) ---
        let seaScore = evaluateSea(waveHeight: waveHeight, wavePeriod: wavePeriod, seaTemp: seaTemp, details: &details)

        // --- Pressure score (15 pts) ---
        let pressureScore = evaluatePressure(current: pressureCurrent, trend: pressureTrend, details: &details)

        let totalScore = solunarScore + tideScore + windScore + seaScore + pressureScore

        // Build best windows
        let windows = buildWindows(solunar: solunar, tideData: tideData)

        return FishingConditions(
            score: totalScore,
            solunarScore: solunarScore,
            tideScore: tideScore,
            windScore: windScore,
            seaScore: seaScore,
            pressureScore: pressureScore,
            details: details,
            bestWindows: windows
        )
    }

    // MARK: - Sub-scores

    private func evaluateSolunar(solunar: SolunarData, details: inout [String]) -> Int {
        var score = 0

        // Moon phase: 0-12 pts
        let phase = solunar.moonPhase
        let phaseDistance = min(phase, 1.0 - phase)
        let fullDistance = abs(phase - 0.5)

        if phaseDistance < 0.05 {
            score += 12
            details.append("Nouvelle lune : activité maximale")
        } else if fullDistance < 0.05 {
            score += 10
            details.append("Pleine lune : très bonne activité")
        } else if phaseDistance < 0.15 || fullDistance < 0.15 {
            score += 6
            details.append("\(solunar.moonPhaseName) : activité modérée")
        } else {
            score += 3
            details.append("\(solunar.moonPhaseName) : activité réduite")
        }

        // Active periods: 0-13 pts
        let now = Date()
        let hasMajorNow = solunar.majorPeriods.contains { now >= $0.start && now <= $0.end }
        let hasMajorSoon = solunar.majorPeriods.contains { period in
            let timeUntil = period.start.timeIntervalSince(now)
            return timeUntil > 0 && timeUntil < 2 * 3600
        }
        let hasMinorNow = solunar.minorPeriods.contains { now >= $0.start && now <= $0.end }

        if hasMajorNow {
            score += 13
            details.append("Période solunaire majeure en cours")
        } else if hasMajorSoon {
            score += 8
            details.append("Période majeure dans moins de 2h")
        } else if hasMinorNow {
            score += 5
            details.append("Période solunaire mineure en cours")
        } else {
            score += 2
        }

        return min(score, 25)
    }

    private func evaluateTide(tideData: TideData?, details: inout [String]) -> Int {
        guard let data = tideData else {
            details.append("Données de marée non disponibles")
            return 10 // Neutral score
        }

        var score = 0

        // Coefficient: 0-8 pts
        if let coef = data.todayCoefficient {
            if coef >= 60 && coef <= 90 {
                score += 8
                details.append("Coefficient \(coef) : idéal pour la pêche")
            } else if (coef >= 40 && coef < 60) || (coef > 90 && coef <= 110) {
                score += 5
                details.append("Coefficient \(coef) : conditions correctes")
            } else if coef > 110 {
                score += 4
                details.append("Coefficient \(coef) : forts courants")
            } else {
                score += 2
                details.append("Coefficient \(coef) : mortes-eaux")
            }
        } else {
            score += 4
        }

        // Phase de marée: 0-12 pts
        if let nextTide = data.nextTide {
            let minutesUntil = nextTide.time.timeIntervalSinceNow / 60
            if abs(minutesUntil) <= 30 {
                score += 12
                details.append("Étale de marée : moment optimal")
            } else if abs(minutesUntil) <= 120 {
                score += 9
                let label = nextTide.type == "high" ? "pleine mer" : "basse mer"
                details.append("A \(Int(abs(minutesUntil)))min de la \(label)")
            } else {
                score += 4
            }
        } else {
            score += 6
        }

        return min(score, 20)
    }

    private func evaluateWind(wind: Double?, gust: Double?, details: inout [String]) -> Int {
        guard let windSpeed = wind else {
            details.append("Données de vent non disponibles")
            return 10
        }

        var score = 0

        // Force: 0-12 pts
        if windSpeed < 8 {
            score += 12
            details.append("Vent faible (\(Int(windSpeed)) nds) : conditions idéales")
        } else if windSpeed < 15 {
            score += 9
            details.append("Vent modéré (\(Int(windSpeed)) nds) : bonnes conditions")
        } else if windSpeed < 20 {
            score += 5
            details.append("Vent soutenu (\(Int(windSpeed)) nds) : pêche difficile")
        } else {
            score += 1
            details.append("Vent fort (\(Int(windSpeed)) nds) : conditions défavorables")
        }

        // Régularité (rafales): 0-8 pts
        if let gustSpeed = gust, windSpeed > 0 {
            let ratio = gustSpeed / windSpeed
            if ratio < 1.5 {
                score += 8
            } else if ratio < 2.0 {
                score += 4
                details.append("Rafales irrégulières")
            } else {
                score += 1
                details.append("Rafales très fortes")
            }
        } else {
            score += 4
        }

        return min(score, 20)
    }

    private func evaluatePressure(current: Double?, trend: Double?, details: inout [String]) -> Int {
        var score = 0

        // Tendance: 0-9 pts
        if let t = trend {
            if t < -1.5 && t > -4 {
                score += 9
                details.append("Pression en baisse lente : poissons actifs")
            } else if abs(t) <= 1.5 {
                score += 6
                details.append("Pression stable")
            } else if t > 0 && t < 3 {
                score += 4
                details.append("Pression en hausse")
            } else {
                score += 1
                details.append("Forte variation de pression")
            }
        } else {
            score += 5
        }

        // Valeur absolue: 0-6 pts
        if let p = current {
            if p >= 1010 && p <= 1020 {
                score += 6
            } else if p >= 1005 && p <= 1025 {
                score += 4
            } else {
                score += 1
            }
        } else {
            score += 3
        }

        return min(score, 15)
    }

    private func evaluateSea(waveHeight: Double?, wavePeriod: Double?, seaTemp: Double?, details: inout [String]) -> Int {
        guard waveHeight != nil || seaTemp != nil else {
            return 10 // Neutral when no data
        }

        var score = 0

        // Wave height: 0-10 pts
        if let h = waveHeight {
            if h < 0.3 {
                score += 10
                details.append("Mer très calme : idéal")
            } else if h < 0.5 {
                score += 9
                details.append("Mer calme (\(String(format: "%.1f", h))m)")
            } else if h < 1.0 {
                score += 7
                details.append("Mer belle (\(String(format: "%.1f", h))m)")
            } else if h < 1.5 {
                score += 5
                details.append("Mer peu agitée (\(String(format: "%.1f", h))m)")
            } else if h < 2.0 {
                score += 3
                details.append("Mer agitée (\(String(format: "%.1f", h))m)")
            } else if h < 2.5 {
                score += 1
                details.append("Mer forte (\(String(format: "%.1f", h))m) : pêche déconseillée")
            } else {
                details.append("Mer très forte (\(String(format: "%.1f", h))m) : danger")
            }
        } else {
            score += 5
        }

        // Wave period: 0-5 pts
        if let p = wavePeriod {
            if p > 10 { score += 5 }
            else if p > 8 { score += 4 }
            else if p > 6 { score += 3 }
            else if p > 4 { score += 2 }
            else { score += 1 }
        } else {
            score += 3
        }

        // Sea temperature: 0-5 pts
        if let t = seaTemp {
            if t >= 14 && t <= 18 {
                score += 5
                details.append("Eau \(String(format: "%.0f", t))°C : température idéale")
            } else if (t >= 12 && t < 14) || (t > 18 && t <= 22) {
                score += 4
            } else if t >= 10 && t < 12 {
                score += 2
                details.append("Eau froide (\(String(format: "%.0f", t))°C)")
            } else if t >= 8 && t < 10 {
                score += 1
            } else if t > 22 {
                score += 3
                details.append("Eau chaude (\(String(format: "%.0f", t))°C) : poissons en profondeur")
            }
        } else {
            score += 3
        }

        return min(score, 20)
    }

    // MARK: - Best Windows

    private func buildWindows(solunar: SolunarData, tideData: TideData?) -> [FishingWindow] {
        var windows: [FishingWindow] = []

        // Tide change windows (±2h around tide events)
        var tideWindows: [(start: Date, end: Date)] = []
        if let nextHigh = tideData?.nextHighTide?.parsedTime {
            let start = nextHigh.addingTimeInterval(-2 * 3600)
            let end = nextHigh.addingTimeInterval(2 * 3600)
            tideWindows.append((start, end))
        }
        if let nextLow = tideData?.nextLowTide?.parsedTime {
            let start = nextLow.addingTimeInterval(-2 * 3600)
            let end = nextLow.addingTimeInterval(2 * 3600)
            tideWindows.append((start, end))
        }

        // Check solunar periods against tide windows
        for period in solunar.majorPeriods {
            let overlapsWithTide = tideWindows.contains { tw in
                period.peak >= tw.start && period.peak <= tw.end
            }

            if overlapsWithTide {
                windows.append(FishingWindow(
                    start: period.start,
                    end: period.end,
                    reason: "Période majeure + changement de marée",
                    quality: .excellent
                ))
            } else {
                windows.append(FishingWindow(
                    start: period.start,
                    end: period.end,
                    reason: "Période solunaire majeure",
                    quality: .good
                ))
            }
        }

        for period in solunar.minorPeriods {
            let overlapsWithTide = tideWindows.contains { tw in
                period.peak >= tw.start && period.peak <= tw.end
            }

            if overlapsWithTide {
                windows.append(FishingWindow(
                    start: period.start,
                    end: period.end,
                    reason: "Période mineure + changement de marée",
                    quality: .good
                ))
            } else {
                windows.append(FishingWindow(
                    start: period.start,
                    end: period.end,
                    reason: "Période solunaire mineure",
                    quality: .moderate
                ))
            }
        }

        // Add standalone tide windows if no solunar overlap
        for tw in tideWindows {
            let alreadyCovered = windows.contains { w in
                abs(w.start.timeIntervalSince(tw.start)) < 3600
            }
            if !alreadyCovered {
                windows.append(FishingWindow(
                    start: tw.start,
                    end: tw.end,
                    reason: "Changement de marée",
                    quality: .moderate
                ))
            }
        }

        // Sort by start time and filter future only
        let now = Date()
        return windows
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Region Detection

    static func detectRegion(latitude: Double, longitude: Double) -> FishingRegion {
        // Mediterranean: south of ~43.8N and east of ~3E, or Corsica
        if latitude < 43.8 && longitude > 3.0 {
            return .mediterranee
        }
        if latitude < 43.0 && longitude > 8.0 {
            return .mediterranee
        }
        // Manche / Mer du Nord: northern coast facing English Channel
        // Normandie, Picardie, Nord-Pas-de-Calais, Saint-Malo area
        if latitude > 49.0 && longitude > -5.5 {
            return .manche
        }
        if latitude > 48.5 && longitude > -2.0 {
            return .manche
        }
        // Atlantic Sud: south of Loire (~47N)
        if latitude < 47.0 {
            return .atlantiqueSud
        }
        // Default: Atlantic Nord (Bretagne)
        return .atlantiqueNord
    }
}
