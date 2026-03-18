import Foundation

// MARK: - WindsUp Models

struct WindsUpStation: Identifiable {
    let id: Int
    let name: String
    let slug: String
    let latitude: Double
    let longitude: Double

    var observationsURL: URL? {
        URL(string: "https://www.winds-up.com/spot-\(slug)-windsurf-kitesurf-\(id)-observations-releves-vent.html")
    }
}

struct WindsUpObservation {
    let timestamp: Date
    let windSpeed: Double      // in knots
    let windDirection: String  // e.g., "NO", "NE", "S"
    let windDirectionDegrees: Double?
    let gustSpeed: Double?
}

struct WindsUpStationData {
    let station: WindsUpStation
    let observations: [WindsUpObservation]
    let currentWind: Double?
    let currentGust: Double?      // Current gust from latest observation
    let currentDirection: String?
    let minWind: Double?
    let maxWind: Double?
    let isBroken: Bool            // "Spot en panne" detected
}

// MARK: - WindsUp Service

final class WindsUpService {
    static let shared = WindsUpService()

    private var session: URLSession
    private var isAuthenticated = false

    // Cache
    private var cache: [Int: (data: WindsUpStationData, date: Date)] = [:]
    private let cacheDuration: TimeInterval = 180 // 3 minutes (matches site refresh)

    /// Get cached observations for a station (for charts)
    func getObservations(stationId: Int) -> [WindsUpObservation] {
        return cache[stationId]?.data.observations ?? []
    }

    /// Get observations by WindStation ID (format: "windsup_123")
    func getObservations(windStationId: String) -> [WindsUpObservation] {
        guard windStationId.hasPrefix("windsup_"),
              let idStr = windStationId.split(separator: "_").last,
              let stationId = Int(idStr) else {
            return []
        }
        return getObservations(stationId: stationId)
    }

    /// Force re-authentication on next fetch
    func resetAuth() {
        isAuthenticated = false
        cache.removeAll()
    }

    /// Set authentication status (called from WebView login)
    func setAuthenticated(_ value: Bool) {
        isAuthenticated = value
        if value {
            Log.debug("WindsUp: Authentication set to true from WebView")
        }
    }

    /// Check if we have valid auth cookies
    func checkAuthCookies() -> Bool {
        guard let url = URL(string: "https://www.winds-up.com/") else { return false }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        // autolog is the main auth cookie
        let hasAutolog = cookies.contains { $0.name == "autolog" }
        return hasAutolog
    }

    // All WindsUp stations with anemometers (real-time data)
    // URL format: spot-{slug}-windsurf-kitesurf-{id}-observations-releves-vent.html
    nonisolated static let defaultStations: [WindsUpStation] = [
        // === MÉDITERRANÉE ===
        WindsUpStation(id: 1, name: "Agde", slug: "agde", latitude: 43.2723, longitude: 3.50471),
        WindsUpStation(id: 2, name: "Almanarre - Salin des Pesquiers", slug: "almanarre-salin-des-pesquiers", latitude: 43.0667, longitude: 6.13491),
        WindsUpStation(id: 3, name: "Les Aresquiers", slug: "les-aresquiers-etang-dingril", latitude: 43.4942, longitude: 3.8086),
        WindsUpStation(id: 5, name: "Carro", slug: "carro", latitude: 43.3293, longitude: 5.03882),
        WindsUpStation(id: 6, name: "Saint Aygulf", slug: "saint-aygulf", latitude: 43.4094, longitude: 6.7264),
        WindsUpStation(id: 8, name: "La Bergerie", slug: "la-bergerie", latitude: 43.0583, longitude: 6.1333),
        WindsUpStation(id: 11, name: "Cannes Ouest", slug: "cannes-ouest", latitude: 43.5528, longitude: 6.9939),
        WindsUpStation(id: 14, name: "Saint Cyr les Lecques", slug: "saint-cyr-les-lecques", latitude: 43.1781, longitude: 5.7031),
        WindsUpStation(id: 20, name: "Fos", slug: "fos-", latitude: 43.4326, longitude: 4.92427),
        WindsUpStation(id: 22, name: "Port Camargue", slug: "port-camargue", latitude: 43.5182, longitude: 4.12238),
        WindsUpStation(id: 23, name: "Gruissan", slug: "gruissan-", latitude: 43.11, longitude: 3.125),
        WindsUpStation(id: 26, name: "Le Jaï", slug: "le-jaya", latitude: 43.4422, longitude: 5.0978),
        WindsUpStation(id: 29, name: "Saint Laurent du Var", slug: "saint-laurent-du-var", latitude: 43.6576, longitude: 7.19514),
        WindsUpStation(id: 30, name: "Port St Louis", slug: "port-st-louis", latitude: 43.3906, longitude: 4.8236),
        WindsUpStation(id: 39, name: "Leucate", slug: "leucate-", latitude: 42.8728, longitude: 3.03635),
        WindsUpStation(id: 44, name: "Marseille - Pointe Rouge", slug: "marseille-pointe-rouge-digue", latitude: 43.2463, longitude: 5.36383),
        WindsUpStation(id: 45, name: "Salagou", slug: "salagou", latitude: 43.6578, longitude: 3.3736),
        WindsUpStation(id: 48, name: "Sète - CN Barrou", slug: "syite-cn-barrou", latitude: 43.3967, longitude: 3.6931),
        WindsUpStation(id: 49, name: "Six Fours - Le Brusc", slug: "six-fours-le-brusc", latitude: 43.0736, longitude: 5.7972),
        WindsUpStation(id: 51, name: "Tonnara", slug: "tonnara", latitude: 41.4133, longitude: 9.1667),
        WindsUpStation(id: 58, name: "Barcarès", slug: "barcares-", latitude: 42.8324, longitude: 3.03459),
        WindsUpStation(id: 61, name: "Beauduc", slug: "beauduc", latitude: 43.4149, longitude: 4.61408),
        WindsUpStation(id: 63, name: "La Londe les Maures", slug: "la-londe-les-maures", latitude: 43.1333, longitude: 6.2333),
        WindsUpStation(id: 65, name: "Saintes Maries de la Mer", slug: "saintes-maries-de-la-mer", latitude: 43.4487, longitude: 4.42653),
        WindsUpStation(id: 81, name: "Le Ponant", slug: "le-ponant", latitude: 43.5333, longitude: 4.0833),
        WindsUpStation(id: 82, name: "Villeneuve-lès-Maguelone", slug: "villeneuve-lyis-maguelone", latitude: 43.5167, longitude: 3.8500),
        WindsUpStation(id: 83, name: "Saint Cyprien", slug: "saint-cyprien-", latitude: 42.6244, longitude: 3.0289),
        WindsUpStation(id: 84, name: "Porto Polo", slug: "porto-polo", latitude: 41.5833, longitude: 8.8000),
        WindsUpStation(id: 86, name: "La Coudoulière Six-Fours", slug: "la-coudouliere-six-fours", latitude: 43.0806, longitude: 5.8111),
        WindsUpStation(id: 117, name: "Saint Chamas", slug: "saint-chamas", latitude: 43.5456, longitude: 5.0308),
        WindsUpStation(id: 118, name: "La Ciotat", slug: "la-ciotat", latitude: 43.1747, longitude: 5.6047),
        WindsUpStation(id: 135, name: "La Grande-Motte", slug: "la-grande-motte", latitude: 43.5567, longitude: 4.0833),
        WindsUpStation(id: 1536, name: "Le Pradet Garonne", slug: "le-pradet-garonne", latitude: 43.0994, longitude: 6.0236),
        WindsUpStation(id: 1547, name: "Cannes Palm Beach", slug: "cannes-palm-beach", latitude: 43.5355, longitude: 7.0375),
        WindsUpStation(id: 1548, name: "Bormes les Mimosas", slug: "bormes-les-mimosas", latitude: 43.1333, longitude: 6.3333),
        WindsUpStation(id: 1549, name: "Santa Manza", slug: "santa-manza", latitude: 41.4583, longitude: 9.2583),
        WindsUpStation(id: 1554, name: "La Franqui - Coussoules", slug: "la-franqui-poste-des-coussoules", latitude: 42.9333, longitude: 3.0333),
        WindsUpStation(id: 1558, name: "Carnon Yacht Club", slug: "carnon-yacht-club-", latitude: 43.5500, longitude: 3.9667),
        WindsUpStation(id: 1561, name: "Rognac - Base Nautique", slug: "rognac-base-nautique", latitude: 43.4875, longitude: 5.2306),
        WindsUpStation(id: 1563, name: "Argelès Nord", slug: "argeles-nord", latitude: 42.5500, longitude: 3.0333),
        WindsUpStation(id: 1567, name: "Le Goulet - Windy Sam", slug: "le-goulet-windy-sam-voilerie", latitude: 43.1167, longitude: 3.1000),
        WindsUpStation(id: 1572, name: "La Nautique", slug: "la-nautique", latitude: 43.1167, longitude: 2.9833),
        WindsUpStation(id: 1573, name: "Berre l'étang", slug: "berre-lyotang", latitude: 43.4792, longitude: 5.1664),
        WindsUpStation(id: 1576, name: "Saint Laurent de la Salanque", slug: "saint-laurent-de-la-salanque", latitude: 42.7667, longitude: 2.9833),
        WindsUpStation(id: 1617, name: "La Vieille Nouvelle", slug: "la-vieille-nouvelle-", latitude: 43.1000, longitude: 3.0667),
        WindsUpStation(id: 1629, name: "La Palme", slug: "la-palme", latitude: 42.9667, longitude: 3.0000),
        WindsUpStation(id: 1630, name: "Porto Vecchio", slug: "porto-vecchio-cala-rossa", latitude: 41.5917, longitude: 9.2794),
        WindsUpStation(id: 1637, name: "Beaulieu-sur-Mer", slug: "beaulieu-sur-mer", latitude: 43.7069, longitude: 7.3306),
        WindsUpStation(id: 1645, name: "Marseillan", slug: "marseillan-cercle-de-voile", latitude: 43.3500, longitude: 3.5333),
        WindsUpStation(id: 1655, name: "Berre - La Fare", slug: "berre-la-fare-aerodrome", latitude: 43.5333, longitude: 5.1167),
        WindsUpStation(id: 1659, name: "Piantarella", slug: "piantarella", latitude: 41.3833, longitude: 9.2333),
        WindsUpStation(id: 1661, name: "Figari - Eole", slug: "figari-eole", latitude: 41.5000, longitude: 9.0833),
        WindsUpStation(id: 1665, name: "Le Mérou Kite Beach", slug: "le-myorou-kite-beach", latitude: 42.9000, longitude: 3.0167),
        WindsUpStation(id: 1666, name: "Sète - Les 3 digues", slug: "syite-les-3-digues", latitude: 43.4000, longitude: 3.7000),
        WindsUpStation(id: 1668, name: "Sainte Marie la Mer", slug: "sainte-marie-la-mer", latitude: 42.7167, longitude: 3.0167),
        WindsUpStation(id: 1693, name: "Balistra", slug: "balistra", latitude: 41.4167, longitude: 9.2000),
        WindsUpStation(id: 1698, name: "Saint Aygulf Pacha", slug: "saint-aygulf-pacha", latitude: 43.4083, longitude: 6.7278),
        WindsUpStation(id: 1709, name: "Almanarre - Spinout", slug: "almanarre-plage-des-estagnets-spinout", latitude: 43.0583, longitude: 6.1250),
        WindsUpStation(id: 1716, name: "Toulon - Le Mourillon", slug: "toulon-le-mourillon-grande-jetyoe-sud", latitude: 43.1056, longitude: 5.9389),
        WindsUpStation(id: 1725, name: "Terminal Côte Azur Sud", slug: "terminal-cote-azur-sud", latitude: 43.6500, longitude: 7.2167),
        WindsUpStation(id: 1726, name: "Porticcio", slug: "porticcio-", latitude: 41.8833, longitude: 8.7833),

        // === AQUITAINE ===
        WindsUpStation(id: 4, name: "Arcachon", slug: "arcachon", latitude: 44.6481, longitude: -1.19855),
        WindsUpStation(id: 25, name: "Hourtin Lac", slug: "hourtin-lac", latitude: 45.1833, longitude: -1.0833),
        WindsUpStation(id: 27, name: "Lacanau - Lac", slug: "lacanau-lac", latitude: 44.9667, longitude: -1.1333),
        WindsUpStation(id: 46, name: "Sanguinet", slug: "sanguinet", latitude: 44.4833, longitude: -1.0833),
        WindsUpStation(id: 73, name: "Soustons", slug: "soustons", latitude: 43.7583, longitude: -1.3333),
        WindsUpStation(id: 1623, name: "Mimizan", slug: "mimizan", latitude: 44.2167, longitude: -1.2333),
        WindsUpStation(id: 1639, name: "Lacanau - Plage", slug: "lacanau-plage", latitude: 45.0000, longitude: -1.2000),
        WindsUpStation(id: 1657, name: "Soulac", slug: "soulac", latitude: 45.5083, longitude: -1.1250),
        WindsUpStation(id: 1679, name: "Lacanau - Guyenne Voile", slug: "lacanau-guyenne-voile", latitude: 44.9833, longitude: -1.1167),

        // === CHARENTE & VENDÉE ===
        WindsUpStation(id: 9, name: "Saint Brévin", slug: "saint-bryovin-", latitude: 47.225, longitude: -2.173),
        WindsUpStation(id: 43, name: "La Rochelle", slug: "la-rochelle", latitude: 46.1428, longitude: -1.17177),
        WindsUpStation(id: 53, name: "La Tranche - Le Phare", slug: "la-tranche-sur-mer-le-phare", latitude: 46.3439, longitude: -1.43073),
        WindsUpStation(id: 59, name: "La Palmyre - Accrokite", slug: "la-palmyre-accrokite", latitude: 45.6886, longitude: -1.19039),
        WindsUpStation(id: 80, name: "Ile de Ré - Albeau", slug: "ile-de-ryo-ecole-a-albeau", latitude: 46.2000, longitude: -1.5333),
        WindsUpStation(id: 91, name: "Ile Oléron", slug: "ile-oleron", latitude: 45.9333, longitude: -1.3167),
        WindsUpStation(id: 105, name: "Brétignolles sur mer", slug: "bretignolles-sur-mer", latitude: 46.6333, longitude: -1.8667),
        WindsUpStation(id: 106, name: "Fromentine", slug: "fromentine", latitude: 46.886, longitude: -2.15371),
        WindsUpStation(id: 133, name: "Saint Gilles Croix de Vie", slug: "saint-gilles-croix-de-vie", latitude: 46.6833, longitude: -1.9333),
        WindsUpStation(id: 136, name: "CNT - La Tranche sur Mer", slug: "cnt-la-tranche-sur-mer", latitude: 46.3500, longitude: -1.4333),
        WindsUpStation(id: 1529, name: "Saint Jean de Monts", slug: "saint-jean-de-monts-", latitude: 46.8000, longitude: -2.0667),
        WindsUpStation(id: 1532, name: "Tharon Plage", slug: "tharon-plage-le-cormier", latitude: 47.1667, longitude: -2.1667),
        WindsUpStation(id: 1541, name: "Poitiers - St Cyr", slug: "poitiers-st-cyr-base-de-loisirs", latitude: 46.6333, longitude: 0.3833),
        WindsUpStation(id: 1611, name: "Noirmoutier - Barbâtre", slug: "noirmoutier-barbyctre-", latitude: 46.9423, longitude: -2.1733),
        WindsUpStation(id: 1614, name: "La Tremblade", slug: "la-tremblade", latitude: 45.7667, longitude: -1.1333),
        WindsUpStation(id: 1658, name: "Les Sables d'Olonne", slug: "les-sables-dolonne", latitude: 46.5000, longitude: -1.7833),
        WindsUpStation(id: 1669, name: "Saint Georges de Didonne", slug: "saint-georges-de-didonne", latitude: 45.5833, longitude: -1.0000),
        WindsUpStation(id: 1671, name: "Notre-Dame-De-Monts", slug: "notre-dame-de-monts", latitude: 46.8500, longitude: -2.1333),
        WindsUpStation(id: 1680, name: "Saint-Brevin Estuaire", slug: "saint-brevin-estuaire", latitude: 47.2500, longitude: -2.1667),
        WindsUpStation(id: 1699, name: "Noirmoutier - La Linière", slug: "noirmoutier-la-liniere", latitude: 47.0167, longitude: -2.2500),
        WindsUpStation(id: 1710, name: "St Brevin Pecherie", slug: "st-brevin-pecherie", latitude: 47.2333, longitude: -2.1667),

        // === BRETAGNE ===
        WindsUpStation(id: 7, name: "La Baule", slug: "la-baule", latitude: 47.2811, longitude: -2.38417),
        WindsUpStation(id: 12, name: "Chèvre", slug: "chyivre", latitude: 48.2283, longitude: -4.50141),
        WindsUpStation(id: 15, name: "Dossen", slug: "dossen", latitude: 48.7023, longitude: -4.05348),
        WindsUpStation(id: 19, name: "Fort Bloqué", slug: "fort-bloque", latitude: 47.7336, longitude: -3.49892),
        WindsUpStation(id: 28, name: "Lancieux - Le Briantais", slug: "lancieux-le-briantais", latitude: 48.6084, longitude: -2.15619),
        WindsUpStation(id: 33, name: "Pont-Mahé", slug: "pont-mahyo", latitude: 47.4463, longitude: -2.45405),
        WindsUpStation(id: 34, name: "Saint Malo", slug: "saint-malo", latitude: 48.6531, longitude: -2.01313),
        WindsUpStation(id: 37, name: "Brest - Keraliou", slug: "brest-keraliou", latitude: 48.3812, longitude: -4.40727),
        WindsUpStation(id: 41, name: "Quiberon", slug: "quiberon", latitude: 47.5511, longitude: -3.13268),
        WindsUpStation(id: 55, name: "Val André", slug: "val-andre", latitude: 48.5878, longitude: -2.55751),
        WindsUpStation(id: 62, name: "Mazerolles", slug: "mazerolles", latitude: 47.3621, longitude: -1.50899),
        WindsUpStation(id: 66, name: "Douarnenez Pentrez", slug: "douarnenez-pentrez", latitude: 48.1828, longitude: -4.29253),
        WindsUpStation(id: 89, name: "Guissény", slug: "guisseny", latitude: 48.6392, longitude: -4.44662),
        WindsUpStation(id: 108, name: "Brignogan", slug: "brignogan", latitude: 48.6729, longitude: -4.32752),
        WindsUpStation(id: 116, name: "Penvins", slug: "penvins", latitude: 47.495, longitude: -2.68223),
        WindsUpStation(id: 132, name: "Plouescat", slug: "plouescat", latitude: 48.6505, longitude: -4.21309),
        WindsUpStation(id: 134, name: "Le Rohu - St Gildas", slug: "le-rohu-st-gildas-de-rhuys", latitude: 47.5188, longitude: -2.85707),
        WindsUpStation(id: 1524, name: "Le Steir Penmarc'h", slug: "le-steir-penmarch-", latitude: 47.7998, longitude: -4.3311),
        WindsUpStation(id: 1559, name: "Brest - Pôle France", slug: "brest-pyele-france", latitude: 48.3874, longitude: -4.43451),
        WindsUpStation(id: 1566, name: "Bénodet Dune", slug: "benodet-dune", latitude: 47.8623, longitude: -4.08461),
        WindsUpStation(id: 1667, name: "La Torche", slug: "la-torche-st-jean-trolimon", latitude: 47.8525, longitude: -4.34792),
        WindsUpStation(id: 1674, name: "Saint Pierre Quiberon", slug: "saint-pierre-quiberon-", latitude: 47.5369, longitude: -3.14),
        WindsUpStation(id: 1683, name: "Sainte-Marguerite", slug: "sainte-marguerite", latitude: 48.5935, longitude: -4.60594),
        WindsUpStation(id: 1697, name: "Treompan Dunes", slug: "treompan-dunes-3-moutons", latitude: 48.5715, longitude: -4.66336),
        WindsUpStation(id: 1705, name: "Kersidan", slug: "kersidan", latitude: 47.7973, longitude: -3.82717),

        // === MANCHE / NORD ===
        WindsUpStation(id: 13, name: "Le Crotoy", slug: "le-crotoy", latitude: 50.2141, longitude: 1.62614),
        WindsUpStation(id: 16, name: "Dunkerque", slug: "dunkerque", latitude: 51.0543, longitude: 2.41481),
        WindsUpStation(id: 24, name: "Ouistreham - Colleville", slug: "ouistreham-colleville", latitude: 49.2947, longitude: -0.28737),
        WindsUpStation(id: 40, name: "Wissant", slug: "wissant", latitude: 50.8876, longitude: 1.65834),
        WindsUpStation(id: 56, name: "Wimereux", slug: "wimereux", latitude: 50.7641, longitude: 1.60559),
        WindsUpStation(id: 57, name: "Berck", slug: "berck", latitude: 50.4053, longitude: 1.55768),
        WindsUpStation(id: 93, name: "Vauville - Siouville", slug: "vauville-siouville", latitude: 49.5333, longitude: -1.8333),
        WindsUpStation(id: 95, name: "Jonville", slug: "jonville", latitude: 49.4667, longitude: -1.2500),
        WindsUpStation(id: 96, name: "Le Havre Saint Adresse", slug: "le-havre-saint-adresse", latitude: 49.5056, longitude: 0.0833),
        WindsUpStation(id: 100, name: "Le Touquet", slug: "le-touquet", latitude: 50.5172, longitude: 1.57857),
        WindsUpStation(id: 101, name: "Calais", slug: "calais", latitude: 50.9762, longitude: 1.89672),
        WindsUpStation(id: 109, name: "Jullouville", slug: "jullouville", latitude: 48.7667, longitude: -1.5667),
        WindsUpStation(id: 112, name: "Gravelines", slug: "gravelines", latitude: 51.0000, longitude: 2.1333),
        WindsUpStation(id: 115, name: "Hardelot-Plage", slug: "hardelot-plage", latitude: 50.6333, longitude: 1.5833),
        WindsUpStation(id: 128, name: "Quineville", slug: "quineville", latitude: 49.5167, longitude: -1.2333),
        WindsUpStation(id: 130, name: "Asnelles", slug: "asnelles-poste-de-secours", latitude: 49.3333, longitude: -0.5833),
        WindsUpStation(id: 1534, name: "Cayeux sur Mer", slug: "cayeux-sur-mer", latitude: 50.1833, longitude: 1.5000),
        WindsUpStation(id: 1603, name: "Franceville", slug: "franceville", latitude: 49.2833, longitude: -0.1000),
        WindsUpStation(id: 1638, name: "Trouville CN", slug: "trouville-cn", latitude: 49.3667, longitude: 0.0833),

        // === LACS & INTÉRIEUR ===
        WindsUpStation(id: 17, name: "Épervière", slug: "eperviere", latitude: 44.9333, longitude: 4.8833),
        WindsUpStation(id: 21, name: "La Ganguise", slug: "la-ganguise", latitude: 43.3500, longitude: 1.9167),
        WindsUpStation(id: 31, name: "Lyon - Miribel", slug: "lyon-miribel", latitude: 45.8167, longitude: 4.9333),
        WindsUpStation(id: 32, name: "Madine", slug: "madine", latitude: 48.9333, longitude: 5.7333),
        WindsUpStation(id: 35, name: "Moisson", slug: "moisson", latitude: 49.0667, longitude: 1.6667),
        WindsUpStation(id: 36, name: "Monteynard", slug: "monteynard-ketos-foil", latitude: 44.9167, longitude: 5.7000),
        WindsUpStation(id: 38, name: "Montélimar", slug: "montelimar", latitude: 44.5667, longitude: 4.7500),
        WindsUpStation(id: 42, name: "Lac forêt d'Orient", slug: "lac-foret-dorient", latitude: 48.2833, longitude: 4.3500),
        WindsUpStation(id: 47, name: "Lac de Serre-Ponçon", slug: "lac-de-serre-ponyion-plage-du-boscodon", latitude: 44.5167, longitude: 6.3333),
        WindsUpStation(id: 52, name: "Vaires sur Marne", slug: "vaires-sur-marne-", latitude: 48.8667, longitude: 2.6333),
        WindsUpStation(id: 85, name: "Lac du Der", slug: "lac-du-der", latitude: 48.5667, longitude: 4.7500),
        WindsUpStation(id: 127, name: "La Grande Paroisse", slug: "la-grande-paroisse", latitude: 48.3833, longitude: 2.9000),
        WindsUpStation(id: 138, name: "Lyon - Le Grand Large", slug: "lyon-le-grand-large", latitude: 45.7833, longitude: 5.0500),
        WindsUpStation(id: 1527, name: "Pierrelatte", slug: "pierrelatte", latitude: 44.3833, longitude: 4.6833),
        WindsUpStation(id: 1539, name: "Ceüze", slug: "ceuze", latitude: 44.5167, longitude: 5.9500),
        WindsUpStation(id: 1688, name: "Étang de Gondrexange", slug: "etang-de-gondrexange-acal", latitude: 48.7000, longitude: 6.9167),
        WindsUpStation(id: 1704, name: "Jablines", slug: "jablines", latitude: 48.9167, longitude: 2.7333),
        WindsUpStation(id: 1711, name: "Lac de Thoux", slug: "lac-de-thoux-saint-cricq", latitude: 43.6833, longitude: 0.8500),
        WindsUpStation(id: 1712, name: "Lac de Jouarres", slug: "lac-de-jouarres", latitude: 43.8833, longitude: 2.4000),
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    /// Login to WindsUp with your paid account
    func login(email: String, password: String) async throws -> Bool {
        // Fetch login page first to get session
        guard let loginPageUrl = URL(string: "https://www.winds-up.com/index.php?p=connexion") else {
            throw WindsUpError.invalidURL
        }

        // POST to index.php (form action)
        guard let postUrl = URL(string: "https://www.winds-up.com/index.php") else {
            throw WindsUpError.invalidURL
        }

        var request = URLRequest(url: postUrl)
        request.httpMethod = "POST"
        request.setValue("https://www.winds-up.com/index.php?p=connexion", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        // First, fetch the login page to understand the form
        var pageRequest = URLRequest(url: loginPageUrl)
        pageRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let (pageData, _) = try await session.data(for: pageRequest)
        let pageHtml = String(data: pageData, encoding: .utf8) ?? ""

        Log.debug("WindsUp: Login page length: \(pageHtml.count)")

        // Debug: look for form details
        if let formMatch = pageHtml.range(of: #"<form[^>]*name="formu_login"[^>]*>"#, options: .regularExpression) {
            let formTag = String(pageHtml[formMatch])
            Log.debug("WindsUp: Form tag: \(formTag)")
        }

        // Look for all input fields in the form
        let inputPattern = #"<input[^>]*name="([^"]+)"[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: inputPattern, options: []) {
            let matches = regex.matches(in: pageHtml, options: [], range: NSRange(pageHtml.startIndex..., in: pageHtml))
            let fieldNames = matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: pageHtml) else { return nil }
                return String(pageHtml[range])
            }
            Log.debug("WindsUp: Form fields found: \(fieldNames.joined(separator: ", "))")
        }

        // Look for hidden token field (extracted for debugging, not used in login)
        if let tokenMatch = pageHtml.range(of: #"name="token"\s+value="([^"]+)""#, options: .regularExpression) {
            let fullMatch = String(pageHtml[tokenMatch])
            if let valueRange = fullMatch.range(of: #"value="([^"]+)""#, options: .regularExpression) {
                let _token = String(fullMatch[valueRange]).replacingOccurrences(of: "value=\"", with: "").replacingOccurrences(of: "\"", with: "")
                Log.debug("WindsUp: Found token: \(_token.prefix(10))...")
            }
        }

        // Use multipart/form-data as specified by the form
        let boundary = "----WebKitFormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body - include ALL form fields
        var body = Data()
        let formFields: [(String, String)] = [
            ("login_pseudo", email),
            ("login_passwd", password),
            ("action", "login"),
            ("p", "connexion"),
            ("id", ""),
            ("cat", ""),
            ("aff", ""),
            ("rester_log", "1"),
            ("MAX_FILE_SIZE", "500000")
        ]

        for (name, value) in formFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        Log.debug("WindsUp: Attempting login for \(email) with multipart form: \(formFields.map { $0.0 }.joined(separator: ", "))...")

        // Debug: print cookies being sent
        if let cookies = HTTPCookieStorage.shared.cookies(for: postUrl) {
            Log.debug("WindsUp: Sending \(cookies.count) cookies with POST")
            for cookie in cookies {
                Log.debug("WindsUp: -> \(cookie.name)")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WindsUpError.invalidResponse
        }

        Log.debug("WindsUp: Login response status: \(httpResponse.statusCode)")

        // Check cookies
        let cookies = HTTPCookieStorage.shared.cookies(for: postUrl) ?? []
        for cookie in cookies {
            Log.debug("WindsUp: Cookie - \(cookie.name): \(cookie.value.prefix(20))...")
        }

        // Check response for login success indicators
        if let html = String(data: data, encoding: .utf8) {
            Log.debug("WindsUp: Response length: \(html.count) chars")

            // Debug: show part of response to understand what we got
            if html.contains("Déconnexion") || html.contains("deconnexion") {
                Log.debug("WindsUp: Found 'Déconnexion' - login successful!")
                isAuthenticated = true
                return true
            }

            if html.contains("Mon compte") || html.contains("mon-compte") {
                Log.debug("WindsUp: Found 'Mon compte' - login successful!")
                isAuthenticated = true
                return true
            }

            // Look for user name in response (indicates logged in)
            if html.contains("Paul29") || html.contains("paul29") {
                Log.debug("WindsUp: Found username in response - login successful!")
                isAuthenticated = true
                return true
            }

            // Check for error messages
            if html.contains("Identifiant ou mot de passe incorrect") {
                Log.debug("WindsUp: Login failed - invalid credentials")
                return false
            }

            // Debug: print key parts of response
            Log.debug("WindsUp: Response contains 'Connexion': \(html.contains("Connexion"))")
            Log.debug("WindsUp: Response contains 'Déconnexion': \(html.contains("Déconnexion"))")
            Log.debug("WindsUp: Response contains 'pseudo': \(html.contains("pseudo"))")
            Log.debug("WindsUp: Response contains 'erreur': \(html.contains("erreur"))")

            // Print title of page
            if let titleStart = html.range(of: "<title>"),
               let titleEnd = html.range(of: "</title>") {
                let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
                Log.debug("WindsUp: Page title: \(title)")
            }

            // Look for any user-related text
            let searchTerms = ["abonnement", "premium", "compte", "profil", "bienvenue", "membre", "paul29", "Paul29", "Bonjour"]
            for term in searchTerms {
                if html.lowercased().contains(term.lowercased()) {
                    Log.debug("WindsUp: Found '\(term)' in response")
                }
            }

            // Print a snippet of the response to debug
            let startIndex = html.index(html.startIndex, offsetBy: min(5000, html.count))
            let snippet = String(html[..<startIndex])
            if snippet.contains("login") || snippet.contains("pseudo") {
                Log.debug("WindsUp: Response seems to still show login form")
            }

            // Look for specific login success indicators
            if html.contains("Mon espace") || html.contains("mon-espace") {
                Log.debug("WindsUp: Found 'Mon espace' - login successful!")
                isAuthenticated = true
                return true
            }
        }

        // Check for the specific auth cookies that indicate successful login
        let hasAutolog = cookies.contains { $0.name == "autolog" }
        let hasCodeCnx = cookies.contains { $0.name == "codeCnx" }

        Log.debug("WindsUp: Has 'autolog' cookie: \(hasAutolog)")
        Log.debug("WindsUp: Has 'codeCnx' cookie: \(hasCodeCnx)")

        if hasAutolog && hasCodeCnx {
            Log.debug("WindsUp: Login successful - found autolog and codeCnx cookies!")
            isAuthenticated = true
            return true
        }

        if hasAutolog || hasCodeCnx {
            Log.debug("WindsUp: Partial auth cookies found")
            isAuthenticated = true
            return true
        }

        // Fallback: just PHPSESSID is not enough
        Log.debug("WindsUp: Login failed - missing autolog/codeCnx cookies")

        Log.debug("WindsUp: Login status uncertain")
        return false
    }

    // MARK: - Fetch Station Data

    func fetchStationData(station: WindsUpStation) async throws -> WindsUpStationData {
        // Check cache
        if let cached = cache[station.id],
           Date().timeIntervalSince(cached.date) < cacheDuration {
            Log.debug("WindsUp: Using cached data for \(station.name)")
            return cached.data
        }

        guard let url = station.observationsURL else {
            throw WindsUpError.invalidURL
        }

        Log.debug("WindsUp: Fetching \(station.name) from \(url)")

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.winds-up.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.debug("WindsUp: Invalid response for \(station.name)")
            throw WindsUpError.fetchFailed
        }

        Log.debug("WindsUp: \(station.name) response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw WindsUpError.fetchFailed
        }

        // Try UTF-8 first, then ISO-8859-1 (Latin-1) which is common for French sites
        var html: String?
        html = String(data: data, encoding: .utf8)
        if html == nil {
            html = String(data: data, encoding: .isoLatin1)
            Log.debug("WindsUp: \(station.name) using ISO-8859-1 encoding")
        }
        if html == nil {
            html = String(data: data, encoding: .windowsCP1252)
            Log.debug("WindsUp: \(station.name) using Windows-1252 encoding")
        }

        guard let htmlContent = html else {
            Log.debug("WindsUp: \(station.name) - could not decode HTML")
            throw WindsUpError.invalidData
        }

        Log.debug("WindsUp: \(station.name) HTML length: \(htmlContent.count)")

        let stationData = try parseStationHTML(html: htmlContent, station: station)

        Log.debug("WindsUp: \(station.name) parsed - \(stationData.observations.count) observations, wind: \(stationData.currentWind ?? -1)")

        // Cache result
        cache[station.id] = (stationData, Date())

        return stationData
    }

    // MARK: - Parse HTML

    private func parseStationHTML(html: String, station: WindsUpStation) throws -> WindsUpStationData {
        var observations: [WindsUpObservation] = []
        var currentWind: Double?
        var currentGust: Double?
        var currentDirection: String?
        var minWind: Double?
        var maxWind: Double?

        // Check if station is broken/down
        // Message: "Spot en panne - les relevés indiqués ne sont probablement pas représentatifs de la réalité"
        let isBroken = html.contains("Spot en panne") || html.contains("spot en panne")

        if isBroken {
            Log.debug("WindsUp: \(station.name) - SPOT EN PANNE detected, marking as broken")
            // Return empty data for broken stations
            return WindsUpStationData(
                station: station,
                observations: [],
                currentWind: nil,
                currentGust: nil,
                currentDirection: nil,
                minWind: nil,
                maxWind: nil,
                isBroken: true
            )
        }

        // Parse Highcharts data embedded in JavaScript
        // Look for data: [{x:..., y:..., o:...}, ...] pattern
        // Need to find the closing ]} that matches our opening [{
        if let dataMatch = html.range(of: #"data:\s*\[\{x:"#, options: .regularExpression) {
            let startIndex = dataMatch.lowerBound
            let searchStart = html.index(after: dataMatch.lowerBound) // Skip past "data:"

            // Find matching closing bracket by counting
            var bracketCount = 0
            var endIndex: String.Index? = nil

            for (offset, char) in html[searchStart...].enumerated() {
                if char == "[" { bracketCount += 1 }
                else if char == "]" {
                    bracketCount -= 1
                    if bracketCount == 0 {
                        endIndex = html.index(searchStart, offsetBy: offset + 1)
                        break
                    }
                }
            }

            if let end = endIndex {
                let dataString = String(html[startIndex..<end])
                Log.debug("WindsUp: Data chunk length: \(dataString.count)")
                observations = parseHighchartsData(dataString)
            }
        }

        // Alternative: Search directly for individual data points in the HTML
        if observations.isEmpty {
            Log.debug("WindsUp: Trying direct pattern search on full HTML")
            observations = parseHighchartsData(html)
        }

        // Get current values from the most recent observation
        if let latest = observations.first {
            currentWind = latest.windSpeed
            currentGust = latest.gustSpeed  // Use actual gust from latest observation
            currentDirection = latest.windDirection
            Log.debug("WindsUp: Latest obs - wind: \(latest.windSpeed), gust: \(latest.gustSpeed ?? 0), dir: '\(latest.windDirection)', time: \(latest.timestamp)")
        }

        // Calculate min/max from observations
        let speeds = observations.map { $0.windSpeed }
        minWind = speeds.min()
        maxWind = speeds.max()

        return WindsUpStationData(
            station: station,
            observations: observations,
            currentWind: currentWind,
            currentGust: currentGust,
            currentDirection: currentDirection,
            minWind: minWind,
            maxWind: maxWind,
            isBroken: false
        )
    }

    private func parseHighchartsData(_ dataString: String) -> [WindsUpObservation] {
        var observations: [WindsUpObservation] = []

        // Actual format: {x:1767372664000, y:14, o:"N", color:"#1DEE44", img:"...", min:"10", max:"23", abo:""}
        // Pattern captures: x (timestamp), y (wind), o (direction)
        let pattern = #"\{x:(\d+),\s*y:(\d+(?:\.\d+)?),\s*o:"([^"]+)"[^}]*\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            Log.debug("WindsUp: Failed to create regex")
            return observations
        }

        // Separate pattern for max (gust) extraction
        let maxPattern = #"max:"(\d+)""#
        let maxRegex = try? NSRegularExpression(pattern: maxPattern, options: [])

        let matches = regex.matches(in: dataString, options: [], range: NSRange(dataString.startIndex..., in: dataString))
        Log.debug("WindsUp: Found \(matches.count) data points in chunk")

        var gustFoundCount = 0
        for match in matches {
            guard let timestampRange = Range(match.range(at: 1), in: dataString),
                  let speedRange = Range(match.range(at: 2), in: dataString),
                  let directionRange = Range(match.range(at: 3), in: dataString) else {
                continue
            }

            let timestampMs = Double(dataString[timestampRange]) ?? 0
            let speed = Double(dataString[speedRange]) ?? 0
            let direction = String(dataString[directionRange])

            // Extract the full object to search for max value
            let fullMatchRange = match.range(at: 0)
            var gust: Double? = nil
            if let objRange = Range(fullMatchRange, in: dataString),
               let maxRegex = maxRegex {
                let objString = String(dataString[objRange])
                if let maxMatch = maxRegex.firstMatch(in: objString, options: [], range: NSRange(objString.startIndex..., in: objString)),
                   let maxValueRange = Range(maxMatch.range(at: 1), in: objString) {
                    gust = Double(objString[maxValueRange])
                    gustFoundCount += 1
                }
            }

            // WindsUp timestamps are in French local time (UTC+1), adjust to UTC
            let date = Date(timeIntervalSince1970: (timestampMs / 1000) - 3600)

            let obs = WindsUpObservation(
                timestamp: date,
                windSpeed: speed,
                windDirection: direction,
                windDirectionDegrees: directionToDegrees(direction),
                gustSpeed: gust
            )
            observations.append(obs)
        }

        // Sort by timestamp descending (most recent first)
        observations.sort { $0.timestamp > $1.timestamp }

        Log.debug("WindsUp: Parsed \(observations.count) observations, \(gustFoundCount) with gust data")
        return observations
    }

    func directionToDegrees(_ direction: String) -> Double? {
        let directions: [String: Double] = [
            "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5,
            "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
            "S": 180, "SSO": 202.5, "SO": 225, "OSO": 247.5,
            "O": 270, "ONO": 292.5, "NO": 315, "NNO": 337.5,
            // English variants
            "SSW": 202.5, "SW": 225, "WSW": 247.5,
            "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5
        ]
        return directions[direction.uppercased()]
    }

    // MARK: - Fetch All Stations

    func fetchAllStations(_ stations: [WindsUpStation] = defaultStations) async -> [WindsUpStationData] {
        var results: [WindsUpStationData] = []

        await withTaskGroup(of: (String, WindsUpStationData?).self) { group in
            for station in stations {
                group.addTask {
                    do {
                        let data = try await self.fetchStationData(station: station)
                        return (station.name, data)
                    } catch {
                        Log.debug("WindsUp: Error fetching \(station.name): \(error)")
                        return (station.name, nil)
                    }
                }
            }

            for await (name, result) in group {
                if let data = result {
                    results.append(data)
                } else {
                    Log.debug("WindsUp: No data for \(name)")
                }
            }
        }

        return results
    }

    // MARK: - Fetch as WindStation (for integration with WindStationManager)

    /// Fetches WindsUp stations and returns them as WindStation objects
    /// Requires prior authentication via WebView
    func fetchWindStations() async -> [WindStation] {
        // Check if we have valid auth cookies from WebView login
        if !checkAuthCookies() {
            Log.debug("WindsUp: Not authenticated - please login via WebView")
            return []
        }

        Log.debug("WindsUp: Auth cookies found, fetching stations...")

        // Fetch all stations
        Log.debug("WindsUp: Fetching \(Self.defaultStations.count) stations...")
        let stationDataList = await fetchAllStations()
        Log.debug("WindsUp: Got \(stationDataList.count) station data")

        // Convert to WindStation
        let windStations = stationDataList.compactMap { $0.toWindStation() }
        Log.debug("WindsUp: Converted to \(windStations.count) WindStations")

        for station in windStations {
            Log.debug("WindsUp: Station '\(station.name)' - \(station.wind) kts, dir \(station.direction)°")
        }

        return windStations
    }
}

// MARK: - Errors

enum WindsUpError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case fetchFailed
    case invalidData
    case notAuthenticated
    case loginFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invalide"
        case .invalidResponse: return "Réponse invalide"
        case .fetchFailed: return "Échec du chargement"
        case .invalidData: return "Données invalides"
        case .notAuthenticated: return "Non authentifié"
        case .loginFailed: return "Échec de connexion"
        }
    }
}

// MARK: - Convert to WindStation for integration

extension WindsUpStationData {
    func toWindStation() -> WindStation? {
        // Skip broken stations entirely - they have unreliable data
        if isBroken {
            Log.debug("WindsUp: Skipping broken station \(station.name)")
            return nil
        }

        guard let wind = currentWind,
              let dirString = currentDirection else {
            return nil
        }

        let direction = WindsUpService.shared.directionToDegrees(dirString) ?? 0

        // Check if data is valid and recent (less than 30 minutes old, not in future)
        let isValid: Bool
        if let lastObs = observations.first?.timestamp {
            let timeDiff = Date().timeIntervalSince(lastObs)
            isValid = timeDiff >= 0 && timeDiff < 1800
        } else {
            isValid = false
        }

        // Don't show stations with stale or invalid data
        guard isValid else {
            Log.debug("WindsUp: Skipping \(station.name) - invalid or stale data")
            return nil
        }

        return WindStation(
            id: "windsup_\(station.id)",
            name: station.name,
            latitude: station.latitude,
            longitude: station.longitude,
            wind: wind,
            gust: currentGust ?? wind,  // Use actual gust from latest observation
            direction: direction,
            isOnline: true,
            source: .windsUp,
            lastUpdate: observations.first?.timestamp
        )
    }
}
