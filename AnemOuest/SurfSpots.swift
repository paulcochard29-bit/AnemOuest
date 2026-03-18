import Foundation
import CoreLocation
import SwiftUI

// MARK: - Surf Spot Model

struct SurfSpot: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    // Caractéristiques du spot
    let level: SurfLevel
    let waveType: SurfWaveType
    let bottomType: BottomType
    let orientation: String           // Direction face à la houle (ex: "W", "SW", "NW")

    // Conditions idéales
    let idealSwellDirection: ClosedRange<Double>  // Degrés (ex: 250...310 pour W-NW)
    let idealSwellSize: ClosedRange<Double>       // Hauteur en mètres
    let idealPeriod: ClosedRange<Double>          // Période en secondes
    let idealTide: TidePreference

    // Informations additionnelles
    var description: String = ""
    var hazards: [String] = []        // Dangers (rochers, courants, etc.)
    var crowd: CrowdLevel = .moderate
    var consistency: Int = 3          // 1-5 (fréquence des bonnes conditions)

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Enums

enum SurfLevel: String, CaseIterable {
    case beginner = "Débutant"
    case intermediate = "Intermédiaire"
    case advanced = "Confirmé"
    case expert = "Expert"

    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .yellow
        case .advanced: return .orange
        case .expert: return .red
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

    var minWaveHeight: Double {
        switch self {
        case .beginner: return 0.3
        case .intermediate: return 0.5
        case .advanced: return 1.0
        case .expert: return 1.5
        }
    }

    var maxWaveHeight: Double {
        switch self {
        case .beginner: return 1.0
        case .intermediate: return 1.8
        case .advanced: return 3.0
        case .expert: return 10.0
        }
    }
}

enum SurfWaveType: String, CaseIterable {
    case beachBreak = "Beach Break"
    case reefBreak = "Reef Break"
    case pointBreak = "Point Break"
    case riverMouth = "Embouchure"
    case shoreBreak = "Shore Break"

    var icon: String {
        switch self {
        case .beachBreak: return "beach.umbrella"
        case .reefBreak: return "fossil.shell.fill"
        case .pointBreak: return "arrow.turn.down.right"
        case .riverMouth: return "water.waves.and.arrow.down"
        case .shoreBreak: return "water.waves"
        }
    }

    var description: String {
        switch self {
        case .beachBreak: return "Vagues sur fond sableux"
        case .reefBreak: return "Vagues sur récif/rochers"
        case .pointBreak: return "Vagues le long d'une pointe"
        case .riverMouth: return "Vagues à l'embouchure"
        case .shoreBreak: return "Vagues cassant sur le bord"
        }
    }
}

enum BottomType: String {
    case sand = "Sable"
    case rock = "Rochers"
    case reef = "Récif"
    case mixed = "Mixte"

    var icon: String {
        switch self {
        case .sand: return "circle.dotted"
        case .rock: return "mountain.2.fill"
        case .reef: return "fossil.shell"
        case .mixed: return "square.split.diagonal"
        }
    }
}

enum TidePreference: String {
    case low = "Marée basse"
    case mid = "Mi-marée"
    case high = "Marée haute"
    case all = "Toutes marées"

    var icon: String {
        switch self {
        case .low: return "arrow.down"
        case .mid: return "arrow.left.arrow.right"
        case .high: return "arrow.up"
        case .all: return "water.waves"
        }
    }
}

enum CrowdLevel: String {
    case empty = "Désert"
    case light = "Peu fréquenté"
    case moderate = "Modéré"
    case crowded = "Fréquenté"
    case packed = "Très fréquenté"

    var icon: String {
        switch self {
        case .empty: return "person"
        case .light: return "person.2"
        case .moderate: return "person.2.fill"
        case .crowded: return "person.3"
        case .packed: return "person.3.fill"
        }
    }
}

// MARK: - Surf Condition Rating

struct SurfConditionRating {
    let score: Int              // 0-100
    let waveScore: Int          // 0-100
    let periodScore: Int        // 0-100
    let directionScore: Int     // 0-100
    let levelMatch: Bool        // Le spot convient au niveau de houle actuel
    let summary: String
    let details: [String]

    var color: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
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
        default: return "xmark.circle"
        }
    }
}

// MARK: - Surf Spots Database (France - Côte Atlantique)

let allSurfSpots: [SurfSpot] = [
    // FINISTÈRE
    SurfSpot(
        id: "torche",
        name: "La Torche",
        latitude: 47.8397,
        longitude: -4.3497,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...310,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 8...14,
        idealTide: .mid,
        description: "Spot mythique de Bretagne, consistant et puissant",
        hazards: ["Courants", "Rochers côté nord"],
        crowd: .crowded,
        consistency: 5
    ),
    SurfSpot(
        id: "baie-trepasses",
        name: "Baie des Trépassés",
        latitude: 48.0469,
        longitude: -4.7068,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.6...2.0,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Belle baie abritée, idéale par grosse houle",
        hazards: ["Courants par grosse houle"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "penhors",
        name: "Penhors",
        latitude: 47.9147,
        longitude: -4.3847,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 220...280,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 7...11,
        idealTide: .mid,
        description: "Beach break accessible, bon pour débuter",
        hazards: [],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "kermabec",
        name: "Kermabec",
        latitude: 47.8815,
        longitude: -4.3614,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...310,
        idealSwellSize: 0.5...2.0,
        idealPeriod: 8...13,
        idealTide: .all,
        description: "Alternative à La Torche, même exposition",
        hazards: [],
        crowd: .light,
        consistency: 4
    ),
    SurfSpot(
        id: "tronoen",
        name: "Tronoën",
        latitude: 47.8521,
        longitude: -4.3494,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...310,
        idealSwellSize: 0.5...1.8,
        idealPeriod: 8...12,
        idealTide: .all,
        description: "Entre La Torche et Kermabec, plage naturiste",
        hazards: [],
        crowd: .light,
        consistency: 4
    ),
    SurfSpot(
        id: "dourveil",
        name: "Dourveil",
        latitude: 47.7938,
        longitude: -3.8112,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "S",
        idealSwellDirection: 200...260,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .low,
        description: "Spot abrité de Névez, idéal débutants",
        hazards: [],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "la-palue",
        name: "La Palue",
        latitude: 48.2026,
        longitude: -4.5510,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...310,
        idealSwellSize: 1.0...3.0,
        idealPeriod: 9...14,
        idealTide: .all,
        description: "Spot sauvage de la presqu'île de Crozon, puissant",
        hazards: ["Courants forts", "Baignade interdite"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "pen-hat",
        name: "Pen Hat",
        latitude: 48.2765,
        longitude: -4.6177,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 1.0...3.0,
        idealPeriod: 10...15,
        idealTide: .mid,
        description: "Spot puissant de Camaret, courants dangereux",
        hazards: ["Courants très forts", "Baignade interdite"],
        crowd: .light,
        consistency: 4
    ),
    SurfSpot(
        id: "petit-minou",
        name: "Le Petit Minou",
        latitude: 48.3370,
        longitude: -4.6180,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 220...280,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 8...12,
        idealTide: .low,
        description: "Spot emblématique de Brest, vagues creuses",
        hazards: ["Rochers"],
        crowd: .crowded,
        consistency: 4
    ),
    SurfSpot(
        id: "blancs-sablons",
        name: "Les Blancs Sablons",
        latitude: 48.3694,
        longitude: -4.7644,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...330,
        idealSwellSize: 0.5...2.0,
        idealPeriod: 8...13,
        idealTide: .high,
        description: "Grande plage du Conquet, 2.5km de sable",
        hazards: ["Courants par grosse houle"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "le-dossen",
        name: "Le Dossen",
        latitude: 48.7032,
        longitude: -4.0260,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 280...340,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .all,
        description: "Spot nord Finistère, kite et windsurf",
        hazards: ["Vent fort"],
        crowd: .light,
        consistency: 2
    ),
    SurfSpot(
        id: "lostmarch",
        name: "Lostmarc'h",
        latitude: 48.2247,
        longitude: -4.5847,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...310,
        idealSwellSize: 1.0...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Plage sauvage de Crozon, moins fréquentée",
        hazards: ["Courants", "Accès difficile"],
        crowd: .light,
        consistency: 4
    ),
    SurfSpot(
        id: "goulien",
        name: "Goulien",
        latitude: 48.1847,
        longitude: -4.5297,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...300,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 8...13,
        idealTide: .mid,
        description: "Belle plage de la presqu'île de Crozon",
        hazards: ["Courants"],
        crowd: .light,
        consistency: 3
    ),

    // MORBIHAN
    SurfSpot(
        id: "donnant",
        name: "Donnant",
        latitude: 47.3248,
        longitude: -3.2366,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 240...300,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .high,
        description: "Spot mythique de Belle-Île, vagues puissantes",
        hazards: ["Courants forts", "Rochers"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "sainte-barbe",
        name: "Sainte-Barbe",
        latitude: 47.5987,
        longitude: -3.1510,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 210...270,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .high,
        description: "Long beach break, vagues douces et régulières",
        hazards: [],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "kerhilio",
        name: "Kerhilio",
        latitude: 47.6247,
        longitude: -3.1897,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 200...260,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 7...11,
        idealTide: .all,
        description: "Grande plage d'Erdeven, idéale pour débuter",
        hazards: [],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "mane-gwen",
        name: "Mané Gwen",
        latitude: 47.5753,
        longitude: -3.1122,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 200...260,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Spot de qualité près de la presqu'île de Quiberon",
        hazards: ["Rochers sur les côtés"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "port-blanc-quiberon",
        name: "Port Blanc",
        latitude: 47.5163,
        longitude: -3.1528,
        level: .advanced,
        waveType: .reefBreak,
        bottomType: .rock,
        orientation: "S",
        idealSwellDirection: 180...240,
        idealSwellSize: 1.0...2.5,
        idealPeriod: 10...14,
        idealTide: .mid,
        description: "Droite de qualité sur fond rocheux",
        hazards: ["Rochers", "Courants"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "port-rhu",
        name: "Port Rhu",
        latitude: 47.4847,
        longitude: -3.1339,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "SW",
        idealSwellDirection: 200...260,
        idealSwellSize: 0.6...1.8,
        idealPeriod: 8...12,
        idealTide: .all,
        description: "Spot polyvalent, marche à toutes les marées",
        hazards: [],
        crowd: .moderate,
        consistency: 4
    ),

    // LOIRE-ATLANTIQUE
    SurfSpot(
        id: "la-govelle",
        name: "La Govelle",
        latitude: 47.2661,
        longitude: -2.4539,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...300,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Le spot principal de la Côte Sauvage",
        hazards: ["Courants"],
        crowd: .crowded,
        consistency: 4
    ),
    SurfSpot(
        id: "la-courance",
        name: "La Courance",
        latitude: 47.2589,
        longitude: -2.3931,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...300,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Spot idéal pour les débutants",
        hazards: [],
        crowd: .moderate,
        consistency: 4
    ),

    // VENDÉE
    SurfSpot(
        id: "sables-olonne",
        name: "Les Sables d'Olonne - Tanchet",
        latitude: 46.4802,
        longitude: -1.7627,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...310,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Spot urbain avec des vagues de qualité",
        hazards: ["Baïnes"],
        crowd: .crowded,
        consistency: 4
    ),
    SurfSpot(
        id: "bud-bud",
        name: "Bud Bud",
        latitude: 46.3886,
        longitude: -1.4949,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 1.0...3.0,
        idealPeriod: 10...15,
        idealTide: .low,
        description: "Spot puissant, tubes possibles",
        hazards: ["Courants forts", "Shore break"],
        crowd: .moderate,
        consistency: 4
    ),

    // CHARENTE-MARITIME
    SurfSpot(
        id: "vert-bois",
        name: "Vert Bois",
        latitude: 45.8536,
        longitude: -1.2358,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...310,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Principal spot de l'île d'Oléron",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "saint-trojan",
        name: "Saint-Trojan",
        latitude: 45.8297,
        longitude: -1.2119,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...300,
        idealSwellSize: 0.4...1.2,
        idealPeriod: 8...11,
        idealTide: .all,
        description: "Spot école, vagues douces",
        hazards: [],
        crowd: .moderate,
        consistency: 3
    ),

    // GIRONDE
    SurfSpot(
        id: "lacanau",
        name: "Lacanau",
        latitude: 45.0015,
        longitude: -1.2022,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot mythique, accueille des compétitions WSL",
        hazards: ["Baïnes", "Courants"],
        crowd: .packed,
        consistency: 5
    ),
    SurfSpot(
        id: "carcans",
        name: "Carcans",
        latitude: 45.0789,
        longitude: -1.1892,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Moins de monde que Lacanau, même qualité",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "le-porge",
        name: "Le Porge",
        latitude: 44.8847,
        longitude: -1.1883,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Beach break sauvage et préservé",
        hazards: ["Baïnes", "Courants"],
        crowd: .light,
        consistency: 5
    ),
    SurfSpot(
        id: "cap-ferret",
        name: "Cap Ferret - La Pointe",
        latitude: 44.6547,
        longitude: -1.2599,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...310,
        idealSwellSize: 1.0...3.0,
        idealPeriod: 10...15,
        idealTide: .low,
        description: "Vagues puissantes à la pointe",
        hazards: ["Courants très forts", "Zone de navigation"],
        crowd: .light,
        consistency: 4
    ),

    // LANDES
    SurfSpot(
        id: "biscarrosse",
        name: "Biscarrosse",
        latitude: 44.4464,
        longitude: -1.2596,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Beach break de qualité, moins bondé",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "mimizan",
        name: "Mimizan Plage",
        latitude: 44.2143,
        longitude: -1.2998,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot familial avec bonnes vagues",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "contis",
        name: "Contis Plage",
        latitude: 44.0894,
        longitude: -1.3189,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot sauvage et préservé",
        hazards: ["Baïnes", "Courants"],
        crowd: .light,
        consistency: 5
    ),
    SurfSpot(
        id: "vieux-boucau",
        name: "Vieux Boucau",
        latitude: 43.7858,
        longitude: -1.4017,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...310,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .all,
        description: "Spot école idéal pour débuter",
        hazards: [],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "seignosse-casernes",
        name: "Les Casernes",
        latitude: 43.7247,
        longitude: -1.4297,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot nord de Seignosse, moins fréquenté",
        hazards: ["Baïnes", "Courants"],
        crowd: .light,
        consistency: 5
    ),
    SurfSpot(
        id: "seignosse-penon",
        name: "Le Penon",
        latitude: 43.7092,
        longitude: -1.4343,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .all,
        description: "Beach break de qualité, ambiance familiale",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "seignosse-bourdaines",
        name: "Les Bourdaines",
        latitude: 43.6947,
        longitude: -1.4367,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 275...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot caché entre Le Penon et Les Estagnots",
        hazards: ["Baïnes"],
        crowd: .light,
        consistency: 5
    ),
    SurfSpot(
        id: "seignosse-estagnots",
        name: "Les Estagnots",
        latitude: 43.6863,
        longitude: -1.4388,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 280...320,
        idealSwellSize: 1.0...3.0,
        idealPeriod: 10...15,
        idealTide: .low,
        description: "Vagues puissantes et creuses",
        hazards: ["Courants forts", "Shore break"],
        crowd: .crowded,
        consistency: 5
    ),
    SurfSpot(
        id: "hossegor-culs-nus",
        name: "Les Culs Nus",
        latitude: 43.6801,
        longitude: -1.4387,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 275...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Entre Estagnots et La Gravière, bon compromis",
        hazards: ["Baïnes", "Courants"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "hossegor-graviere",
        name: "La Gravière",
        latitude: 43.6738,
        longitude: -1.4409,
        level: .expert,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 280...320,
        idealSwellSize: 1.5...4.0,
        idealPeriod: 11...16,
        idealTide: .low,
        description: "Le pipeline français, tubes puissants",
        hazards: ["Vagues très creuses", "Courants violents"],
        crowd: .packed,
        consistency: 5
    ),
    SurfSpot(
        id: "hossegor-nord",
        name: "Hossegor - La Nord",
        latitude: 43.6703,
        longitude: -1.4436,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 280...320,
        idealSwellSize: 1.0...3.5,
        idealPeriod: 10...15,
        idealTide: .mid,
        description: "Pic de qualité au nord de la Gravière",
        hazards: ["Courants", "Foule"],
        crowd: .crowded,
        consistency: 5
    ),
    SurfSpot(
        id: "hossegor-centrale",
        name: "Hossegor - La Centrale",
        latitude: 43.6603,
        longitude: -1.4434,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .low,
        description: "Spot central d'Hossegor, ambiance animée",
        hazards: ["Courants", "Foule en été"],
        crowd: .packed,
        consistency: 5
    ),
    SurfSpot(
        id: "hossegor-sud",
        name: "Hossegor - La Sud",
        latitude: 43.6547,
        longitude: -1.4453,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...310,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Sud de la plage d'Hossegor, moins intense",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "capbreton-santocha",
        name: "La Santocha",
        latitude: 43.6411,
        longitude: -1.4467,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...310,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot polyvalent de Capbreton",
        hazards: ["Baïnes"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "capbreton-preventorium",
        name: "Le Préventorium",
        latitude: 43.6308,
        longitude: -1.4481,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...310,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Spot abrité par la digue sud",
        hazards: [],
        crowd: .moderate,
        consistency: 4
    ),

    // PAYS BASQUE
    SurfSpot(
        id: "anglet-vvf",
        name: "VVF",
        latitude: 43.5339,
        longitude: -1.5197,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Nord d'Anglet, moins fréquenté",
        hazards: ["Courants"],
        crowd: .light,
        consistency: 5
    ),
    SurfSpot(
        id: "anglet-marinella",
        name: "Marinella",
        latitude: 43.5267,
        longitude: -1.5231,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Bon beach break d'Anglet",
        hazards: ["Courants"],
        crowd: .moderate,
        consistency: 5
    ),
    SurfSpot(
        id: "anglet-cavaliers",
        name: "Les Cavaliers",
        latitude: 43.5208,
        longitude: -1.5266,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot emblématique d'Anglet",
        hazards: ["Courants"],
        crowd: .crowded,
        consistency: 5
    ),
    SurfSpot(
        id: "anglet-sables-or",
        name: "Les Sables d'Or",
        latitude: 43.5067,
        longitude: -1.5294,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Spot école surveillé",
        hazards: [],
        crowd: .crowded,
        consistency: 4
    ),
    SurfSpot(
        id: "biarritz-cote-basques",
        name: "Côte des Basques",
        latitude: 43.4791,
        longitude: -1.5584,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 270...320,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .high,
        description: "Berceau du surf en France, longues vagues douces",
        hazards: ["Rochers à marée basse"],
        crowd: .packed,
        consistency: 4
    ),
    SurfSpot(
        id: "biarritz-grande-plage",
        name: "Grande Plage Biarritz",
        latitude: 43.4848,
        longitude: -1.5589,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Spot urbain au coeur de Biarritz",
        hazards: ["Baigneurs", "Zones de baignade"],
        crowd: .packed,
        consistency: 4
    ),
    SurfSpot(
        id: "guethary-parlementia",
        name: "Parlementia",
        latitude: 43.4270,
        longitude: -1.6137,
        level: .expert,
        waveType: .reefBreak,
        bottomType: .reef,
        orientation: "NW",
        idealSwellDirection: 300...340,
        idealSwellSize: 2.0...5.0,
        idealPeriod: 12...18,
        idealTide: .mid,
        description: "Big wave spot, vagues de 3-6m",
        hazards: ["Récif", "Courants violents", "Taille"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "guethary-alcyons",
        name: "Les Alcyons",
        latitude: 43.4261,
        longitude: -1.6047,
        level: .advanced,
        waveType: .reefBreak,
        bottomType: .reef,
        orientation: "NW",
        idealSwellDirection: 290...330,
        idealSwellSize: 1.0...2.5,
        idealPeriod: 10...14,
        idealTide: .mid,
        description: "Droite de qualité sur récif",
        hazards: ["Récif peu profond", "Oursins"],
        crowd: .moderate,
        consistency: 4
    ),
    SurfSpot(
        id: "lafitenia",
        name: "Lafitenia",
        latitude: 43.4140,
        longitude: -1.6282,
        level: .intermediate,
        waveType: .pointBreak,
        bottomType: .rock,
        orientation: "NW",
        idealSwellDirection: 290...340,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 10...14,
        idealTide: .mid,
        description: "Point break de qualité, longues droites",
        hazards: ["Rochers", "Localisme"],
        crowd: .crowded,
        consistency: 4
    ),
    SurfSpot(
        id: "hendaye",
        name: "Hendaye",
        latitude: 43.3853,
        longitude: -1.7531,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 300...350,
        idealSwellSize: 0.4...1.2,
        idealPeriod: 8...12,
        idealTide: .all,
        description: "Grande plage idéale pour débuter",
        hazards: [],
        crowd: .crowded,
        consistency: 4
    ),

    // BRETAGNE NORD
    SurfSpot(
        id: "sibiril",
        name: "Sibiril",
        latitude: 48.6761,
        longitude: -4.0667,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "N",
        idealSwellDirection: 320...360,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 9...13,
        idealTide: .mid,
        description: "Spot exposé nord, marche par houle de nord",
        hazards: ["Eau froide"],
        crowd: .empty,
        consistency: 2
    ),

    // NORMANDIE
    SurfSpot(
        id: "siouville",
        name: "Siouville-Hague",
        latitude: 49.5603,
        longitude: -1.8308,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Le spot de surf référence de Normandie",
        hazards: ["Eau froide", "Courants"],
        crowd: .moderate,
        consistency: 3
    ),
    SurfSpot(
        id: "sciotot",
        name: "Sciotot",
        latitude: 49.5197,
        longitude: -1.8467,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...310,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Grande plage à côté de Siouville",
        hazards: ["Eau froide"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "etretat",
        name: "Étretat",
        latitude: 49.7089,
        longitude: 0.2067,
        level: .advanced,
        waveType: .pointBreak,
        bottomType: .rock,
        orientation: "SW",
        idealSwellDirection: 200...260,
        idealSwellSize: 1.0...2.5,
        idealPeriod: 10...14,
        idealTide: .low,
        description: "Spot mythique sous les falaises de craie",
        hazards: ["Rochers", "Courants", "Eau froide"],
        crowd: .moderate,
        consistency: 2
    ),

    // CÔTE D'OPALE (HAUTS-DE-FRANCE)
    SurfSpot(
        id: "wissant",
        name: "Wissant",
        latitude: 50.8853,
        longitude: 1.6625,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 280...340,
        idealSwellSize: 0.8...2.5,
        idealPeriod: 8...13,
        idealTide: .mid,
        description: "Le spot phare de la Côte d'Opale, entre Cap Gris-Nez et Cap Blanc-Nez",
        hazards: ["Eau froide", "Courants de marée", "Vent"],
        crowd: .moderate,
        consistency: 3
    ),
    SurfSpot(
        id: "wimereux",
        name: "Wimereux",
        latitude: 50.7650,
        longitude: 1.6067,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "NW",
        idealSwellDirection: 270...330,
        idealSwellSize: 0.5...1.8,
        idealPeriod: 7...12,
        idealTide: .mid,
        description: "Plage familiale idéale pour débuter",
        hazards: ["Eau froide"],
        crowd: .moderate,
        consistency: 3
    ),
    SurfSpot(
        id: "boulogne-plage",
        name: "Boulogne-sur-Mer",
        latitude: 50.7283,
        longitude: 1.5833,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 7...11,
        idealTide: .mid,
        description: "Grande plage urbaine, bonnes conditions pour l'apprentissage",
        hazards: ["Eau froide", "Trafic maritime"],
        crowd: .moderate,
        consistency: 2
    ),
    SurfSpot(
        id: "hardelot",
        name: "Hardelot-Plage",
        latitude: 50.6361,
        longitude: 1.5833,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.5...1.8,
        idealPeriod: 7...12,
        idealTide: .all,
        description: "Longue plage de sable fin, idéale pour les débutants",
        hazards: ["Eau froide"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "le-touquet",
        name: "Le Touquet",
        latitude: 50.5167,
        longitude: 1.5833,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.6...2.0,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Grande plage avec de bonnes vagues par houle d'ouest",
        hazards: ["Eau froide", "Courants"],
        crowd: .moderate,
        consistency: 3
    ),
    SurfSpot(
        id: "berck",
        name: "Berck-sur-Mer",
        latitude: 50.4053,
        longitude: 1.5647,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 250...310,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 7...11,
        idealTide: .all,
        description: "Immense plage avec vagues régulières, parfait pour débuter",
        hazards: ["Eau froide", "Char à voile"],
        crowd: .light,
        consistency: 3
    ),
    SurfSpot(
        id: "equihen",
        name: "Équihen-Plage",
        latitude: 50.6819,
        longitude: 1.5750,
        level: .intermediate,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "W",
        idealSwellDirection: 260...320,
        idealSwellSize: 0.8...2.0,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Spot moins connu mais avec du potentiel",
        hazards: ["Eau froide", "Rochers à marée basse"],
        crowd: .empty,
        consistency: 2
    ),
    SurfSpot(
        id: "sangatte",
        name: "Sangatte - Cap Blanc-Nez",
        latitude: 50.9333,
        longitude: 1.7500,
        level: .advanced,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "N",
        idealSwellDirection: 300...360,
        idealSwellSize: 1.0...2.5,
        idealPeriod: 9...14,
        idealTide: .mid,
        description: "Spot exposé au pied des falaises, réservé aux expérimentés",
        hazards: ["Eau froide", "Courants forts", "Falaises"],
        crowd: .empty,
        consistency: 2
    ),

    // CÔTES D'ARMOR
    SurfSpot(
        id: "trestraou",
        name: "Trestraou",
        latitude: 48.8197,
        longitude: -3.4397,
        level: .beginner,
        waveType: .beachBreak,
        bottomType: .sand,
        orientation: "N",
        idealSwellDirection: 320...360,
        idealSwellSize: 0.5...1.5,
        idealPeriod: 8...12,
        idealTide: .mid,
        description: "Plage familiale de Perros-Guirec",
        hazards: [],
        crowd: .light,
        consistency: 2
    ),
]

// MARK: - Condition Evaluation Functions

/// Évalue les conditions actuelles pour un spot de surf
func evaluateSurfConditions(spot: SurfSpot, buoy: WaveBuoy?, tide: TideData?) -> SurfConditionRating {
    guard let buoy = buoy, let hm0 = buoy.hm0 else {
        return SurfConditionRating(
            score: 0,
            waveScore: 0,
            periodScore: 0,
            directionScore: 0,
            levelMatch: false,
            summary: "Données indisponibles",
            details: ["Aucune donnée de houle disponible"]
        )
    }

    var details: [String] = []

    // 1. Évaluation de la hauteur des vagues (40% du score)
    let waveScore: Int
    if spot.idealSwellSize.contains(hm0) {
        waveScore = 100
        details.append("Hauteur idéale (\(String(format: "%.1f", hm0))m)")
    } else if hm0 < spot.idealSwellSize.lowerBound {
        let diff = spot.idealSwellSize.lowerBound - hm0
        waveScore = max(0, Int(100 - diff * 50))
        details.append("Houle un peu petite (\(String(format: "%.1f", hm0))m)")
    } else {
        let diff = hm0 - spot.idealSwellSize.upperBound
        waveScore = max(0, Int(100 - diff * 40))
        details.append("Houle importante (\(String(format: "%.1f", hm0))m)")
    }

    // 2. Évaluation de la période (30% du score)
    let periodScore: Int
    if let tp = buoy.tp {
        if spot.idealPeriod.contains(tp) {
            periodScore = 100
            details.append("Période idéale (\(Int(tp))s)")
        } else if tp < spot.idealPeriod.lowerBound {
            let diff = spot.idealPeriod.lowerBound - tp
            periodScore = max(0, Int(100 - diff * 15))
            details.append("Période courte (\(Int(tp))s)")
        } else {
            periodScore = 90 // Une longue période est rarement mauvaise
            details.append("Longue période (\(Int(tp))s)")
        }
    } else {
        periodScore = 50
        details.append("Période inconnue")
    }

    // 3. Évaluation de la direction (30% du score)
    let directionScore: Int
    if let direction = buoy.direction {
        if spot.idealSwellDirection.contains(direction) {
            directionScore = 100
            details.append("Direction idéale (\(Int(direction))°)")
        } else {
            // Calcul de l'écart angulaire
            let idealMid = (spot.idealSwellDirection.lowerBound + spot.idealSwellDirection.upperBound) / 2
            var diff = abs(direction - idealMid)
            if diff > 180 { diff = 360 - diff }
            directionScore = max(0, Int(100 - diff * 1.5))
            details.append("Direction décalée (\(Int(direction))°)")
        }
    } else {
        directionScore = 50
        details.append("Direction inconnue")
    }

    // 4. Vérification du niveau
    let levelMatch = hm0 >= spot.level.minWaveHeight && hm0 <= spot.level.maxWaveHeight
    if !levelMatch {
        if hm0 < spot.level.minWaveHeight {
            details.append("Trop petit pour ce spot")
        } else {
            details.append("Conditions réservées aux confirmés")
        }
    }

    // Score final pondéré
    let totalScore = Int(Double(waveScore) * 0.4 + Double(periodScore) * 0.3 + Double(directionScore) * 0.3)

    // Ajustement si le niveau ne correspond pas
    let finalScore = levelMatch ? totalScore : max(0, totalScore - 20)

    // Résumé
    let summary: String
    switch finalScore {
    case 80...100: summary = "Conditions excellentes pour ce spot"
    case 60..<80: summary = "Bonnes conditions, allez-y !"
    case 40..<60: summary = "Conditions moyennes"
    case 20..<40: summary = "Conditions médiocres"
    default: summary = "Conditions défavorables"
    }

    return SurfConditionRating(
        score: finalScore,
        waveScore: waveScore,
        periodScore: periodScore,
        directionScore: directionScore,
        levelMatch: levelMatch,
        summary: summary,
        details: details
    )
}

/// Évalue les conditions de surf à partir des prévisions Open-Meteo
func evaluateSurfConditionsFromForecast(spot: SurfSpot, forecast: SurfWaveForecast, tide: TideData?) -> SurfConditionRating {
    guard let waveHeight = forecast.primaryHeight else {
        return SurfConditionRating(
            score: 0,
            waveScore: 0,
            periodScore: 0,
            directionScore: 0,
            levelMatch: false,
            summary: "Données indisponibles",
            details: ["Aucune prévision de houle disponible"]
        )
    }

    var details: [String] = []

    // 1. Évaluation de la hauteur des vagues (40% du score)
    let waveScore: Int
    if spot.idealSwellSize.contains(waveHeight) {
        waveScore = 100
        details.append("Hauteur idéale (\(String(format: "%.1f", waveHeight))m)")
    } else if waveHeight < spot.idealSwellSize.lowerBound {
        let diff = spot.idealSwellSize.lowerBound - waveHeight
        waveScore = max(0, Int(100 - diff * 50))
        details.append("Houle un peu petite (\(String(format: "%.1f", waveHeight))m)")
    } else {
        let diff = waveHeight - spot.idealSwellSize.upperBound
        waveScore = max(0, Int(100 - diff * 40))
        details.append("Houle importante (\(String(format: "%.1f", waveHeight))m)")
    }

    // 2. Évaluation de la période (30% du score)
    let periodScore: Int
    if let period = forecast.primaryPeriod {
        if spot.idealPeriod.contains(period) {
            periodScore = 100
            details.append("Période idéale (\(Int(period))s)")
        } else if period < spot.idealPeriod.lowerBound {
            let diff = spot.idealPeriod.lowerBound - period
            periodScore = max(0, Int(100 - diff * 15))
            details.append("Période courte (\(Int(period))s)")
        } else {
            periodScore = 90 // Une longue période est rarement mauvaise
            details.append("Longue période (\(Int(period))s)")
        }
    } else {
        periodScore = 50
        details.append("Période inconnue")
    }

    // 3. Évaluation de la direction (30% du score)
    let directionScore: Int
    if let direction = forecast.primaryDirection {
        if spot.idealSwellDirection.contains(direction) {
            directionScore = 100
            details.append("Direction idéale (\(Int(direction))°)")
        } else {
            // Calcul de l'écart angulaire
            let idealMid = (spot.idealSwellDirection.lowerBound + spot.idealSwellDirection.upperBound) / 2
            var diff = abs(direction - idealMid)
            if diff > 180 { diff = 360 - diff }
            directionScore = max(0, Int(100 - diff * 1.5))
            details.append("Direction décalée (\(Int(direction))°)")
        }
    } else {
        directionScore = 50
        details.append("Direction inconnue")
    }

    // 4. Vérification du niveau
    let levelMatch = waveHeight >= spot.level.minWaveHeight && waveHeight <= spot.level.maxWaveHeight
    if !levelMatch {
        if waveHeight < spot.level.minWaveHeight {
            details.append("Trop petit pour ce spot")
        } else {
            details.append("Conditions réservées aux confirmés")
        }
    }

    // Score final pondéré
    let totalScore = Int(Double(waveScore) * 0.4 + Double(periodScore) * 0.3 + Double(directionScore) * 0.3)

    // Ajustement si le niveau ne correspond pas
    let finalScore = levelMatch ? totalScore : max(0, totalScore - 20)

    // Résumé
    let summary: String
    switch finalScore {
    case 80...100: summary = "Conditions excellentes pour ce spot"
    case 60..<80: summary = "Bonnes conditions, allez-y !"
    case 40..<60: summary = "Conditions moyennes"
    case 20..<40: summary = "Conditions médiocres"
    default: summary = "Conditions défavorables"
    }

    return SurfConditionRating(
        score: finalScore,
        waveScore: waveScore,
        periodScore: periodScore,
        directionScore: directionScore,
        levelMatch: levelMatch,
        summary: summary,
        details: details
    )
}

// MARK: - Surf Spot Bottom Panel

struct SurfSpotBottomPanel: View {
    let spot: SurfSpot
    let nearbyBuoy: WaveBuoy?
    let tideData: TideData?
    let onClose: () -> Void
    var onTideTap: (() -> Void)? = nil

    @StateObject private var forecastService = SurfForecastService.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var isExpanded: Bool = false
    @State private var selectedTab: Int = 0
    @State private var isTabExpanded: Bool = false
    @State private var showAlertConfig = false
    @State private var showScoreDetails: Bool = false
    @GestureState private var dragOffset: CGFloat = 0

    private var isFavorite: Bool {
        favoritesManager.isSpotFavorite(spotId: spot.id)
    }

    /// Prévision actuelle du spot (priorité sur les données bouée)
    private var currentForecast: SurfWaveForecast? {
        forecastService.currentForecast(for: spot.id)
    }

    /// Utilise les prévisions si disponibles, sinon les données bouée
    private var currentWaveHeight: Double? {
        currentForecast?.primaryHeight ?? nearbyBuoy?.hm0
    }

    private var currentWavePeriod: Double? {
        currentForecast?.primaryPeriod ?? nearbyBuoy?.tp
    }

    private var currentWaveDirection: Double? {
        currentForecast?.primaryDirection ?? nearbyBuoy?.direction
    }

    private var rating: SurfConditionRating {
        // Utilise les prévisions si disponibles
        if let forecast = currentForecast {
            return evaluateSurfConditionsFromForecast(spot: spot, forecast: forecast, tide: tideData)
        }
        return evaluateSurfConditions(spot: spot, buoy: nearbyBuoy, tide: tideData)
    }

    private var dataSource: String {
        if currentForecast != nil {
            return "Prévisions Open-Meteo"
        } else if nearbyBuoy != nil {
            return nearbyBuoy?.name ?? "Houlographe"
        }
        return "Aucune donnée"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 4)

            // MARK: - Header avec score
            HStack(spacing: 12) {
                // Score circulaire
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(rating.score) / 100)
                        .stroke(rating.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(rating.score)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Level badge
                        HStack(spacing: 3) {
                            Circle()
                                .fill(spot.level.color)
                                .frame(width: 8, height: 8)
                            Text(spot.level.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(spot.level.color)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        // Wave type
                        Text(spot.waveType.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Favorite button
                Button {
                    if isFavorite {
                        showAlertConfig = true
                    } else {
                        favoritesManager.addFavorite(surfSpot: spot)
                        HapticManager.shared.success()
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isFavorite ? .red : .secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // MARK: - Résumé des conditions
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
                        .foregroundStyle(.tertiary)
                    Text(rating.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(showScoreDetails ? Color.blue : Color.gray.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            // MARK: - Détails du score (dépliable)
            if showScoreDetails {
                VStack(spacing: 8) {
                    scoreDetailRow(
                        label: "Houle",
                        icon: rating.waveScore >= 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: rating.waveScore >= 70 ? .green : (rating.waveScore >= 40 ? .orange : .red),
                        current: String(format: "%.1f m", currentWaveHeight ?? 0),
                        ideal: String(format: "%.1f-%.1f m", spot.idealSwellSize.lowerBound, spot.idealSwellSize.upperBound),
                        score: rating.waveScore
                    )
                    scoreDetailRow(
                        label: "Période",
                        icon: rating.periodScore >= 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: rating.periodScore >= 70 ? .green : (rating.periodScore >= 40 ? .orange : .red),
                        current: currentWavePeriod != nil ? "\(Int(currentWavePeriod!)) s" : "—",
                        ideal: "\(Int(spot.idealPeriod.lowerBound))-\(Int(spot.idealPeriod.upperBound)) s",
                        score: rating.periodScore
                    )
                    scoreDetailRow(
                        label: "Direction",
                        icon: rating.directionScore >= 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: rating.directionScore >= 70 ? .green : (rating.directionScore >= 40 ? .orange : .red),
                        current: currentWaveDirection != nil ? "\(Int(currentWaveDirection!))°" : "—",
                        ideal: "\(Int(spot.idealSwellDirection.lowerBound))°-\(Int(spot.idealSwellDirection.upperBound))°",
                        score: rating.directionScore
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

            // MARK: - Conditions actuelles (toujours visible)
            if let waveHeight = currentWaveHeight {
                VStack(spacing: 8) {
                    // Source des données
                    HStack {
                        Image(systemName: currentForecast != nil ? "chart.line.uptrend.xyaxis" : "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(dataSource)
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        if forecastService.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    .foregroundStyle(.tertiary)

                    HStack(spacing: 0) {
                        // Hauteur
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", waveHeight))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(waveColor(waveHeight))
                                Text("m")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Houle")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)

                        // Période
                        if let period = currentWavePeriod {
                            VStack(spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("\(Int(period))")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.cyan)
                                    Text("s")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text("Période")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Direction
                        if let direction = currentWaveDirection {
                            VStack(spacing: 2) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 18, weight: .bold))
                                        .rotationEffect(.degrees(direction + 180))
                                        .foregroundStyle(.blue)
                                }
                                Text("\(Int(direction))°")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Température eau (depuis bouée si disponible)
                        if let buoy = nearbyBuoy, let seaTemp = buoy.seaTemp {
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text(String(format: "%.1f", seaTemp).replacingOccurrences(of: ".", with: ","))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(seaTempColor(seaTemp))
                                Text("°C")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Eau")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
                }
            }

            // MARK: - Barres de score (toujours visible)
            HStack(spacing: 10) {
                ScoreBar(label: "Houle", score: rating.waveScore, color: .blue)
                ScoreBar(label: "Période", score: rating.periodScore, color: .cyan)
                ScoreBar(label: "Direction", score: rating.directionScore, color: .green)
            }

            // MARK: - Stats cards (toujours visible)
            HStack(spacing: 8) {
                SurfStatCard(
                    title: "Fond",
                    value: spot.bottomType.rawValue,
                    icon: spot.bottomType.icon,
                    color: .brown
                )
                SurfStatCard(
                    title: "Marée idéale",
                    value: spot.idealTide.rawValue,
                    icon: spot.idealTide.icon,
                    color: .cyan
                )
                SurfStatCard(
                    title: "Affluence",
                    value: spot.crowd.rawValue,
                    icon: spot.crowd.icon,
                    color: .orange
                )
            }

            // MARK: - Bouton voir plus / moins
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(isExpanded ? "Réduire" : "Plus de détails")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // MARK: - Section étendue
            if isExpanded {
                // Dangers si présents
                if !spot.hazards.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(spot.hazards.joined(separator: " • "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                // Conditions idéales
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Conditions idéales")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("\(String(format: "%.1f", spot.idealSwellSize.lowerBound))-\(String(format: "%.1f", spot.idealSwellSize.upperBound))m")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Houle")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 4) {
                            Text("\(Int(spot.idealPeriod.lowerBound))-\(Int(spot.idealPeriod.upperBound))s")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Période")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 4) {
                            Text("\(Int(spot.idealSwellDirection.lowerBound))°-\(Int(spot.idealSwellDirection.upperBound))°")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Direction")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 4) {
                            Text(spot.orientation)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("Orientation")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))

                // Houle & Marées tabs
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        ForEach(0..<2) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedTab == index && isTabExpanded {
                                        isTabExpanded = false
                                    } else {
                                        selectedTab = index
                                        isTabExpanded = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: index == 0 ? "water.waves" : "water.waves.and.arrow.down")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(index == 0 ? "Houle" : "Marées")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(selectedTab == index && isTabExpanded ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    selectedTab == index && isTabExpanded
                                        ? (index == 0 ? Color.blue : Color.cyan)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 10))

                    if isTabExpanded {
                        if selectedTab == 0 {
                            if let buoy = nearbyBuoy {
                                WaveHistoryMiniChart(buoy: buoy)
                            }
                        } else if let tide = tideData {
                            TideChartStrip(tideData: tide)
                                .onTapGesture {
                                    onTideTap?()
                                }
                        }
                    }
                }

                // Description
                if !spot.description.isEmpty {
                    Text(spot.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                // Houlographe source
                if let buoy = nearbyBuoy {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10))
                        Text("Source: \(buoy.name)")
                            .font(.system(size: 10, weight: .medium))
                        let dist = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
                            .distance(from: CLLocation(latitude: buoy.latitude, longitude: buoy.longitude))
                        Text("à \(String(format: "%.0f", dist / 1000)) km")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.quaternary)
                        if let lastUpdate = buoy.lastUpdate {
                            Text("•")
                            Text(lastUpdate, style: .relative)
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(.tertiary)
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
        .onAppear {
            // Charger les prévisions de houle pour ce spot
            Task {
                await forecastService.fetchForecast(for: spot)
            }
        }
        .sheet(isPresented: $showAlertConfig) {
            if let favoriteSpot = favoritesManager.getSpotFavorite(id: spot.id) {
                SpotAlertConfigView(spot: favoriteSpot)
            }
        }
    }

    @ViewBuilder
    private func scoreDetailRow(label: String, icon: String, iconColor: Color, current: String, ideal: String, score: Int) -> some View {
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

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(ideal)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(score)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(score >= 70 ? .green : (score >= 40 ? .orange : .red))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func seaTempColor(_ temp: Double) -> Color {
        switch temp {
        case ..<10: return .blue
        case ..<14: return .cyan
        case ..<18: return .green
        case ..<22: return .yellow
        default: return .orange
        }
    }

    private func waveColor(_ height: Double) -> Color {
        switch height {
        case ..<0.5: return .cyan
        case ..<1.0: return .green
        case ..<1.5: return .yellow
        case ..<2.5: return .orange
        case ..<4.0: return .red
        default: return .purple
        }
    }
}

// MARK: - Score Bar

private struct ScoreBar: View {
    let label: String
    let score: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Surf Stat Card

private struct SurfStatCard: View {
    let title: String
    let value: String
    var icon: String = ""
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

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

// MARK: - Wave History Mini Chart

private struct WaveHistoryMiniChart: View {
    let buoy: WaveBuoy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Évolution de la houle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let hm0 = buoy.hm0 {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1fm", hm0))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text("Hm0 actuel")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    if let tp = buoy.tp {
                        VStack(spacing: 2) {
                            Text("\(Int(tp))s")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                            Text("Période")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if let lastUpdate = buoy.lastUpdate {
                        VStack(spacing: 2) {
                            Text(lastUpdate, style: .time)
                                .font(.system(size: 14, weight: .semibold))
                            Text("Dernière MàJ")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Text("Données de houle non disponibles")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }
}
