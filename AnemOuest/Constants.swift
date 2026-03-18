import Foundation
import CoreLocation

// MARK: - App Constants
/// Single source of truth for all hardcoded values across the app.

enum AppConstants {

    // MARK: - App Group

    static let appGroupId = "group.com.anemouest.shared"

    // MARK: - Background Tasks

    static let backgroundTaskIdentifier = "Wind.AnemOuest.windcheck"
    static let backgroundProcessingIdentifier = "Wind.AnemOuest.dataprocessing"
    static let backgroundFetchMinInterval: TimeInterval = 15 * 60 // 15 minutes (iOS minimum)

    // MARK: - Network Timeouts

    enum Timeout {
        static let standard: TimeInterval = 15
        static let extended: TimeInterval = 20
        static let heavy: TimeInterval = 30 // For large payloads (history.json ~3MB)
        static let quick: TimeInterval = 10 // For small/fast endpoints
        static let webcam: TimeInterval = 12  // Timeout for webcam images (Viewsurf can be slow)
        static let webcamThumbnail: TimeInterval = 6  // Shorter timeout for map thumbnails
    }

    // MARK: - User Agent

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - Cache TTL

    enum CacheTTL {
        static let webcamLive: TimeInterval = 60       // 1 minute
        static let webcamThumbnail: TimeInterval = 300  // 5 minutes
        static let webcamHistory: TimeInterval = 3600   // 1 hour
        static let webcamDiskMax: TimeInterval = 86400   // 24 hours
        static let windHistory: TimeInterval = 120       // 2 minutes
        static let forecastData: TimeInterval = 15 * 60  // 15 minutes
        static let tideData: TimeInterval = 60 * 60      // 1 hour
        static let marineData: TimeInterval = 30 * 60    // 30 minutes
    }

    // MARK: - Cache Limits

    enum CacheLimits {
        static let webcamMemoryCount = 80
        static let webcamMemoryBytes = 80 * 1024 * 1024  // ~80 MB
        static let webcamPrefetchCount = 30  // Prefetch more for faster scrolling
        static let webcamPrefetchBatchSize = 8  // Parallel fetch batch size
    }

    // MARK: - API Base URLs

    enum API {
        static let anemOuestAPI = "https://api.levent.live/api"
        static let key = "lv_R3POazDkm6rvLC5NKFNeTOwEu2oDnoN5"
    }

    /// Create a URLRequest pre-configured with the API key header
    static func apiRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(API.key, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    // MARK: - Default Refresh

    static let defaultRefreshInterval: Double = 30 // seconds
}

// MARK: - WindCornouaille Sensor Registry
/// All WindCornouaille sensors defined once.

enum WCSensors {

    struct Sensor: Identifiable, Hashable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

    }

    /// All WindCornouaille sensors
    static let all: [Sensor] = [
        Sensor(id: "6",        name: "Glénan",                    latitude: 47.71791,  longitude: -4.0088),
        Sensor(id: "7",        name: "Pointe de Trévignon",       latitude: 47.79325,  longitude: -3.85535),
        Sensor(id: "8",        name: "Pornichet",                 latitude: 47.258259, longitude: -2.35234),
        Sensor(id: "2",        name: "Sémaphore St Gildas",       latitude: 47.1337,   longitude: -2.24585),
        Sensor(id: "10",       name: "Phare de Port Navalo",      latitude: 47.5478,   longitude: -2.9183),
        Sensor(id: "5",        name: "Phare de la Teignouse",     latitude: 47.457333, longitude: -3.0458),
        Sensor(id: "73091286", name: "Feu de Kerroch",            latitude: 47.699518, longitude: -3.46097),
        Sensor(id: "73091264", name: "Phare des Cardinaux",       latitude: 47.321217, longitude: -2.834867),
        Sensor(id: "73091265", name: "Isthme",                    latitude: 47.550833, longitude: -3.134722),
        Sensor(id: "73091277", name: "Sémaphore d'Etel",          latitude: 47.646112, longitude: -3.214433),
        Sensor(id: "73091304", name: "Phare du Four",             latitude: 47.2978046, longitude: -2.63425627),
        Sensor(id: "73091305", name: "Phare du Grand Charpentier", latitude: 47.222515, longitude: -2.315754),
        Sensor(id: "73091306", name: "Jetée Est St Nazaire",      latitude: 47.268821, longitude: -2.200842),
        Sensor(id: "10438252", name: "ENVSN Quiberon",            latitude: 47.5095,   longitude: -3.1194),
        Sensor(id: "4",        name: "Île Dumet",                 latitude: 47.411505, longitude: -2.620043),
        Sensor(id: "9",        name: "Île d'Arz",                 latitude: 47.595,    longitude: -2.81044),
        Sensor(id: "1",        name: "École de voile Océane",     latitude: 47.567,    longitude: -3.004),
        Sensor(id: "3",        name: "Noirmoutier",               latitude: 47.02458,  longitude: -2.3067),
    ]

    /// Quick lookup by sensor ID
    static let byId: [String: Sensor] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Names lookup (for FavoritesManager migration)
    static let names: [String: String] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })

    /// Subset used in background fetch (lightweight — only core sensors)
    static let backgroundFetchIds: [String] = ["6", "7", "8", "2", "10", "5"]
}
