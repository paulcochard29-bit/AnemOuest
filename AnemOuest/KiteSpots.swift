//
//  KiteSpots.swift
//  AnemOuest
//
//  Spots de kitesurf - Sources: kiteloopers.com, thespot2be.com
//

import Foundation
import CoreLocation
import SwiftUI

struct KiteSpot: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let orientation: String
    let level: SpotLevel
    let type: SpotType

    // Données enrichies (thespot2be.com)
    // Par défaut, les spots de kite sont aussi praticables en windsurf et wingfoil
    var waveType: WaveType = .unknown
    var supportsKite: Bool = true
    var supportsWindsurf: Bool = true
    var supportsWing: Bool = true
    var supportsSurf: Bool = false

    // Préférence de marée (certains spots nécessitent marée haute/basse)
    var tidePreference: KiteTidePreference = .all

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Activities summary for display
    var activitiesSummary: String {
        var activities: [String] = []
        if supportsKite { activities.append("Kite") }
        if supportsWindsurf { activities.append("Windsurf") }
        if supportsWing { activities.append("Wing") }
        if supportsSurf { activities.append("Surf") }
        return activities.isEmpty ? "Kite" : activities.joined(separator: ", ")
    }
}

/// Préférence de marée pour les spots de kite
enum KiteTidePreference: String, Codable, CaseIterable {
    case all = "all"
    case highOnly = "high"
    case lowOnly = "low"
    case midTide = "mid"
    case avoidHigh = "avoidHigh"   // Dangereux à marée haute
    case avoidLow = "avoidLow"     // Dangereux à marée basse

    var displayName: String {
        switch self {
        case .all: return "Toutes marées"
        case .highOnly: return "Marée haute"
        case .lowOnly: return "Marée basse"
        case .midTide: return "Mi-marée"
        case .avoidHigh: return "Éviter marée haute"
        case .avoidLow: return "Éviter marée basse"
        }
    }

    var shortName: String {
        switch self {
        case .all: return "Toutes"
        case .highOnly: return "Haute"
        case .lowOnly: return "Basse"
        case .midTide: return "Mi-marée"
        case .avoidHigh: return "Pas haute"
        case .avoidLow: return "Pas basse"
        }
    }

    var icon: String {
        switch self {
        case .all: return "water.waves"
        case .highOnly: return "arrow.up.to.line"
        case .lowOnly: return "arrow.down.to.line"
        case .midTide: return "equal"
        case .avoidHigh: return "exclamationmark.arrow.up"
        case .avoidLow: return "exclamationmark.arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .all: return .blue
        case .highOnly: return .cyan
        case .lowOnly: return .teal
        case .midTide: return .green
        case .avoidHigh, .avoidLow: return .orange
        }
    }

    /// Indique si la marée actuelle est compatible
    func isCompatible(with tideData: TideData?) -> Bool {
        guard self != .all else { return true }
        guard let tide = tideData, let nextEvent = tide.tides.first else { return true }

        // Déterminer si on monte ou descend
        let isRising = !nextEvent.isHighTide // Si prochain = haute, on monte

        switch self {
        case .all:
            return true
        case .highOnly:
            // OK si proche de marée haute (< 2h avant/après)
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = eventTime.timeIntervalSince(Date()) / 3600
                return nextEvent.isHighTide && hoursUntil < 2 && hoursUntil > -2
            }
            return false
        case .lowOnly:
            // OK si proche de marée basse
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = eventTime.timeIntervalSince(Date()) / 3600
                return !nextEvent.isHighTide && hoursUntil < 2 && hoursUntil > -2
            }
            return false
        case .midTide:
            // OK si entre 2h et 4h d'une marée
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = abs(eventTime.timeIntervalSince(Date()) / 3600)
                return hoursUntil >= 2 && hoursUntil <= 4
            }
            return false
        case .avoidHigh:
            // NOK si proche de marée haute
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = eventTime.timeIntervalSince(Date()) / 3600
                if nextEvent.isHighTide && hoursUntil < 2 && hoursUntil > -2 {
                    return false
                }
            }
            return true
        case .avoidLow:
            // NOK si proche de marée basse
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = eventTime.timeIntervalSince(Date()) / 3600
                if !nextEvent.isHighTide && hoursUntil < 2 && hoursUntil > -2 {
                    return false
                }
            }
            return true
        }
    }
}

enum SpotLevel: String, Comparable {
    case beginner = "Débutant"
    case intermediate = "Intermédiaire"
    case advanced = "Confirmé"
    case expert = "Expert"

    private var sortOrder: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced: return 2
        case .expert: return 3
        }
    }

    static func < (lhs: SpotLevel, rhs: SpotLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// Ideal wind range (knots) for this level
    var idealWindRange: ClosedRange<Double> {
        switch self {
        case .beginner: return 10...18
        case .intermediate: return 12...22
        case .advanced: return 14...28
        case .expert: return 16...35
        }
    }
}

/// Niveau du rider — détermine la plage de vent idéale indépendamment du spot
enum KiteRiderLevel: String, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case expert = "expert"

    var displayName: String {
        switch self {
        case .beginner: return "Débutant"
        case .intermediate: return "Intermédiaire"
        case .advanced: return "Confirmé"
        case .expert: return "Expert"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .advanced: return "3.circle.fill"
        case .expert: return "star.circle.fill"
        }
    }

    /// Corresponding SpotLevel for comparison
    var asSpotLevel: SpotLevel {
        switch self {
        case .beginner: return .beginner
        case .intermediate: return .intermediate
        case .advanced: return .advanced
        case .expert: return .expert
        }
    }
}

enum SpotType: String {
    case beach = "Plage"
    case lagoon = "Lagune"
    case bay = "Baie"
    case spot = "Spot"
    case lake = "Lac"
}

enum WaveType: String {
    case flat = "Flat"
    case smallWave = "Clapot"
    case bigWave = "Vagues"
    case unknown = ""

    var icon: String {
        switch self {
        case .flat: return "water.waves"
        case .smallWave: return "wind"
        case .bigWave: return "tornado"
        case .unknown: return "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .flat: return .cyan
        case .smallWave: return .orange
        case .bigWave: return .red
        case .unknown: return .secondary
        }
    }
}

// MARK: - Kite Condition Rating

struct KiteConditionRating {
    let score: Int           // 0-100
    let windScore: Int       // 0-40
    let directionScore: Int  // 0-30
    let gustScore: Int       // 0-30
    let summary: String
    let details: [String]

    var color: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .orange
        case 20..<40: return .red
        default: return .gray
        }
    }

    var label: String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Bon"
        case 40..<60: return "Moyen"
        case 20..<40: return "Médiocre"
        default: return "Mauvais"
        }
    }

    var icon: String {
        switch score {
        case 80...100: return "hand.thumbsup.fill"
        case 60..<80: return "hand.thumbsup"
        case 40..<60: return "hand.raised"
        case 20..<40: return "hand.thumbsdown"
        default: return "hand.thumbsdown.fill"
        }
    }

    /// Evaluate kite conditions from station data
    /// - dangerThreshold: seuil de vent fort (nds) au-delà duquel la note baisse fortement (réglage utilisateur)
    /// - riderLevel: niveau du rider — la plage idéale utilise le max(rider, spot)
    static func evaluate(wind: Double, gust: Double, direction: Double, spot: KiteSpot, dangerThreshold: Double = 40, riderLevel: KiteRiderLevel = .intermediate) -> KiteConditionRating {
        var windScore = 0
        var directionScore = 0
        var gustScore = 0
        var details: [String] = []

        // --- Wind speed score (0-40) ---
        // Effective level = max(rider level, spot level)
        let effectiveLevel = max(spot.level, riderLevel.asSpotLevel)
        let idealRange = effectiveLevel.idealWindRange

        if idealRange.contains(wind) {
            // In range: score 25-40 depending on how centered
            let center = (idealRange.lowerBound + idealRange.upperBound) / 2
            let halfRange = (idealRange.upperBound - idealRange.lowerBound) / 2
            let distFromCenter = abs(wind - center)
            let centerFactor = max(0, 1 - (distFromCenter / halfRange))
            windScore = Int(25 + centerFactor * 15)
            details.append("Vent \(Int(wind)) nds — dans la plage idéale")
        } else if wind < idealRange.lowerBound {
            let deficit = idealRange.lowerBound - wind
            windScore = max(0, Int(20 - deficit * 3))
            details.append("Vent faible (\(Int(wind)) nds)")
        } else if wind <= dangerThreshold {
            // Au-dessus de la plage idéale mais sous le seuil de danger
            let range = dangerThreshold - idealRange.upperBound
            if range > 0 {
                let fraction = (wind - idealRange.upperBound) / range
                windScore = Int(25 - fraction * 5) // 25 → 20
            } else {
                windScore = 20
            }
            details.append("Vent soutenu (\(Int(wind)) nds)")
        } else {
            // Au-dessus du seuil de danger — baisse forte
            let excess = wind - dangerThreshold
            windScore = max(0, Int(18 - excess * 3))
            details.append("Vent dangereux (\(Int(wind)) nds)")
        }

        // --- Direction score (0-30) ---
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let dirIndex = Int(round(direction / 45.0)) % 8
        let windDir = directions[dirIndex]
        let spotOrientations = spot.orientation.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let isMatch = spotOrientations.contains { orient in
            windDir == orient ||
            (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
        }

        if isMatch {
            directionScore = 30
            details.append("Direction \(windDir) — favorable")
        } else {
            // Check adjacent directions for partial credit
            let allDirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            if let windIdx = allDirs.firstIndex(of: windDir) {
                let adjacent1 = allDirs[(windIdx + 1) % 8]
                let adjacent2 = allDirs[(windIdx + 7) % 8]
                let hasAdjacent = spotOrientations.contains(adjacent1) || spotOrientations.contains(adjacent2)
                directionScore = hasAdjacent ? 12 : 0
            }
            details.append("Direction \(windDir) — défavorable (idéal: \(spot.orientation))")
        }

        // --- Gust score (0-30) ---
        // Lower gust/wind ratio = more stable wind = better
        let gustRatio = wind > 0 ? gust / wind : 2.0
        if gustRatio <= 1.3 {
            gustScore = 30
            details.append("Vent stable (rafales \(Int(gust)) nds)")
        } else if gustRatio <= 1.5 {
            gustScore = 22
            details.append("Rafales modérées (\(Int(gust)) nds)")
        } else if gustRatio <= 1.8 {
            gustScore = 12
            details.append("Rafales marquées (\(Int(gust)) nds)")
        } else {
            gustScore = 5
            details.append("Vent irrégulier (rafales \(Int(gust)) nds)")
        }

        let total = min(100, max(0, windScore + directionScore + gustScore))

        let summary: String
        switch total {
        case 80...100: summary = "Conditions excellentes"
        case 60..<80: summary = "Bonnes conditions"
        case 40..<60: summary = "Conditions moyennes"
        case 20..<40: summary = "Conditions difficiles"
        default: summary = "Conditions défavorables"
        }

        return KiteConditionRating(
            score: total,
            windScore: windScore,
            directionScore: directionScore,
            gustScore: gustScore,
            summary: summary,
            details: details
        )
    }
}

// MARK: - Liste des spots de kitesurf en France (Source: kiteloopers.com)
// Total: 410 spots

let kiteSpots: [KiteSpot] = [
    KiteSpot(id: "bray-dunes-0", name: "Bray-Dunes - Plage de Bray-Dunes", latitude: 51.083301, longitude: 2.516769,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "zuydcoote-1", name: "Zuydcoote - Plage de Zuydcoote", latitude: 51.074240, longitude: 2.478919,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "leffrinckoucke-2", name: "Leffrinckoucke - Plage de Leffrinckoucke", latitude: 51.066428, longitude: 2.443674,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "malo-les-bains-3", name: "Malo-les-Bains - Plage de Malo-les-Bains", latitude: 51.057616, longitude: 2.403715,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "loon-plage-4", name: "Loon-Plage - Plage du Clipon", latitude: 51.036923, longitude: 2.210303,
             orientation: "W,NW", level: .advanced, type: .beach),
    KiteSpot(id: "grand-fort-philippe-5", name: "Grand-Fort-Philippe - La Petite Mer", latitude: 51.015745, longitude: 2.109215,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "oye-plage-6", name: "Oye-Plage - Les Hemmes de Marck", latitude: 50.995010, longitude: 1.985054,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "calais-7", name: "Calais - Blériot-Plage", latitude: 50.967316, longitude: 1.829531,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "sangatte-8", name: "Sangatte - Plage de Sangatte", latitude: 50.943794, longitude: 1.741812,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "wissant-9", name: "Wissant - Baie", latitude: 50.890249, longitude: 1.656445,
             orientation: "W,SW,NW", level: .intermediate, type: .bay, waveType: .bigWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: true),
    KiteSpot(id: "audresselles-10", name: "Audresselles - Plage d’Audresselles", latitude: 50.817459, longitude: 1.589826,
             orientation: "W,SW", level: .advanced, type: .beach),
    KiteSpot(id: "ambleteuse-11", name: "Ambleteuse - Plage d’Ambleteuse", latitude: 50.802789, longitude: 1.596623,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "wimereux-12", name: "Wimereux - Pointe aux Oies", latitude: 50.790582, longitude: 1.599469,
             orientation: "W,SW", level: .advanced, type: .beach, waveType: .bigWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: true),
    KiteSpot(id: "wimereux-13", name: "Wimereux - Plage de Wimereux", latitude: 50.766967, longitude: 1.600927,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "boulogne-sur-mer-14", name: "Boulogne-sur-Mer - Plage de Boulogne-sur-Mer", latitude: 50.738007, longitude: 1.588905,
             orientation: "W,SW", level: .advanced, type: .beach),
    KiteSpot(id: "hardelot-plage-15", name: "Hardelot-Plage - Plage d’Hardelot", latitude: 50.632565, longitude: 1.571389,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "sainte-cecile-16", name: "Sainte-Cécile - Sainte-Cécile-Plage", latitude: 50.574883, longitude: 1.574281,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "le-touquet-paris-plage-17", name: "Le Touquet-Paris-Plage - Baie de la Canche", latitude: 50.543954, longitude: 1.599059,
             orientation: "W,SW", level: .beginner, type: .bay, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "le-touquet-paris-plage-18", name: "Le Touquet-Paris-Plage - Plage du Touquet", latitude: 50.515934, longitude: 1.576353,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "berck-sur-mer-19", name: "Berck-sur-Mer - Plage principale", latitude: 50.412834, longitude: 1.554204,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "fort-mahon-plage-20", name: "Fort-Mahon-Plage - Plage de Fort-Mahon", latitude: 50.343702, longitude: 1.547294,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "le-hourdel-21", name: "Le Hourdel - Pointe du Hourdel", latitude: 50.217766, longitude: 1.565734,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "le-crotoy-22", name: "Le Crotoy - Plage du Crotoy", latitude: 50.216129, longitude: 1.618881,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "cayeux-sur-mer-23", name: "Cayeux-sur-Mer - Plage de Cayeux-sur-Mer", latitude: 50.190161, longitude: 1.497362,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "mers-les-bains-24", name: "Mers-les-Bains - Plage de Mers-les-Bains", latitude: 50.069776, longitude: 1.384029,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "petit-caux-25", name: "Petit-Caux - Plage de Petit-Caux", latitude: 49.970728, longitude: 1.195592,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "dieppe-26", name: "Dieppe - Plage de Dieppe", latitude: 49.929759, longitude: 1.072824,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "pourville-sur-mer-27", name: "Pourville-sur-Mer - Plage de Pourville-sur-Mer", latitude: 49.918049, longitude: 1.030008,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "quiberville-sur-mer-28", name: "Quiberville-sur-Mer - Plage de Quiberville-sur-Mer", latitude: 49.905768, longitude: 0.924197,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-aubin-sur-mer-29", name: "Saint-Aubin-sur-Mer - Plage de Saint-Aubin-sur-Mer", latitude: 49.894608, longitude: 0.870813,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-valery-en-caux-30", name: "Saint-Valery-en-Caux - Plage de Saint-Valery-en-Caux", latitude: 49.870798, longitude: 0.714740,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "veulettes-sur-mer-31", name: "Veulettes-sur-Mer - Plage de Veulettes-sur-Mer", latitude: 49.853728, longitude: 0.598077,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "fecamp-32", name: "Fécamp - Plage de Fécamp", latitude: 49.762108, longitude: 0.361144,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "vicq-sur-mer-33", name: "Vicq-sur-Mer - Le Vicq Plage", latitude: 49.703911, longitude: -1.401311,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "gouberville-gattemare-34", name: "Gouberville (Gattemare)", latitude: 49.697681, longitude: -1.304216,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "fermanville-35", name: "Fermanville - Plage de la Mondrée", latitude: 49.693590, longitude: -1.452759,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "urville-nacqueville-36", name: "Urville-Nacqueville", latitude: 49.678676, longitude: -1.736584,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "barfleur-37", name: "Barfleur - Plage de la Masse", latitude: 49.674816, longitude: -1.263596,
             orientation: "W,NW,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "collignon-38", name: "Collignon", latitude: 49.657891, longitude: -1.567652,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "le-becquet-39", name: "Le Becquet", latitude: 49.655146, longitude: -1.555797,
             orientation: "NE,E", level: .intermediate, type: .beach),
    KiteSpot(id: "antifer-40", name: "Antifer - Plage d’Antifer", latitude: 49.647030, longitude: 0.150018,
             orientation: "W,NW", level: .advanced, type: .beach),
    KiteSpot(id: "vauville-41", name: "Vauville", latitude: 49.628760, longitude: -1.856798,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "dranguet-42", name: "Dranguet", latitude: 49.616856, longitude: -1.225351,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "jonville-43", name: "Jonville - Pont de Saire", latitude: 49.611236, longitude: -1.251135,
             orientation: "NE,E,SE,S,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "biville-44", name: "Biville", latitude: 49.608432, longitude: -1.850264,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "jonville-45", name: "Jonville - Pointe de Saire", latitude: 49.604027, longitude: -1.232385,
             orientation: "NE,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "la-hougue-46", name: "La Hougue - Baie", latitude: 49.580009, longitude: -1.274340,
             orientation: "NW,W,SW", level: .beginner, type: .bay),
    KiteSpot(id: "siouville-hague-47", name: "Siouville-Hague", latitude: 49.574476, longitude: -1.846464,
             orientation: "WSW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "morsalines-48", name: "Morsalines", latitude: 49.569285, longitude: -1.302228,
             orientation: "NE,E,SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "quineville-49", name: "Quineville", latitude: 49.513720, longitude: -1.280663,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "sainte-adresse-50", name: "Sainte-Adresse - Plage de Sainte-Adresse", latitude: 49.505651, longitude: 0.067965,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "le-havre-51", name: "Le Havre - Plage du Ponant", latitude: 49.499877, longitude: 0.085930,
             orientation: "W,NW", level: .advanced, type: .beach),
    KiteSpot(id: "le-havre-52", name: "Le Havre - Plage du Havre", latitude: 49.495039, longitude: 0.088745,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "sciotot-53", name: "Sciotot", latitude: 49.494322, longitude: -1.851268,
             orientation: "S,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "utah-beach-54", name: "Utah Beach", latitude: 49.413028, longitude: -1.165517,
             orientation: "N,NE,E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "hatainville-55", name: "Hatainville", latitude: 49.399666, longitude: -1.828292,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "gefosse-fontenay-56", name: "Gefosse-Fontenay", latitude: 49.374393, longitude: -1.102228,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "trouville-sur-mer-57", name: "Trouville-sur-mer", latitude: 49.371242, longitude: 0.076690,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "trouville-sur-mer-58", name: "Trouville-sur-mer - Plage 3", latitude: 49.370802, longitude: 0.076833,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "barneville-59", name: "Barneville", latitude: 49.368747, longitude: -1.781961,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "deauville-60", name: "Deauville", latitude: 49.359752, longitude: 0.060656,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "ver-sur-mer-61", name: "Ver-sur-Mer", latitude: 49.347651, longitude: -0.524026,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "asnelles-62", name: "Asnelles", latitude: 49.344843, longitude: -0.582868,
             orientation: "NW,NE", level: .beginner, type: .beach),
    KiteSpot(id: "courseulles-sur-mer-63", name: "Courseulles-sur-Mer", latitude: 49.337925, longitude: -0.447690,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "langrune-sur-mer-64", name: "Langrune-sur-Mer", latitude: 49.329047, longitude: -0.372865,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "villers-sur-mer-65", name: "Villers-sur-mer", latitude: 49.328808, longitude: 0.002887,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "port-bail-sur-mer-66", name: "Port-Bail-Sur-Mer - Havre de Portbail", latitude: 49.325818, longitude: -1.703325,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "luc-sur-mer-67", name: "Luc-sur-mer", latitude: 49.320736, longitude: -0.350591,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "denneville-68", name: "Denneville", latitude: 49.303410, longitude: -1.701668,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "houlgate-69", name: "Houlgate", latitude: 49.303079, longitude: -0.081979,
             orientation: "WSW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "coleville-70", name: "Coleville", latitude: 49.296534, longitude: -0.283313,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "cabourg-71", name: "Cabourg", latitude: 49.295882, longitude: -0.113768,
             orientation: "NW,N,NE", level: .beginner, type: .beach),
    KiteSpot(id: "riva-bella-72", name: "Riva-Bella", latitude: 49.294913, longitude: -0.256818,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "merville-franceville-plag-73", name: "Merville-Franceville-Plage", latitude: 49.288808, longitude: -0.212684,
             orientation: "NW,NE", level: .beginner, type: .beach),
    KiteSpot(id: "ouistreham-74", name: "Ouistreham - Estuaire de l’Orne", latitude: 49.278645, longitude: -0.233621,
             orientation: "NW,NE,SW", level: .beginner, type: .beach),
    KiteSpot(id: "anneville-sur-mer-75", name: "Anneville-sur-Mer", latitude: 49.123775, longitude: -1.601023,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "gouville-sur-mer-76", name: "Gouville-sur-Mer", latitude: 49.098267, longitude: -1.612877,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "agon-coutainville-77", name: "Agon-Coutainville - Plage de Coutainville", latitude: 49.045941, longitude: -1.602363,
             orientation: "SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "agon-coutainville-78", name: "Agon-Coutainville - La Pointe d’Agon", latitude: 49.000683, longitude: -1.569558,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "montmartin-sur-mer-79", name: "Montmartin-sur-Mer", latitude: 48.989750, longitude: -1.562907,
             orientation: "SW,W", level: .beginner, type: .beach),
    KiteSpot(id: "coudeville-plage-80", name: "Coudeville-Plage", latitude: 48.888125, longitude: -1.572713,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "larmor-81", name: "L’Armor - Sillon du Talbert", latitude: 48.874915, longitude: -3.074723,
             orientation: "NE,E,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "tregastel-82", name: "Trégastel - Plage de la Grève Rose", latitude: 48.829450, longitude: -3.527615,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "trestel-83", name: "Trestel", latitude: 48.827841, longitude: -3.359284,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "perros-guirec-84", name: "Perros-Guirec - Plage du Trestraou", latitude: 48.820030, longitude: -3.453173,
             orientation: "E,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-pair-sur-mer-85", name: "Saint-Pair-sur-Mer", latitude: 48.817209, longitude: -1.574700,
             orientation: "SW,NW", level: .beginner, type: .beach),
    KiteSpot(id: "nantouar-86", name: "Nantouar", latitude: 48.806691, longitude: -3.395698,
             orientation: "NE", level: .beginner, type: .beach),
    KiteSpot(id: "perros-guirec-87", name: "Perros-Guirec - Plage du Port", latitude: 48.806628, longitude: -3.433915,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-pair-sur-mer-88", name: "Saint-Pair-sur-Mer - Kairon Plage", latitude: 48.801688, longitude: -1.572609,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "ile-grande-89", name: "Île-Grande - Plage de Toul Gwenn", latitude: 48.800234, longitude: -3.562449,
             orientation: "NW,NE", level: .beginner, type: .beach),
    KiteSpot(id: "truzugal-90", name: "Truzugal", latitude: 48.800072, longitude: -3.426738,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "ile-grande-91", name: "Île-Grande - Saint-Sauveur", latitude: 48.796565, longitude: -3.587767,
             orientation: "S,SW", level: .advanced, type: .beach),
    KiteSpot(id: "trebeurden-92", name: "Trébeurden - Plage de Goas Treiz", latitude: 48.782671, longitude: -3.582366,
             orientation: "SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "jullouville-93", name: "Jullouville", latitude: 48.770754, longitude: -1.572556,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "trebeurden-94", name: "Trébeurden - Plage de Tresmeur", latitude: 48.763906, longitude: -3.582878,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "beg-leguer-95", name: "Beg Leguer - Plage de Goas Lagorn", latitude: 48.744656, longitude: -3.552749,
             orientation: "SW", level: .beginner, type: .beach),
    KiteSpot(id: "brehec-96", name: "Bréhec - Plage du Vieux Bréhec", latitude: 48.724103, longitude: -2.938217,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "primel-tregastel-97", name: "Primel-Trégastel", latitude: 48.715450, longitude: -3.806515,
             orientation: "W,WNW", level: .intermediate, type: .beach),
    KiteSpot(id: "dragey-98", name: "Dragey", latitude: 48.708466, longitude: -1.517873,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-jean-du-doigt-ploug-99", name: "Saint-Jean-du-Doigt (Plougasnou)", latitude: 48.706078, longitude: -3.780604,
             orientation: "E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "le-dossen-100", name: "Le Dossen", latitude: 48.699432, longitude: -4.064977,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "roguennic-101", name: "Roguennic - Plage des Amiets", latitude: 48.695467, longitude: -4.138472,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "genets-102", name: "Genêts - Plage du Bec d’Andaine", latitude: 48.685020, longitude: -1.505340,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-michel-en-greve-103", name: "Saint-Michel-en-Grève", latitude: 48.683310, longitude: -3.570271,
             orientation: "SW,W", level: .beginner, type: .beach),
    KiteSpot(id: "terenez-104", name: "Térénez", latitude: 48.679007, longitude: -3.851318,
             orientation: "W", level: .beginner, type: .beach),
    KiteSpot(id: "saint-efflam-105", name: "Saint-Efflam", latitude: 48.671749, longitude: -3.599778,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-malo-106", name: "Saint-Malo - Grande Plage du Sillon", latitude: 48.664403, longitude: -2.013275,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "pleherel-plage-vieux-bour-107", name: "Pléhérel Plage-Vieux Bourg - Anse du Croc", latitude: 48.660522, longitude: -2.362760,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "keremma-108", name: "Keremma", latitude: 48.654970, longitude: -4.246209,
             orientation: "W,NE", level: .beginner, type: .beach),
    KiteSpot(id: "sables-dor-les-pins-109", name: "Sables d’Or les Pins - Grève du Minieu", latitude: 48.650996, longitude: -2.407211,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "kermor-110", name: "Kermor - Baie de Goulven", latitude: 48.649288, longitude: -4.301199,
             orientation: "W,SW", level: .intermediate, type: .bay),
    KiteSpot(id: "mentoull-111", name: "Mentoull - Baie de Nodeven", latitude: 48.645351, longitude: -4.425213,
             orientation: "NW,W", level: .beginner, type: .bay),
    KiteSpot(id: "keremma-112", name: "Keremma - Baie de Goulven", latitude: 48.645328, longitude: -4.287931,
             orientation: "W,NW", level: .intermediate, type: .bay),
    KiteSpot(id: "saint-lunaire-113", name: "Saint-Lunaire - Plage de Longchamps", latitude: 48.639746, longitude: -2.124124,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "mont-saint-michel-114", name: "Mont-Saint-Michel - Baie", latitude: 48.634095, longitude: -1.508873,
             orientation: "NW,W", level: .intermediate, type: .bay),
    KiteSpot(id: "penn-ar-strejou-115", name: "Penn ar Stréjou - Grève Blanche", latitude: 48.632859, longitude: -4.529704,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-cast-le-guildo-116", name: "Saint-Cast-le-Guildo - Grande Plage", latitude: 48.629514, longitude: -2.246048,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "les-gobelains-117", name: "Les Gobelains", latitude: 48.624241, longitude: -2.819804,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "caroual-118", name: "Caroual", latitude: 48.622209, longitude: -2.485605,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "hirel-119", name: "Hirel", latitude: 48.614705, longitude: -1.798116,
             orientation: "NW,W,E", level: .intermediate, type: .beach),
    KiteSpot(id: "cherrueix-120", name: "Cherrueix", latitude: 48.612662, longitude: -1.712968,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "lancieux-121", name: "Lancieux - Plage Saint-Sieuc", latitude: 48.610900, longitude: -2.159069,
             orientation: "WNW,W,NNE", level: .beginner, type: .beach),
    KiteSpot(id: "saint-pabu-122", name: "Saint-Pabu", latitude: 48.610149, longitude: -2.497141,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-jacut-de-la-mer-123", name: "Saint-Jacut-de-la-Mer - Plage du Rougeret", latitude: 48.609001, longitude: -2.187341,
             orientation: "N,NE", level: .beginner, type: .beach),
    KiteSpot(id: "plougastel-daoulas-124", name: "Plougastel-Daoulas - Plage de Plougouri", latitude: 48.606366, longitude: -4.603642,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "binic-125", name: "Binic - Plage de l’Avant-Port", latitude: 48.604107, longitude: -2.817816,
             orientation: "NE,ENE,E", level: .intermediate, type: .beach),
    KiteSpot(id: "pleneuf-val-andre-126", name: "Pléneuf-Val-André - Plage des Vallées", latitude: 48.603554, longitude: -2.536940,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "landeda-127", name: "Landéda - Plage de l'Aber Vrac'h", latitude: 48.598901, longitude: -4.564040,
             orientation: "N,NNE,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "sainte-marguerite-128", name: "Sainte-Marguerite", latitude: 48.594028, longitude: -4.609607,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "pleneuf-val-andre-129", name: "Pléneuf-Val-André", latitude: 48.591992, longitude: -2.560601,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-pabu-130", name: "Saint-Pabu - Plage Corn ar Gazel", latitude: 48.577447, longitude: -4.620417,
             orientation: "NE", level: .beginner, type: .beach),
    KiteSpot(id: "lampaul-ploudalmezeau-131", name: "Lampaul-Ploudalmézeau - Plage des Trois Moutons", latitude: 48.574065, longitude: -4.652791,
             orientation: "NE,W", level: .beginner, type: .beach),
    KiteSpot(id: "treompan-132", name: "Treompan", latitude: 48.572582, longitude: -4.677212,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "plerin-133", name: "Plérin - Plage des Rosaires", latitude: 48.569551, longitude: -2.758294,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-suliac-134", name: "Saint-Suliac", latitude: 48.568253, longitude: -1.976006,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "morieux-135", name: "Morieux - Plage de Saint-Maurice", latitude: 48.527720, longitude: -2.634666,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "hillion-136", name: "Hillion - Plage Bon Abri", latitude: 48.527683, longitude: -2.650437,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "plobsheim-137", name: "Plobsheim - Base nautique de Plobsheim", latitude: 48.476461, longitude: 7.754381,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "brest-138", name: "Brest - Plage du Moulin Blanc", latitude: 48.395987, longitude: -4.424651,
             orientation: "S,SW", level: .beginner, type: .beach),
    KiteSpot(id: "le-conquet-139", name: "Le Conquet - Plage des Blancs Sablons", latitude: 48.371626, longitude: -4.770898,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "porsmilin-portez-140", name: "Porsmilin (Portez)", latitude: 48.353681, longitude: -4.680139,
             orientation: "SE", level: .advanced, type: .beach),
    KiteSpot(id: "le-trez-hir-141", name: "Le Trez Hir", latitude: 48.347145, longitude: -4.700754,
             orientation: "SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "plougastel-daoulas-142", name: "Plougastel-Daoulas - Porz Kerzit", latitude: 48.324781, longitude: -4.393505,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "camaret-sur-mer-143", name: "Camaret-sur-Mer - Plage de Pen Hat", latitude: 48.272240, longitude: -4.624955,
             orientation: "W,NW", level: .advanced, type: .beach),
    KiteSpot(id: "crozon-144", name: "Crozon - Plage de Kersiguénou", latitude: 48.251678, longitude: -4.556928,
             orientation: "SW,S", level: .intermediate, type: .beach),
    KiteSpot(id: "crozon-145", name: "Crozon - Plage de Goulien", latitude: 48.244934, longitude: -4.552720,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "crozon-146", name: "Crozon - Plage de l'Aber", latitude: 48.229969, longitude: -4.440479,
             orientation: "S,SE,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "crozon-147", name: "Crozon - Plage de Morgat", latitude: 48.229690, longitude: -4.498504,
             orientation: "S,SW,SE", level: .beginner, type: .beach),
    KiteSpot(id: "telgruc-sur-mer-148", name: "Telgruc-sur-Mer - Plage de Trez-Bellec", latitude: 48.212998, longitude: -4.377675,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "crozon-149", name: "Crozon - Plage de la Palue", latitude: 48.203247, longitude: -4.556753,
             orientation: "E,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "pentrez-150", name: "Pentrez", latitude: 48.188443, longitude: -4.304751,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "plonevez-porzay-151", name: "Plonévez-Porzay - Plage de Kervel", latitude: 48.114385, longitude: -4.286608,
             orientation: "NW,W,SW,N", level: .beginner, type: .beach),
    KiteSpot(id: "saint-tugen-152", name: "Saint-Tugen", latitude: 48.011915, longitude: -4.596273,
             orientation: "W,WNW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "audierne-153", name: "Audierne", latitude: 48.009931, longitude: -4.549991,
             orientation: "SW", level: .beginner, type: .beach),
    KiteSpot(id: "kersiny-154", name: "Kersiny", latitude: 48.004873, longitude: -4.513863,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "mesperleuc-155", name: "Mesperleuc", latitude: 47.999331, longitude: -4.499922,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "pouldreuzic-156", name: "Pouldreuzic - Plage de Penhors", latitude: 47.936498, longitude: -4.404452,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "kerleven-157", name: "Kerleven", latitude: 47.894839, longitude: -3.965287,
             orientation: "SW,S,SE", level: .beginner, type: .beach),
    KiteSpot(id: "benodet-158", name: "Bénodet - Lagune du Letty", latitude: 47.864156, longitude: -4.078998,
             orientation: "S,SSE,SSW,SW", level: .beginner, type: .lagoon, tidePreference: .highOnly),
    KiteSpot(id: "ile-tudy-161", name: "Île-Tudy", latitude: 47.846886, longitude: -4.161789,
             orientation: "S,SW,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "penmarch-162", name: "Penmarch - Plage de la Torche", latitude: 47.843965, longitude: -4.351242,
             orientation: "W,SW", level: .intermediate, type: .beach, tidePreference: .avoidLow),
    KiteSpot(id: "penmarch-163", name: "Penmarch - Plage de Pors Carn", latitude: 47.831244, longitude: -4.354932,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "kersidan-164", name: "Kersidan", latitude: 47.794824, longitude: -3.821426,
             orientation: "W,WSW", level: .beginner, type: .beach),
    KiteSpot(id: "treffiagat-165", name: "Treffiagat - Plage du Reun", latitude: 47.791330, longitude: -4.240789,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "guidel-166", name: "Guidel - Plage de la Falaise", latitude: 47.763755, longitude: -3.528089,
             orientation: "S,SW,SE", level: .beginner, type: .beach),
    KiteSpot(id: "le-fort-bloque-167", name: "Le Fort Bloqué - Plage de Pen er Malo", latitude: 47.740134, longitude: -3.505267,
             orientation: "W,NW", level: .beginner, type: .beach, tidePreference: .avoidLow),
    KiteSpot(id: "locmiquelic-168", name: "Locmiquélic - Plage du Loch", latitude: 47.717917, longitude: -3.343636,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "riantec-169", name: "Riantec", latitude: 47.706045, longitude: -3.332434,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "larmor-plage-170", name: "Larmor-Plage - Plage de Toulhars", latitude: 47.703825, longitude: -3.381244,
             orientation: "NE,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "riantec-171", name: "Riantec - Ile de Kerner", latitude: 47.703548, longitude: -3.320039,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "kerguelen-172", name: "Kerguélen", latitude: 47.701876, longitude: -3.402139,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "gavres-173", name: "Gâvres - Plage de Goêrem", latitude: 47.696257, longitude: -3.356318,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "gavres-174", name: "Gâvres - Petite Mer de Gâvres", latitude: 47.696043, longitude: -3.307761,
             orientation: "W,SW,S", level: .beginner, type: .beach),
    KiteSpot(id: "gavres-175", name: "Gâvres - Grande Plage Gâvres Océan", latitude: 47.692458, longitude: -3.335538,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "plouhinec-176", name: "Plouhinec - Plage du Linès", latitude: 47.682155, longitude: -3.285726,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "etel-177", name: "Étel - Pointe Pradic", latitude: 47.652112, longitude: -3.207121,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "etel-178", name: "Étel - Barre d'Étel", latitude: 47.642292, longitude: -3.212561,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "sene-179", name: "Séné - Plage du Ruello", latitude: 47.600643, longitude: -2.736285,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "baden-180", name: "Baden - Plage de Toulindac", latitude: 47.598353, longitude: -2.870557,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "ile-darz-181", name: "Île-d’Arz - Plage de Brouel", latitude: 47.582855, longitude: -2.815636,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "carnac-182", name: "Carnac - Grande Plage / Les Men Du", latitude: 47.576238, longitude: -3.048787,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "quiberon-183", name: "Quiberon - Penthièvre / Plage du Mané Guen", latitude: 47.575404, longitude: -3.148492,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "plouharnel-184", name: "Plouharnel - Plage des Sables Blancs", latitude: 47.572365, longitude: -3.117562,
             orientation: "E,NE,SE", level: .beginner, type: .beach),
    KiteSpot(id: "carnac-185", name: "Carnac - La Grande Plage", latitude: 47.570019, longitude: -3.073630,
             orientation: "SW,S,SE", level: .beginner, type: .beach),
    KiteSpot(id: "carnac-186", name: "Carnac - Plage de Saint Colomban", latitude: 47.569197, longitude: -3.099685,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "carnac-187", name: "Carnac - Plage de Ty Bihan", latitude: 47.563849, longitude: -3.092487,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "locmariaquer-188", name: "Locmariaquer - Plage Saint Pierre", latitude: 47.556931, longitude: -2.970404,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-pierre-quiberon-189", name: "Saint-Pierre-Quiberon - Penthièvre Lagon", latitude: 47.551197, longitude: -3.123456,
             orientation: "W,SW", level: .beginner, type: .lagoon, tidePreference: .highOnly),
    KiteSpot(id: "saint-pierre-quiberon-190", name: "Saint-Pierre-Quiberon - Plage de Penthièvre", latitude: 47.549501, longitude: -3.136894,
             orientation: "E,NE,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-pierre-quiberon-191", name: "Saint-Pierre-Quiberon - Plage de Kermahé", latitude: 47.519410, longitude: -3.124912,
             orientation: "E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "damgan-192", name: "Damgan", latitude: 47.517011, longitude: -2.588710,
             orientation: "W,SW,WSW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-gildas-de-rhuys-193", name: "Saint-Gildas-de-Rhuys - Plage du Goh velin", latitude: 47.514787, longitude: -2.851169,
             orientation: "S,W", level: .beginner, type: .beach),
    KiteSpot(id: "sarzeau-194", name: "Sarzeau - Plage du Landrezac", latitude: 47.503077, longitude: -2.708883,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "sarzeau-195", name: "Sarzeau - Plage du Roaliguen", latitude: 47.496823, longitude: -2.768744,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "sarzeau-196", name: "Sarzeau - Petite plage de Penvins", latitude: 47.495194, longitude: -2.679570,
             orientation: "SW,W", level: .beginner, type: .beach),
    KiteSpot(id: "penestin-197", name: "Pénestin - Plage de la Mine d’Or", latitude: 47.482002, longitude: -2.497984,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "quiberon-198", name: "Quiberon - La Grande Plage", latitude: 47.477307, longitude: -3.118549,
             orientation: "E,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "asserac-199", name: "Assérac - Plage de Pont-Mahé", latitude: 47.442259, longitude: -2.454525,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "mesquer-200", name: "Mesquer - Plage de Sorlock", latitude: 47.418621, longitude: -2.471858,
             orientation: "N,W", level: .intermediate, type: .beach),
    KiteSpot(id: "mesquer-201", name: "Mesquer - Port du Toul Ru", latitude: 47.414146, longitude: -2.481183,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "ile-dhouat-202", name: "Île-d’Houat - Point d’En Tal", latitude: 47.390890, longitude: -2.941101,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "ile-dhouat-203", name: "Île-d’Houat - Tréac’h er Gourèd", latitude: 47.387355, longitude: -2.950693,
             orientation: "E,ENE,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "ile-dhouat-204", name: "Île-d’Houat - Tréac’h Salus", latitude: 47.382355, longitude: -2.957671,
             orientation: "SW,W,S", level: .beginner, type: .beach),
    KiteSpot(id: "la-turballe-205", name: "La Turballe - Plage de Pen Bron", latitude: 47.326602, longitude: -2.506504,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "locmaria-206", name: "Locmaria - Plage des Grands Sables", latitude: 47.316263, longitude: -3.098181,
             orientation: "N,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "le-croisic-207", name: "Le Croisic - Baie de Saint-Goustan", latitude: 47.304756, longitude: -2.524682,
             orientation: "W,NW", level: .beginner, type: .bay),
    KiteSpot(id: "la-baule-208", name: "La Baule - Baie", latitude: 47.276661, longitude: -2.395786,
             orientation: "W,SW", level: .beginner, type: .bay),
    KiteSpot(id: "batz-sur-mer-209", name: "Batz-sur-Mer - Plage de la Govelle", latitude: 47.264751, longitude: -2.458941,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "pornichet-210", name: "Pornichet - Plage des Libraires", latitude: 47.263673, longitude: -2.350087,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "pornichet-211", name: "Pornichet - Bonne Source", latitude: 47.247947, longitude: -2.334686,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-brevin-les-pins-212", name: "Saint-Brévin-les-Pins - Plage principale", latitude: 47.244300, longitude: -2.172900,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-brevin-les-pins-213", name: "Saint-Brevin-les-Pins - Plage du Pointeau", latitude: 47.236148, longitude: -2.185241,
             orientation: "SW,S", level: .beginner, type: .beach),
    KiteSpot(id: "saint-marc-sur-mer-214", name: "Saint-Marc-sur-Mer", latitude: 47.235796, longitude: -2.281295,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-brevin-les-pins-215", name: "Saint-Brevin-les-Pins - Plage des Rochelets", latitude: 47.214488, longitude: -2.174059,
             orientation: "W", level: .beginner, type: .beach),
    KiteSpot(id: "saint-brevin-les-pins-216", name: "Saint-Brevin-les-Pins - Plage de l’Ermitage", latitude: 47.203033, longitude: -2.165227,
             orientation: "NW", level: .intermediate, type: .beach),
    KiteSpot(id: "tharon-217", name: "Tharon", latitude: 47.168306, longitude: -2.170425,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "prefailles-pointe-de-st-g-218", name: "Préfailles (Pointe de St.-Gildas) - Plage de l’Anse du Sud", latitude: 47.130925, longitude: -2.241238,
             orientation: "N,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "ile-de-noirmoutier-219", name: "Île de Noirmoutier - Plage des Sableaux", latitude: 46.992708, longitude: -2.215135,
             orientation: "NE,E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "ile-de-noirmoutier-220", name: "Île de Noirmoutier - Pointe de la Fosse", latitude: 46.897415, longitude: -2.145111,
             orientation: "N,NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "fromentine-221", name: "Fromentine", latitude: 46.892815, longitude: -2.144189,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "la-tranche-sur-mer-222", name: "La Tranche-sur-Mer - Plage centrale / Terrière", latitude: 46.354984, longitude: -1.480693,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "excenevex-223", name: "Excenevex", latitude: 46.351836, longitude: 6.359537,
             orientation: "N,NNE,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "la-tranche-sur-mer-224", name: "La Tranche-sur-Mer - Grande Plage", latitude: 46.341818, longitude: -1.431425,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "chens-sur-leman-225", name: "Chens-sur-Léman - Plage de Tougues", latitude: 46.323890, longitude: 6.255521,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "la-rochelle-226", name: "La Rochelle - Plage des Minimes", latitude: 46.140082, longitude: -1.174627,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "aytre-227", name: "Aytre", latitude: 46.119002, longitude: -1.127365,
             orientation: "SW,W", level: .beginner, type: .beach),
    KiteSpot(id: "chatelaillon-plage-228", name: "Châtelaillon-Plage", latitude: 46.070631, longitude: -1.096749,
             orientation: "NW,SW,N,S", level: .beginner, type: .beach),
    KiteSpot(id: "la-tremblade-229", name: "La Tremblade - Plage du Galon d’Or", latitude: 45.796792, longitude: -1.201769,
             orientation: "NE,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "la-tremblade-230", name: "La Tremblade - Plage de l’Embellie", latitude: 45.794526, longitude: -1.216192,
             orientation: "NW,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "la-tremblade-231", name: "La Tremblade - Plage de La Pointe Espagnole", latitude: 45.782391, longitude: -1.249289,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "la-tremblade-232", name: "La Tremblade - Plage de La Bouverie", latitude: 45.736999, longitude: -1.244520,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "la-tremblade-233", name: "La Tremblade - Plage de la Coubre", latitude: 45.695855, longitude: -1.238746,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "la-palmyre-234", name: "La Palmyre - Plage de La Bonne Anse", latitude: 45.685306, longitude: -1.189319,
             orientation: "SW,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "lac-du-bourget-235", name: "Lac du Bourget - Plage du Lido", latitude: 45.667895, longitude: 5.892619,
             orientation: "N,NW", level: .intermediate, type: .lake),
    KiteSpot(id: "lac-du-bourget-236", name: "Lac du Bourget - Camping Île aux Cygnes", latitude: 45.656756, longitude: 5.866122,
             orientation: "SW,S", level: .beginner, type: .lake),
    KiteSpot(id: "saint-palais-sur-mer-237", name: "Saint-Palais-sur-Mer - Plage de La Grande Côte", latitude: 45.653071, longitude: -1.128862,
             orientation: "S,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "lac-du-bourget-238", name: "Lac du Bourget - Base de Loisirs des Mottets", latitude: 45.651743, longitude: 5.889923,
             orientation: "W,NW", level: .beginner, type: .lake),
    KiteSpot(id: "royan-239", name: "Royan", latitude: 45.615728, longitude: -1.016738,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "saint-georges-de-didonne-240", name: "Saint-Georges-de-Didonne", latitude: 45.591647, longitude: -0.993568,
             orientation: "E,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "le-verdon-sur-mer-241", name: "Le Verdon-sur-Mer - Plage Océane", latitude: 45.569744, longitude: -1.084595,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "le-verdon-sur-mer-242", name: "Le Verdon-sur-Mer - Plage de la Chambrette", latitude: 45.548107, longitude: -1.052413,
             orientation: "E,NE,N", level: .beginner, type: .beach),
    KiteSpot(id: "soulac-sur-mer-243", name: "Soulac-sur-Mer - Plage de Soulac", latitude: 45.511925, longitude: -1.135156,
             orientation: "E,SE", level: .intermediate, type: .lake),
    KiteSpot(id: "le-gurp-244", name: "Le Gurp", latitude: 45.435072, longitude: -1.155419,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "montalivet-245", name: "Montalivet", latitude: 45.380827, longitude: -1.162063,
             orientation: "NW,N", level: .beginner, type: .beach),
    KiteSpot(id: "hourtin-plage-246", name: "Hourtin Plage - Plage Centrale", latitude: 45.222812, longitude: -1.174585,
             orientation: "NW,SW,N", level: .beginner, type: .beach),
    KiteSpot(id: "lac-dhourtin-247", name: "Lac d’Hourtin - Plage du Port d’Hourtin", latitude: 45.177135, longitude: -1.088457,
             orientation: "S,SW", level: .beginner, type: .lake),
    KiteSpot(id: "lac-dhourtin-248", name: "Lac d’Hourtin - Plage de Lachanau", latitude: 45.163613, longitude: -1.078848,
             orientation: "S,SW", level: .beginner, type: .lake),
    KiteSpot(id: "carcans-plage-249", name: "Carcans Plage - Plage Océane", latitude: 45.082570, longitude: -1.195859,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "lacanau-ocean-250", name: "Lacanau Océan - Plage Centrale", latitude: 45.001833, longitude: -1.205462,
             orientation: "NW,W", level: .intermediate, type: .lake),
    KiteSpot(id: "lac-de-lacanau-251", name: "Lac de Lacanau - Plage du Moutchic", latitude: 45.001232, longitude: -1.131668,
             orientation: "E,SE", level: .beginner, type: .lake),
    KiteSpot(id: "lac-de-lacanau-252", name: "Lac de Lacanau - Plage à Gaston de Lacanau", latitude: 44.980244, longitude: -1.100368,
             orientation: "NW,W,SW", level: .beginner, type: .lake),
    KiteSpot(id: "le-porge-ocean-253", name: "Le Porge Océan", latitude: 44.895880, longitude: -1.220939,
             orientation: "NW,W,N", level: .intermediate, type: .beach),
    KiteSpot(id: "le-grand-crohot-254", name: "Le Grand Crohot", latitude: 44.795761, longitude: -1.237367,
             orientation: "NW,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "claquey-255", name: "Claquey - Dune des Journalistes", latitude: 44.746588, longitude: -1.170689,
             orientation: "NE,W", level: .beginner, type: .beach),
    KiteSpot(id: "andernos-les-bains-256", name: "Andernos-les-Bains - Plage du Betey", latitude: 44.732702, longitude: -1.092709,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "le-truc-vert-257", name: "Le Truc Vert", latitude: 44.715437, longitude: -1.253958,
             orientation: "SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "gujan-mestras-258", name: "Gujan-Mestras - Plage de La Hume", latitude: 44.647458, longitude: -1.114870,
             orientation: "SW,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "arcachon-259", name: "Arcachon - Plage des Arbousiers", latitude: 44.647321, longitude: -1.200711,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "cap-ferret-260", name: "Cap Ferret - Plage Ouest", latitude: 44.635353, longitude: -1.263052,
             orientation: "E,NW,SW", level: .beginner, type: .beach),
    KiteSpot(id: "la-teste-du-buch-261", name: "La Teste-du-Buch - Plage de Pyla sur Mer", latitude: 44.631690, longitude: -1.205800,
             orientation: "W,SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "dune-du-pyla-262", name: "Dune du Pyla - Plage de la Corniche", latitude: 44.596202, longitude: -1.215792,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "la-teste-de-buch-263", name: "La Teste-de-Buch - Plage du Petit Nice", latitude: 44.561168, longitude: -1.241759,
             orientation: "W,NW,SW", level: .beginner, type: .beach),
    KiteSpot(id: "cazaux-264", name: "Cazaux - Plage de Cazaux-Lac", latitude: 44.524802, longitude: -1.169940,
             orientation: "N,NW", level: .beginner, type: .beach),
    KiteSpot(id: "la-teste-de-buch-265", name: "La Teste-de-Buch - La Salie", latitude: 44.518172, longitude: -1.257841,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "sanguinet-266", name: "Sanguinet - Plage des Aigrettes", latitude: 44.496109, longitude: -1.091990,
             orientation: "SW,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "sanguinet-267", name: "Sanguinet - Plage du port de l’Estey", latitude: 44.483779, longitude: -1.103776,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "biscarrosse-plage-268", name: "Biscarrosse Plage - Plage du Vivier", latitude: 44.454069, longitude: -1.258481,
             orientation: "SW,W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "biscarrosse-269", name: "Biscarrosse - Plage de Mayotte", latitude: 44.440221, longitude: -1.161681,
             orientation: "SW,W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "biscarrosse-270", name: "Biscarrosse - Plage du port de Navarrosse", latitude: 44.435117, longitude: -1.167448,
             orientation: "N,NW", level: .beginner, type: .beach),
    KiteSpot(id: "mimizan-271", name: "Mimizan - Plage Nord", latitude: 44.232361, longitude: -1.297365,
             orientation: "NW,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "mimizan-272", name: "Mimizan - Plage de la Garluche", latitude: 44.214251, longitude: -1.301189,
             orientation: "S,SW,N,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "moliets-et-maa-273", name: "Moliets-et-Maa - Plage de Moliets", latitude: 43.854672, longitude: -1.395111,
             orientation: "SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "seignosse-274", name: "Seignosse - Plage du Penon", latitude: 43.711336, longitude: -1.440290,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "seignosse-275", name: "Seignosse - Plage des Estagnots", latitude: 43.687282, longitude: -1.444712,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "soorts-hossegor-276", name: "Soorts-Hossegor - Plage de la Gravière", latitude: 43.672168, longitude: -1.445240,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-laurent-du-var-277", name: "Saint-Laurent-du-Var - Plage Cousteau", latitude: 43.655615, longitude: 7.196372,
             orientation: "E,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "capbreton-278", name: "Capbreton - Plage des Océanides", latitude: 43.638216, longitude: -1.458346,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "antibes-279", name: "Antibes - Plage de la Salis", latitude: 43.570680, longitude: 7.129912,
             orientation: "E,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "la-grande-motte-280", name: "La Grande-Motte - Plage du Grands Travers", latitude: 43.556154, longitude: 4.039061,
             orientation: "SW,NW", level: .beginner, type: .beach),
    KiteSpot(id: "la-grande-motte-281", name: "La Grande-Motte - Plage du Couchant", latitude: 43.555599, longitude: 4.074336,
             orientation: "SE,S", level: .intermediate, type: .beach),
    KiteSpot(id: "le-grau-du-roi-282", name: "Le Grau-du-Roi - Plage du Boucanet", latitude: 43.541262, longitude: 4.128570,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "saint-chamas-283", name: "Saint-Chamas - La Digue", latitude: 43.539282, longitude: 5.030308,
             orientation: "NW,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "mauguio-284", name: "Mauguio - Plage des Roquilles", latitude: 43.537823, longitude: 3.971408,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "cannes-285", name: "Cannes - Plage Gazagnaire", latitude: 43.537161, longitude: 7.039919,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "tarnos-286", name: "Tarnos - Plage de la Digue", latitude: 43.535361, longitude: -1.523641,
             orientation: "E,NE", level: .beginner, type: .beach),
    KiteSpot(id: "mandelieu-la-napoule-287", name: "Mandelieu-la-Napoule - Plage du Sable d’Or", latitude: 43.532777, longitude: 6.950907,
             orientation: "SW,W", level: .beginner, type: .beach),
    KiteSpot(id: "le-grau-du-roi-288", name: "Le Grau-du-Roi - Plage Rive Gauche", latitude: 43.529827, longitude: 4.134964,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "anglet-289", name: "Anglet - Plage des Cavaliers", latitude: 43.523016, longitude: -1.530151,
             orientation: "E,NE", level: .intermediate, type: .beach),
    KiteSpot(id: "palavas-les-flots-290", name: "Palavas-les-Flots - Plage de Palavas", latitude: 43.521288, longitude: 3.928742,
             orientation: "NW", level: .beginner, type: .beach),
    KiteSpot(id: "villeneuve-les-maguelone-291", name: "Villeneuve-lès-Maguelone - Plage Palavas-les-Flots", latitude: 43.515754, longitude: 3.909284,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "le-grau-du-roi-port-camar-292", name: "Le Grau-du-Roi (Port Camargue) - Plage de l'Espiguette", latitude: 43.515661, longitude: 4.120081,
             orientation: "NW,SE,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "anglet-293", name: "Anglet - Plage de la Madrague", latitude: 43.513398, longitude: -1.537462,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "anglet-294", name: "Anglet - Plage de Marinella", latitude: 43.505940, longitude: -1.542246,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "anglet-295", name: "Anglet - Plage de la Chambre d'Amour", latitude: 43.497967, longitude: -1.548022,
             orientation: "W,WNW", level: .intermediate, type: .beach),
    KiteSpot(id: "le-grau-du-roi-296", name: "Le Grau-du-Roi - Plage de l’Espiguette", latitude: 43.485545, longitude: 4.117289,
             orientation: "NW,W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "saintes-maries-de-la-mer-297", name: "Saintes-Maries-de-la-Mer - Plage Est", latitude: 43.453935, longitude: 4.470969,
             orientation: "SW,S,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "saintes-maries-de-la-mer-298", name: "Saintes-Maries-de-la-Mer - Plage Ouest", latitude: 43.446826, longitude: 4.413105,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "frontignan-299", name: "Frontignan - Étang d’Ingril", latitude: 43.443574, longitude: 3.788149,
             orientation: "W,NW", level: .beginner, type: .lake),
    KiteSpot(id: "bidart-300", name: "Bidart - Plage du Centre", latitude: 43.438503, longitude: -1.598336,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "bidart-301", name: "Bidart - Plage de l'Uhabia", latitude: 43.434778, longitude: -1.604067,
             orientation: "SW,S,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "frontignan-302", name: "Frontignan", latitude: 43.432174, longitude: 3.781012,
             orientation: "SW,NW", level: .beginner, type: .beach),
    KiteSpot(id: "marignane-303", name: "Marignane - Plage du Jai", latitude: 43.431014, longitude: 5.162793,
             orientation: "N,NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "fos-sur-mer-304", name: "Fos-sur-Mer - Plage du Cavaou", latitude: 43.426736, longitude: 4.925054,
             orientation: "SE,E", level: .intermediate, type: .beach),
    KiteSpot(id: "frejus-305", name: "Fréjus - Plage Caouanne", latitude: 43.417357, longitude: 6.748028,
             orientation: "S,SW,E", level: .beginner, type: .beach),
    KiteSpot(id: "meze-306", name: "Mèze - Conque", latitude: 43.416797, longitude: 3.594563,
             orientation: "N,NW", level: .beginner, type: .beach),
    KiteSpot(id: "frejus-307", name: "Fréjus - Plage du Pacha", latitude: 43.410710, longitude: 6.740329,
             orientation: "SW,S", level: .beginner, type: .beach),
    KiteSpot(id: "beauduc-308", name: "Beauduc - Plage de Beauduc", latitude: 43.408485, longitude: 4.587199,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "erromardie-309", name: "Erromardie", latitude: 43.408164, longitude: -1.641701,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "frejus-310", name: "Fréjus - Plage des Esclamandes", latitude: 43.406235, longitude: 6.735340,
             orientation: "S,SE,SW", level: .beginner, type: .beach),
    KiteSpot(id: "sete-311", name: "Sète - Étang de Thau - Pont Levis", latitude: 43.402407, longitude: 3.654487,
             orientation: "NW", level: .intermediate, type: .lake),
    KiteSpot(id: "saint-jean-de-luz-312", name: "Saint-Jean-de-Luz - Plage Flots Bleus", latitude: 43.397246, longitude: -1.662665,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "port-saint-louis-du-rhone-313", name: "Port-Saint-Louis-du-Rhône - Plage Olga", latitude: 43.393955, longitude: 4.859649,
             orientation: "NW,N", level: .intermediate, type: .beach),
    KiteSpot(id: "ciboure-314", name: "Ciboure", latitude: 43.391086, longitude: -1.678246,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "sete-315", name: "Sète - Plage du Lido", latitude: 43.388502, longitude: 3.653191,
             orientation: "S,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "port-saint-louis-du-rhone-316", name: "Port-Saint-Louis-du-Rhône - Plage de Carteau", latitude: 43.384374, longitude: 4.854917,
             orientation: "NW,W", level: .beginner, type: .beach),
    KiteSpot(id: "hendaye-317", name: "Hendaye", latitude: 43.378231, longitude: -1.780905,
             orientation: "NE,N", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: true),
    KiteSpot(id: "sete-318", name: "Sète - Plage des 3 Digues", latitude: 43.367221, longitude: 3.619888,
             orientation: "S,SW", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "martigues-319", name: "Martigues - Plage des Renaires", latitude: 43.363590, longitude: 5.011045,
             orientation: "N,NW", level: .beginner, type: .beach),
    KiteSpot(id: "marseillan-320", name: "Marseillan - Étang de Thau - Marseillan", latitude: 43.341221, longitude: 3.536437,
             orientation: "NW,W", level: .beginner, type: .lake),
    KiteSpot(id: "roquebrune-sur-argens-321", name: "Roquebrune-sur-Argens - Plage de l’Arpillon", latitude: 43.340546, longitude: 6.696162,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "port-saint-louis-du-rhone-322", name: "Port-Saint-Louis-du-Rhône - Plage Napoléon", latitude: 43.335357, longitude: 4.884932,
             orientation: "N,NE,E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "arles-323", name: "Arles - Plage de Piémanson", latitude: 43.330998, longitude: 4.810491,
             orientation: "S,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "sausset-les-pins-324", name: "Sausset-les-Pins - Plage des Beaumettes", latitude: 43.327985, longitude: 5.135180,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "sainte-maxime-325", name: "Sainte-Maxime - Plage de la Nartelle", latitude: 43.322458, longitude: 6.667256,
             orientation: "NW", level: .beginner, type: .beach),
    KiteSpot(id: "grimaud-326", name: "Grimaud - Plage de Beauvallon", latitude: 43.286476, longitude: 6.604173,
             orientation: "SW,S,ESE,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "agde-327", name: "Agde - Plage de la Tamarissière", latitude: 43.284127, longitude: 3.440647,
             orientation: "SE,S,W", level: .intermediate, type: .beach),
    KiteSpot(id: "cap-dagde-328", name: "Cap d’Agde - Plage Richelieu", latitude: 43.273554, longitude: 3.498402,
             orientation: "SE,S", level: .intermediate, type: .beach),
    KiteSpot(id: "serignan-329", name: "Sérignan", latitude: 43.267687, longitude: 3.342396,
             orientation: "S,SE,SW", level: .beginner, type: .beach),
    KiteSpot(id: "marseille-330", name: "Marseille - Plage de Bonneveine", latitude: 43.253574, longitude: 5.371598,
             orientation: "SW,S", level: .intermediate, type: .beach),
    KiteSpot(id: "valras-plage-331", name: "Valras-Plage", latitude: 43.232941, longitude: 3.270973,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "ramatuelle-332", name: "Ramatuelle - Plage de la Pampelonne", latitude: 43.226287, longitude: 6.671933,
             orientation: "E,NE", level: .beginner, type: .beach),
    KiteSpot(id: "ramatuelle-333", name: "Ramatuelle - Plage de Pampelonne (Gros Vallat)", latitude: 43.213641, longitude: 6.667925,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "la-ciotat-334", name: "La Ciotat - Plage d’Arène Cros", latitude: 43.187474, longitude: 5.649804,
             orientation: "SE", level: .intermediate, type: .beach),
    KiteSpot(id: "la-ciotat-335", name: "La Ciotat - Grande plage", latitude: 43.184990, longitude: 5.624292,
             orientation: "SE,S", level: .intermediate, type: .beach),
    KiteSpot(id: "la-croix-valmer-336", name: "La Croix-Valmer - Plage de Gigaro", latitude: 43.182235, longitude: 6.592672,
             orientation: "NW,N", level: .intermediate, type: .beach),
    KiteSpot(id: "fleury-337", name: "Fleury - Plage de Saint-Pierre-la-Mer", latitude: 43.177327, longitude: 3.194202,
             orientation: "NW,N", level: .beginner, type: .beach),
    KiteSpot(id: "saint-cyr-sur-mer-338", name: "Saint-Cyr-sur-Mer - Plage des Lecques", latitude: 43.173843, longitude: 5.688735,
             orientation: "S,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "le-lavandou-339", name: "Le Lavandou - Plage de Cavalière", latitude: 43.148926, longitude: 6.425627,
             orientation: "E,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "le-lavandou-340", name: "Le Lavandou - Plage de Saint-Clair", latitude: 43.141267, longitude: 6.383616,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "etang-de-bages-sigean-341", name: "Étang de Bages-Sigean - La Nautique", latitude: 43.135861, longitude: 3.013703,
             orientation: "NW,N", level: .intermediate, type: .lake),
    KiteSpot(id: "sanary-sur-mer-342", name: "Sanary-sur-Mer - Plage du Lido", latitude: 43.135293, longitude: 5.774233,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "le-lavandou-343", name: "Le Lavandou - Plage du Lavandou", latitude: 43.131312, longitude: 6.368287,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "gruissan-344", name: "Gruissan - Les Ayguades", latitude: 43.128856, longitude: 3.142570,
             orientation: "NW,W", level: .beginner, type: .beach, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "hyeres-345", name: "Hyères - Plage des Salins", latitude: 43.114339, longitude: 6.204876,
             orientation: "E", level: .intermediate, type: .beach),
    KiteSpot(id: "la-londe-les-maures-346", name: "La-Londe-les-Maures - Plage Miramar", latitude: 43.113231, longitude: 6.243159,
             orientation: "E,SE,ESE", level: .beginner, type: .beach),
    KiteSpot(id: "six-four-les-plages-347", name: "Six-Four-les-Plages - Plage de Bonnegrâce", latitude: 43.112081, longitude: 5.808172,
             orientation: "W,NW,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "hyeres-348", name: "Hyères - Plage du Mérou", latitude: 43.105819, longitude: 6.183521,
             orientation: "E", level: .beginner, type: .beach),
    KiteSpot(id: "hyeres-349", name: "Hyères - Plage de l’Ayguade", latitude: 43.102202, longitude: 6.178745,
             orientation: "E", level: .beginner, type: .beach),
    KiteSpot(id: "bormes-les-mimosas-350", name: "Bormes-les-Mimosas - Plage de Cabasson", latitude: 43.099698, longitude: 6.323350,
             orientation: "NW,N", level: .intermediate, type: .beach),
    KiteSpot(id: "gruissan-351", name: "Gruissan - Plage des Chalets", latitude: 43.097591, longitude: 3.115636,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "bormes-les-mimosas-352", name: "Bormes-les-Mimosas - Plage de Brégançon", latitude: 43.095236, longitude: 6.323952,
             orientation: "NW,N", level: .advanced, type: .beach),
    KiteSpot(id: "six-fours-les-plages-353", name: "Six-Fours-les-Plages - Plage de la Coudoulière", latitude: 43.094590, longitude: 5.807873,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "six-four-les-plages-354", name: "Six-Four-les-Plages - Le Brusc", latitude: 43.080386, longitude: 5.802628,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "la-seyne-sur-mer-355", name: "La Seyne-sur-Mer - Plage des Sablettes", latitude: 43.075450, longitude: 5.892884,
             orientation: "NE,E", level: .intermediate, type: .beach),
    KiteSpot(id: "hyeres-356", name: "Hyères - Plage des Pesquiers", latitude: 43.067185, longitude: 6.153469,
             orientation: "E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "etang-de-bages-sigean-357", name: "Étang de Bages-Sigean - Port Mahon", latitude: 43.060474, longitude: 3.003864,
             orientation: "NW,W", level: .beginner, type: .lake),
    KiteSpot(id: "hyeres-358", name: "Hyères - Plage de l’Almanarre", latitude: 43.055698, longitude: 6.127503,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "hyeres-359", name: "Hyères - Plage de la Badine", latitude: 43.039042, longitude: 6.154514,
             orientation: "E,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "port-la-nouvelle-360", name: "Port-la-Nouvelle - Plage centrale", latitude: 43.008263, longitude: 3.065550,
             orientation: "NW,N", level: .intermediate, type: .beach),
    KiteSpot(id: "barcaggio-361", name: "Barcaggio - Plage de Cala", latitude: 43.007387, longitude: 9.412716,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "rogliano-362", name: "Rogliano - Plage de Macinaggio", latitude: 42.963356, longitude: 9.454902,
             orientation: "SE", level: .intermediate, type: .beach),
    KiteSpot(id: "leucate-363", name: "Leucate - Étang de La Palme", latitude: 42.958188, longitude: 3.000584,
             orientation: "NW,N", level: .beginner, type: .lake),
    KiteSpot(id: "leucate-364", name: "Leucate - Plage Les Coussoules", latitude: 42.941868, longitude: 3.040987,
             orientation: "NW,W,E,SE", level: .advanced, type: .beach),
    KiteSpot(id: "leucate-365", name: "Leucate - Plage La Franqui", latitude: 42.931814, longitude: 3.041123,
             orientation: "NW,W,E,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "leucate-366", name: "Leucate - Le Goulet (étang)", latitude: 42.910140, longitude: 3.015172,
             orientation: "NW,W", level: .advanced, type: .lake),
    KiteSpot(id: "leucate-367", name: "Leucate - Coriolis Foil School Spot (étang)", latitude: 42.900774, longitude: 3.016561,
             orientation: "NW,W", level: .beginner, type: .lake),
    KiteSpot(id: "leucate-368", name: "Leucate - Plage d'Aqualand", latitude: 42.841640, longitude: 3.044625,
             orientation: "NW,SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "leucate-369", name: "Leucate - Barcarès (étang)", latitude: 42.835372, longitude: 3.024506,
             orientation: "NW,W,E", level: .beginner, type: .lake),
    KiteSpot(id: "leucate-370", name: "Leucate - Éole (étang)", latitude: 42.832584, longitude: 3.032053,
             orientation: "NW,W", level: .beginner, type: .lake),
    KiteSpot(id: "le-barcares-371", name: "Le Barcarès - Les 3 Colonnes", latitude: 42.813310, longitude: 3.041805,
             orientation: "SE,S", level: .intermediate, type: .beach),
    KiteSpot(id: "saint-laurent-de-la-salan-372", name: "Saint-Laurent-de-la-Salanque - L'Estaque (étang de Leucate)", latitude: 42.805739, longitude: 3.012775,
             orientation: "NW", level: .beginner, type: .lake),
    KiteSpot(id: "saint-laurent-de-la-salan-373", name: "Saint-Laurent-de-la-Salanque - Base Militaire (étang de Leucate)", latitude: 42.802325, longitude: 2.997054,
             orientation: "NW,W", level: .beginner, type: .lake),
    KiteSpot(id: "santo-pietro-di-tenda-374", name: "Santo-Pietro-di-Tenda - Plage de Saleccia", latitude: 42.727479, longitude: 9.204028,
             orientation: "NW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "canet-en-roussillon-375", name: "Canet-en-Roussillon - Plage du Roussillon", latitude: 42.697192, longitude: 3.038951,
             orientation: "NW,SE", level: .beginner, type: .beach),
    KiteSpot(id: "canet-en-rousillon-376", name: "Canet-en-Rousillon - Plage du Lido", latitude: 42.667276, longitude: 3.035666,
             orientation: "SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "palasca-377", name: "Palasca - Plage de l’Ostriconi", latitude: 42.662320, longitude: 9.058708,
             orientation: "SW", level: .beginner, type: .beach),
    KiteSpot(id: "belgodere-378", name: "Belgodère - Plage de Lozari", latitude: 42.642308, longitude: 9.014011,
             orientation: "W", level: .intermediate, type: .beach),
    KiteSpot(id: "canet-en-rousillon-379", name: "Canet-en-Rousillon - Plage Nord - Saint Cyprien", latitude: 42.638906, longitude: 3.036439,
             orientation: "SE", level: .beginner, type: .beach),
    KiteSpot(id: "lile-rousse-380", name: "L’Île-Rousse", latitude: 42.635235, longitude: 8.941608,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "corbada-381", name: "Corbada - Plage de Bodri", latitude: 42.630376, longitude: 8.911837,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "corbara-382", name: "Corbara - Plage de Ghjunchitu", latitude: 42.628289, longitude: 8.904946,
             orientation: "NW,W", level: .advanced, type: .beach),
    KiteSpot(id: "algajola-383", name: "Algajola - Plage d’Aregno", latitude: 42.610051, longitude: 8.869634,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "argeles-sur-mer-384", name: "Argelès-sur-Mer - Plage du Soleil", latitude: 42.575886, longitude: 3.047476,
             orientation: "ESE", level: .intermediate, type: .beach),
    KiteSpot(id: "calvi-385", name: "Calvi", latitude: 42.560169, longitude: 8.760796,
             orientation: "NW,N", level: .beginner, type: .beach),
    KiteSpot(id: "argeles-sur-mer-386", name: "Argelès-sur-Mer - Plage du Racou", latitude: 42.539408, longitude: 3.056569,
             orientation: "SE,NW", level: .beginner, type: .beach),
    KiteSpot(id: "ghisonaccia-387", name: "Ghisonaccia - Plage d’Erba Rossa", latitude: 41.997230, longitude: 9.451655,
             orientation: "NE,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "ajaccio-388", name: "Ajaccio - Capo di Feno", latitude: 41.936316, longitude: 8.619864,
             orientation: "W,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "ajaccio-389", name: "Ajaccio - Plage du Ricanto", latitude: 41.925394, longitude: 8.773545,
             orientation: "SW,W", level: .intermediate, type: .beach),
    KiteSpot(id: "grosseto-prugna-390", name: "Grosseto-Prugna - Plage de Porticcio", latitude: 41.895887, longitude: 8.801678,
             orientation: "SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "grosseto-prugna-391", name: "Grosseto-Prugna - Crique Porticcio", latitude: 41.879495, longitude: 8.784053,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "solaro-392", name: "Solaro - Plage de Chiola", latitude: 41.878630, longitude: 9.399519,
             orientation: "NE,E,SE", level: .beginner, type: .beach),
    KiteSpot(id: "pietrosella-393", name: "Pietrosella - Plage de Mare É Sole", latitude: 41.812522, longitude: 8.770575,
             orientation: "SW,S", level: .beginner, type: .beach),
    KiteSpot(id: "serra-di-ferro-394", name: "Serra-di-Ferro - Plage du Taravu", latitude: 41.712161, longitude: 8.815864,
             orientation: "W", level: .intermediate, type: .beach),
    KiteSpot(id: "serra-di-ferra-395", name: "Serra-di-Ferra - Plage de Porto Pollo", latitude: 41.709317, longitude: 8.795851,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "zonza-396", name: "Zonza - Plage de Pinarellu", latitude: 41.674259, longitude: 9.375071,
             orientation: "E,NE", level: .beginner, type: .beach),
    KiteSpot(id: "propriano-397", name: "Propriano - Plage de Capu Laurosu", latitude: 41.674143, longitude: 8.891700,
             orientation: "W,NW", level: .beginner, type: .beach),
    KiteSpot(id: "lecci-398", name: "Lecci - Plage de Saint-Cyprien", latitude: 41.638209, longitude: 9.350189,
             orientation: "SE,S", level: .beginner, type: .beach),
    KiteSpot(id: "porto-vecchio-399", name: "Porto-Vecchio - Plage de Golfo di Sogno", latitude: 41.621804, longitude: 9.316889,
             orientation: "NW,SE", level: .intermediate, type: .beach),
    KiteSpot(id: "porto-vecchio-400", name: "Porto-Vecchio - Plage de Palombaggia", latitude: 41.559720, longitude: 9.333080,
             orientation: "S,SSW,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "sartene-401", name: "Sartène - Plage de Tizzano", latitude: 41.534953, longitude: 8.852775,
             orientation: "NW", level: .intermediate, type: .beach),
    KiteSpot(id: "porto-vecchio-402", name: "Porto-Vecchio - Plage de Santa Giulia", latitude: 41.527159, longitude: 9.273515,
             orientation: "W,SW", level: .intermediate, type: .beach),
    KiteSpot(id: "pianottoli-caldarello-403", name: "Pianottoli-Caldarello - Plage de Figari", latitude: 41.466011, longitude: 9.069823,
             orientation: "W,SW", level: .beginner, type: .beach),
    KiteSpot(id: "figari-404", name: "Figari - Plage Punta du Ventilegne", latitude: 41.441543, longitude: 9.081015,
             orientation: "W,E", level: .intermediate, type: .beach),
    KiteSpot(id: "bonifacio-405", name: "Bonifacio - Plage de Balistra", latitude: 41.438677, longitude: 9.224501,
             orientation: "W,E", level: .intermediate, type: .beach),
    KiteSpot(id: "bonifacio-406", name: "Bonifacio - Plage de la Tonnara", latitude: 41.426984, longitude: 9.103793,
             orientation: "W,E", level: .intermediate, type: .beach),
    KiteSpot(id: "bonifacio-407", name: "Bonifacio - Plage de Stagnolu", latitude: 41.421297, longitude: 9.108263,
             orientation: "SW,NW", level: .intermediate, type: .beach),
    KiteSpot(id: "bonifacio-408", name: "Bonifacio - Plage des Tamaris", latitude: 41.416478, longitude: 9.237814,
             orientation: "W", level: .intermediate, type: .beach),
    KiteSpot(id: "bonifacio-409", name: "Bonifacio - Plage de Piantarella", latitude: 41.374166, longitude: 9.221931,
             orientation: "E,NE", level: .beginner, type: .beach),

    // MARK: - Spots enrichis depuis thespot2be.com

    // Landes - Lacs
    KiteSpot(id: "lac-leon-410", name: "Lac de Léon - Les berges", latitude: 43.888, longitude: -1.317,
             orientation: "N,NW,W,SW", level: .beginner, type: .lake, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "lac-leon-vielle-411", name: "Lac de Léon - Vielle", latitude: 43.901, longitude: -1.310,
             orientation: "N,NW,W,SW", level: .beginner, type: .lake, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "lac-soustons-412", name: "Lac de Soustons", latitude: 43.770, longitude: -1.317,
             orientation: "N,NW,W", level: .intermediate, type: .lake, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Champagne-Ardenne
    KiteSpot(id: "lac-der-413", name: "Lac du Der", latitude: 48.602, longitude: 4.746,
             orientation: "W,NW,N,NE,E", level: .intermediate, type: .lake, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Languedoc-Roussillon
    KiteSpot(id: "port-leucate-414", name: "Port-Leucate", latitude: 42.8795, longitude: 3.0497,
             orientation: "N,NW,SE", level: .beginner, type: .lagoon, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "canet-roussillon-415", name: "Canet-en-Roussillon", latitude: 42.673, longitude: 3.034,
             orientation: "N,NE,E,SE", level: .intermediate, type: .beach, waveType: .bigWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: true),
    KiteSpot(id: "valras-416", name: "Valras-Plage", latitude: 43.248, longitude: 3.299,
             orientation: "S,SE,E", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Côte d'Azur
    KiteSpot(id: "antibes-salis-417", name: "Antibes - La Salis", latitude: 43.572, longitude: 7.127,
             orientation: "E,SE", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "marseille-bonneveine-418", name: "Marseille - Bonneveine", latitude: 43.253, longitude: 5.375,
             orientation: "W,NW", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Normandie
    KiteSpot(id: "deauville-419", name: "Deauville", latitude: 49.349, longitude: 0.047,
             orientation: "N,NW,W", level: .beginner, type: .beach, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "cabourg-420", name: "Cabourg", latitude: 49.297, longitude: -0.102,
             orientation: "N,NW", level: .intermediate, type: .beach, waveType: .flat, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "le-havre-421", name: "Le Havre", latitude: 49.495, longitude: 0.092,
             orientation: "W,NW,N", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Bretagne
    KiteSpot(id: "guisseny-422", name: "Guissény", latitude: 48.63, longitude: -4.46,
             orientation: "N,NW,W", level: .beginner, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),
    KiteSpot(id: "guisseny-curnic-423", name: "Guissény - Le Curnic", latitude: 48.64, longitude: -4.45,
             orientation: "N,NW,W", level: .intermediate, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: true),
    KiteSpot(id: "beg-leguer-424", name: "Beg Léguer", latitude: 48.74, longitude: -3.55,
             orientation: "N,NW,W", level: .beginner, type: .beach, waveType: .smallWave, supportsKite: true, supportsWindsurf: true, supportsWing: true, supportsSurf: false),

    // Loire
    KiteSpot(id: "dagueriere-kite-425", name: "La Daguenière - Kitesurf", latitude: 47.418, longitude: -0.433,
             orientation: "W,NW,N,NE,E", level: .intermediate, type: .lake, waveType: .flat, supportsKite: true, supportsWindsurf: false, supportsWing: false, supportsSurf: false),
    KiteSpot(id: "lac-maine-426", name: "Lac de Maine - Angers", latitude: 47.464, longitude: -0.580,
             orientation: "W,NW,N,NE,E", level: .beginner, type: .lake, waveType: .flat, supportsKite: false, supportsWindsurf: true, supportsWing: true, supportsSurf: false)
]

// MARK: - Kite Spot Detail View

import SwiftUI

// MARK: - Kite Spot Bottom Panel (style cohérent avec les stations de vent)

struct KiteSpotBottomPanel: View {
    let spot: KiteSpot
    let forecast: ForecastData?
    let forecastLoading: Bool
    let nearbyStation: WindStation?
    let nearbyBuoy: WaveBuoy?
    let tideData: TideData?
    let onClose: () -> Void
    let onForecastTap: () -> Void
    var onTideTap: (() -> Void)? = nil

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var showForecast = false
    @State private var selectedTab: Int = 0 // 0 = prévisions, 1 = marées
    @State private var isExpanded: Bool = false
    @State private var showAlertConfig = false
    @State private var showScoreDetails: Bool = false
    @GestureState private var dragOffset: CGFloat = 0
    @AppStorage("kiteMaxWindThreshold") private var kiteMaxWindThreshold: Int = 40
    @AppStorage("kiteRiderLevel") private var kiteRiderLevelRaw: String = KiteRiderLevel.intermediate.rawValue

    private var riderLevel: KiteRiderLevel {
        KiteRiderLevel(rawValue: kiteRiderLevelRaw) ?? .intermediate
    }

    private var isFavorite: Bool {
        favoritesManager.isSpotFavorite(spotId: spot.id)
    }

    // MARK: - Navigability Logic

    /// Converts degrees to wind direction abbreviation
    private func directionAbbrev(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(round(degrees / 45.0)) % 8
        return directions[index]
    }

    /// Check if wind direction is suitable for the spot
    private var navigabilityInfo: (isNavigable: Bool, reason: String, color: Color) {
        guard let station = nearbyStation, station.isOnline else {
            return (false, "Pas de données vent", .secondary)
        }

        let windDir = directionAbbrev(station.direction)
        let spotOrientations = spot.orientation.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Check if wind direction matches any of the spot's orientations
        let isMatch = spotOrientations.contains { orientation in
            windDir == orientation ||
            // Handle compound directions (e.g. NW matches both N and W oriented spots)
            (windDir.count == 2 && (String(windDir.prefix(1)) == orientation || String(windDir.suffix(1)) == orientation))
        }

        if isMatch {
            return (true, "Direction favorable (\(windDir))", .green)
        } else {
            return (false, "Direction défavorable (\(windDir))", .orange)
        }
    }

    /// Wind strength assessment for kite
    private var windAssessment: (text: String, color: Color, icon: String)? {
        guard let station = nearbyStation, station.isOnline else { return nil }

        let wind = station.wind
        switch wind {
        case ..<8:
            return ("Vent faible", .blue, "wind")
        case 8..<12:
            return ("Vent léger - Foil/Big kite", .cyan, "wind")
        case 12..<20:
            return ("Conditions idéales", .green, "checkmark.circle.fill")
        case 20..<30:
            return ("Vent soutenu", .orange, "exclamationmark.triangle")
        default:
            return ("Vent fort - Experts", .red, "exclamationmark.triangle.fill")
        }
    }

    /// Wind color based on speed
    private func windScaleColor(_ knots: Double) -> Color {
        windScale(knots)
    }

    /// Sea temperature color
    private func seaTempColor(_ temp: Double) -> Color {
        switch temp {
        case ..<10: return .blue
        case ..<14: return .cyan
        case ..<18: return .green
        case ..<22: return .yellow
        default: return .orange
        }
    }

    private var levelColor: Color {
        switch spot.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        case .expert: return .purple
        }
    }

    private var levelIcon: String {
        switch spot.level {
        case .beginner: return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .advanced: return "3.circle.fill"
        case .expert: return "star.circle.fill"
        }
    }

    /// Kite rating computed from nearby station data
    private var kiteRating: KiteConditionRating? {
        guard let station = nearbyStation, station.isOnline else { return nil }
        return KiteConditionRating.evaluate(
            wind: station.wind,
            gust: station.gust,
            direction: station.direction,
            spot: spot,
            dangerThreshold: Double(kiteMaxWindThreshold),
            riderLevel: riderLevel
        )
    }

    /// Ideal wind range for display — uses effective level (max of rider and spot)
    private var idealWindRange: ClosedRange<Double> {
        let effectiveLevel = max(spot.level, riderLevel.asSpotLevel)
        return effectiveLevel.idealWindRange.lowerBound...Double(kiteMaxWindThreshold)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 4)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        // Type badge
                        HStack(spacing: 3) {
                            Image(systemName: spotTypeIcon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(spot.type.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        // Level badge
                        HStack(spacing: 3) {
                            Circle()
                                .fill(levelColor)
                                .frame(width: 8, height: 8)
                            Text(spot.level.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(levelColor)
                    }
                }

                Spacer()

                // Favorite button
                Button {
                    if isFavorite {
                        showAlertConfig = true
                    } else {
                        favoritesManager.addFavorite(kiteSpot: spot)
                        HapticManager.shared.success()
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isFavorite ? .red : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Stats cards - Row 1
            HStack(spacing: 10) {
                SpotStatCard(
                    title: "Niveau",
                    value: spot.level.rawValue,
                    icon: levelIcon,
                    color: levelColor
                )
                SpotStatCard(
                    title: "Orientation",
                    value: spot.orientation,
                    icon: "safari",
                    color: .blue
                )
                // Water temperature from nearest buoy
                if let buoy = nearbyBuoy, let seaTemp = buoy.seaTemp {
                    SpotStatCard(
                        title: "Eau",
                        value: "\(String(format: "%.1f", seaTemp).replacingOccurrences(of: ".", with: ","))°C",
                        icon: "thermometer.medium",
                        color: seaTempColor(seaTemp)
                    )
                } else {
                    SpotStatCard(
                        title: "Eau",
                        value: "--",
                        icon: "thermometer.medium",
                        color: .secondary
                    )
                }
            }

            // Stats cards - Row 2 (Wave type, Tide & Activities)
            HStack(spacing: 10) {
                if spot.waveType != .unknown {
                    SpotStatCard(
                        title: "Conditions",
                        value: spot.waveType.rawValue,
                        icon: spot.waveType.icon,
                        color: spot.waveType.color
                    )
                }
                // Tide preference if not "all"
                if spot.tidePreference != .all {
                    SpotStatCard(
                        title: "Marée",
                        value: spot.tidePreference.shortName,
                        icon: spot.tidePreference.icon,
                        color: spot.tidePreference.color
                    )
                }
                SpotStatCard(
                    title: "Activités",
                    value: spot.activitiesSummary,
                    icon: "figure.water.fitness",
                    color: .green
                )
            }

            // Tide warning if current tide is not compatible
            if spot.tidePreference != .all {
                let isCompatible = spot.tidePreference.isCompatible(with: tideData)
                if !isCompatible {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Marée non favorable - \(spot.tidePreference.displayName) recommandée")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // MARK: - Conditions actuelles (station proche)
            if let station = nearbyStation, station.isOnline {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Vent actuel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(station.name)
                                .lineLimit(1)
                            let dist = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
                                .distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
                            Text("à \(String(format: "%.1f", dist / 1000)) km")
                                .foregroundStyle(.quaternary)
                            if let lastUpdate = station.lastUpdate {
                                Text("•")
                                    .foregroundStyle(.quaternary)
                                Text(lastUpdate, style: .relative)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        // Wind speed
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(WindUnit.convertValue(station.wind))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(windScaleColor(station.wind))
                                Text(WindUnit.current.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Moy.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        // Gust
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(WindUnit.convertValue(station.gust))")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(windScaleColor(station.gust))
                                Text(WindUnit.current.symbol)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Rafales")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Direction arrow
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .rotationEffect(.degrees(station.direction + 180))
                                    .foregroundStyle(.cyan)
                            }
                            Text(directionAbbrev(station.direction))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Navigability indicator
                    let navInfo = navigabilityInfo
                    HStack(spacing: 8) {
                        Image(systemName: navInfo.isNavigable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(navInfo.color)

                        Text(navInfo.reason)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(navInfo.color)

                        Spacer()

                        // Wind assessment
                        if let assessment = windAssessment {
                            HStack(spacing: 4) {
                                Image(systemName: assessment.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(assessment.text)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(assessment.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(assessment.color.opacity(0.15), in: Capsule())
                        }
                    }

                    // MARK: - Résumé des conditions (notation)
                    if let rating = kiteRating {
                        Divider().padding(.vertical, 2)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showScoreDetails.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: rating.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(rating.color)
                                Text(rating.label)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(rating.color)
                                Text("—")
                                    .foregroundStyle(.secondary)
                                Text(rating.summary)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(rating.score)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(rating.color)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(showScoreDetails ? Color.blue : Color.gray.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)

                        // MARK: - Détails du score (dépliable)
                        if showScoreDetails {
                            VStack(spacing: 8) {
                                kiteScoreDetailRow(
                                    label: "Vent",
                                    icon: rating.windScore >= 28 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.windScore >= 28 ? .green : (rating.windScore >= 15 ? .orange : .red),
                                    current: "\(WindUnit.convertValue(station.wind)) \(WindUnit.current.symbol)",
                                    ideal: "\(WindUnit.convertValue(idealWindRange.lowerBound))-\(WindUnit.convertValue(idealWindRange.upperBound)) \(WindUnit.current.symbol)",
                                    score: rating.windScore,
                                    maxScore: 40
                                )
                                kiteScoreDetailRow(
                                    label: "Direction",
                                    icon: rating.directionScore >= 25 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.directionScore >= 25 ? .green : (rating.directionScore >= 10 ? .orange : .red),
                                    current: directionAbbrev(station.direction),
                                    ideal: spot.orientation,
                                    score: rating.directionScore,
                                    maxScore: 30
                                )
                                kiteScoreDetailRow(
                                    label: "Rafales",
                                    icon: rating.gustScore >= 22 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.gustScore >= 22 ? .green : (rating.gustScore >= 10 ? .orange : .red),
                                    current: "\(WindUnit.convertValue(station.gust)) \(WindUnit.current.symbol)",
                                    ideal: "Ratio < 1.3",
                                    score: rating.gustScore,
                                    maxScore: 30
                                )

                                // Explication textuelle
                                if !rating.details.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(rating.details, id: \.self) { detail in
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(Color.secondary.opacity(0.4))
                                                    .frame(width: 4, height: 4)
                                                Text(detail)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                }
                .padding(12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            } else if nearbyStation == nil {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                    Text("Aucune station à proximité")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            } else {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                    Text("Station hors ligne")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            }

            // Forecast & Tides segmented section (same as wind stations)
            VStack(spacing: 10) {
                // Segmented control
                HStack(spacing: 0) {
                    ForEach(0..<2) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedTab == index && isExpanded {
                                    // Tap same tab: collapse
                                    isExpanded = false
                                } else {
                                    // Tap different tab or expand
                                    selectedTab = index
                                    isExpanded = true
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: index == 0 ? "cloud.sun.fill" : "water.waves")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(index == 0 ? "Prévisions" : "Marées")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(selectedTab == index && isExpanded ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == index && isExpanded
                                    ? (index == 0 ? Color.orange : Color.cyan)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 10))

                // Content (only when expanded)
                if isExpanded {
                    if selectedTab == 0 {
                        ForecastStrip(
                            forecasts: forecast?.hourly ?? [],
                            isLoading: forecastLoading
                        )
                        .onTapGesture {
                            onForecastTap()
                        }
                    } else if let tide = tideData {
                        TideChartStrip(tideData: tide)
                            .onTapGesture {
                                onTideTap?()
                            }
                    }
                }
            }

            // Level legend
            HStack(spacing: 12) {
                ForEach([
                    (SpotLevel.beginner, Color.green),
                    (SpotLevel.intermediate, Color.orange),
                    (SpotLevel.advanced, Color.red),
                    (SpotLevel.expert, Color.purple)
                ], id: \.0) { level, color in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        Text(level.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 22))
        .shadow(radius: 14)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if value.translation.height < -threshold {
                            isExpanded = true
                        } else if value.translation.height > threshold {
                            if isExpanded {
                                isExpanded = false
                            } else {
                                onClose()
                            }
                        }
                    }
                }
        )
        .sheet(isPresented: $showAlertConfig) {
            if let favoriteSpot = favoritesManager.getSpotFavorite(id: spot.id) {
                SpotAlertConfigView(spot: favoriteSpot)
            }
        }
    }

    private var spotTypeIcon: String {
        switch spot.type {
        case .beach: return "beach.umbrella"
        case .lagoon: return "water.waves"
        case .bay: return "wind"
        case .spot: return "mappin"
        case .lake: return "drop.fill"
        }
    }

    @ViewBuilder
    private func kiteScoreDetailRow(label: String, icon: String, iconColor: Color, current: String, ideal: String, score: Int, maxScore: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 58, alignment: .leading)

            Text(current)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            Text(ideal)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Text("\(score)/\(maxScore)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Double(score) / Double(maxScore) >= 0.7 ? .green : (Double(score) / Double(maxScore) >= 0.4 ? .orange : .red))
                .fixedSize()
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Spot Stat Card

private struct SpotStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }
}

// MARK: - Legacy Detail View (pour compatibilité)

struct KiteSpotDetailView: View {
    let spot: KiteSpot
    @Environment(\.dismiss) private var dismiss
    @State private var showForecast = false

    private var levelColor: Color {
        switch spot.level {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        case .expert: return .purple
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(levelColor)
                            .frame(width: 60, height: 60)
                        Image(systemName: "wind")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(spot.name)
                        .font(.title2.bold())
                    Text(spot.type.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                VStack(spacing: 12) {
                    InfoRow(icon: "flag.fill", title: "Niveau", value: spot.level.rawValue, color: levelColor)
                    InfoRow(icon: "safari", title: "Orientation", value: spot.orientation, color: .blue)
                }
                .padding(.horizontal)

                Button {
                    showForecast = true
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Voir les prévisions")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Spot de Kite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showForecast) {
                ForecastFullView(
                    stationName: spot.name,
                    latitude: spot.latitude,
                    longitude: spot.longitude,
                    onClose: { showForecast = false }
                )
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
