import Foundation

// MARK: - Shared Widget Types (App-side copy)
// These types must match the ones in AnemOuestWidget/WidgetData.swift

struct WidgetStationData: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let source: String
    let wind: Double
    let gust: Double
    let direction: Double
    let isOnline: Bool
    let lastUpdate: Date?
}

// MARK: - Widget Wave Buoy Data

struct WidgetWaveBuoyData: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let region: String
    let hm0: Double?           // Significant wave height (meters)
    let tp: Double?            // Peak period (seconds)
    let direction: Double?     // Wave direction (degrees)
    let seaTemp: Double?       // Sea temperature (°C)
    let isOnline: Bool
    let lastUpdate: Date?

    /// Formatted wave height display
    var waveHeightDisplay: String {
        guard let hm0 = hm0 else { return "—" }
        return String(format: "%.1f", hm0)
    }

    /// Formatted period display
    var periodDisplay: String {
        guard let tp = tp else { return "—" }
        return String(format: "%.1f", tp)
    }
}

// MARK: - Widget Forecast Data

struct WidgetForecastHour: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let windSpeed: Double      // knots
    let gustSpeed: Double      // knots
    let windDirection: Double  // degrees
    let weatherCode: Int       // WMO weather code
}

struct WidgetForecastData: Codable, Equatable {
    let stationId: String
    let stationName: String
    let hourly: [WidgetForecastHour]
    let lastUpdate: Date

    var next6Hours: [WidgetForecastHour] {
        let now = Date()
        return hourly.filter { $0.time >= now }.prefix(6).map { $0 }
    }
}

// MARK: - Widget Tide Data

struct WidgetTideEvent: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let height: Double
    let type: TideType

    enum TideType: String, Codable {
        case high = "high"
        case low = "low"
    }
}

struct WidgetTideData: Codable, Equatable {
    let locationName: String
    let events: [WidgetTideEvent]
    let coefficient: Int?
    let lastUpdate: Date

    var nextEvents: [WidgetTideEvent] {
        let now = Date()
        return events.filter { $0.time >= now }.prefix(2).map { $0 }
    }
}

// MARK: - Widget Configuration

struct AnemWidgetConfig: Codable {
    var smallWidgetStationId: String?
    var mediumWidgetStationIds: [String]
    var largeWidgetStationIds: [String]
    var showGustSpeed: Bool
    var showDirection: Bool
    var showLastUpdate: Bool
    var showOnlineStatus: Bool
    var colorTheme: WidgetColorTheme
    var windUnit: WindUnit

    init() {
        self.smallWidgetStationId = nil
        self.mediumWidgetStationIds = []
        self.largeWidgetStationIds = []
        self.showGustSpeed = true
        self.showDirection = true
        self.showLastUpdate = true
        self.showOnlineStatus = true
        self.colorTheme = .auto
        self.windUnit = .knots
    }
}

enum WidgetColorTheme: String, Codable, CaseIterable {
    case auto = "Auto"
    case light = "Clair"
    case dark = "Sombre"
    case colorful = "Coloré"
}

enum WindUnit: String, Codable, CaseIterable {
    case knots = "Nœuds"
    case kmh = "km/h"
    case ms = "m/s"
    case mph = "mph"

    var symbol: String {
        switch self {
        case .knots: return "nds"
        case .kmh: return "km/h"
        case .ms: return "m/s"
        case .mph: return "mph"
        }
    }

    func convert(fromKnots knots: Double) -> Double {
        switch self {
        case .knots: return knots
        case .kmh: return knots * 1.852
        case .ms: return knots * 0.514444
        case .mph: return knots * 1.15078
        }
    }

    /// Key used for storing wind unit in both standard and shared defaults
    static let windUnitKey = "windUnit"

    /// Get the current user-selected wind unit
    static var current: WindUnit {
        let raw = UserDefaults.standard.string(forKey: windUnitKey) ?? WindUnit.knots.rawValue
        return WindUnit(rawValue: raw) ?? .knots
    }

    /// Sync the current wind unit to App Group for widget access
    static func syncToAppGroup() {
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            sharedDefaults.set(current.rawValue, forKey: windUnitKey)
            sharedDefaults.synchronize()
        }
    }

    /// Format a wind value (in knots) for display with current unit
    static func format(_ knots: Double) -> String {
        let unit = current
        let converted = unit.convert(fromKnots: knots)
        return "\(Int(round(converted))) \(unit.symbol)"
    }

    /// Format a wind value without unit symbol
    static func formatValue(_ knots: Double) -> String {
        let unit = current
        let converted = unit.convert(fromKnots: knots)
        return "\(Int(round(converted)))"
    }

    /// Convert a value from knots to current unit
    static func convertValue(_ knots: Double) -> Int {
        Int(round(current.convert(fromKnots: knots)))
    }
}

// MARK: - App Group Manager (App-side)

final class AppGroupManager {
    static let shared = AppGroupManager()

    private let appGroupId = AppConstants.appGroupId
    private let favoritesKey = "widgetFavorites"
    private let waveBuoysKey = "widgetWaveBuoys"
    private let forecastKey = "widgetForecast"
    private let tideKey = "widgetTide"
    private let configKey = "widgetConfiguration"

    private var sharedDefaults: UserDefaults? {
        let defaults = UserDefaults(suiteName: appGroupId)
        if defaults == nil {
            Log.warning("AppGroup: Failed to access UserDefaults for \(appGroupId)")
        }
        return defaults
    }

    private init() {
        Log.widget("AppGroupManager initialized with group: \(appGroupId)")
    }

    func saveFavoritesForWidget(_ stations: [WidgetStationData]) {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot save - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(stations)
            defaults.set(data, forKey: favoritesKey)
            defaults.synchronize() // Force sync
            Log.success("AppGroup: Saved \(stations.count) stations to widget data")
            for station in stations {
                Log.debug("   - \(station.name) (\(station.source))")
            }
        } catch {
            Log.error("AppGroup: Failed to save widget data: \(error)")
        }
    }

    func loadFavoritesForWidget() -> [WidgetStationData] {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot load - sharedDefaults is nil")
            return []
        }
        guard let data = defaults.data(forKey: favoritesKey) else {
            Log.warning("AppGroup: No data found for key '\(favoritesKey)'")
            return []
        }
        do {
            let stations = try JSONDecoder().decode([WidgetStationData].self, from: data)
            Log.success("AppGroup: Loaded \(stations.count) stations from widget data")
            return stations
        } catch {
            Log.error("AppGroup: Failed to load widget data: \(error)")
            return []
        }
    }

    // MARK: - Wave Buoy Data

    func saveWaveBuoysForWidget(_ buoys: [WidgetWaveBuoyData]) {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot save wave buoys - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(buoys)
            defaults.set(data, forKey: waveBuoysKey)
            defaults.synchronize()
            Log.success("AppGroup: Saved \(buoys.count) wave buoys to widget data")
        } catch {
            Log.error("AppGroup: Failed to save wave buoy data: \(error)")
        }
    }

    func loadWaveBuoysForWidget() -> [WidgetWaveBuoyData] {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot load wave buoys - sharedDefaults is nil")
            return []
        }
        guard let data = defaults.data(forKey: waveBuoysKey) else {
            Log.warning("AppGroup: No wave buoy data found")
            return []
        }
        do {
            let buoys = try JSONDecoder().decode([WidgetWaveBuoyData].self, from: data)
            Log.success("AppGroup: Loaded \(buoys.count) wave buoys from widget data")
            return buoys
        } catch {
            Log.error("AppGroup: Failed to load wave buoy data: \(error)")
            return []
        }
    }

    func saveConfiguration(_ config: AnemWidgetConfig) {
        guard let defaults = sharedDefaults else { return }
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: configKey)
        } catch {
            Log.error("Failed to save widget config: \(error)")
        }
    }

    func loadConfiguration() -> AnemWidgetConfig {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: configKey) else {
            return AnemWidgetConfig()
        }
        do {
            return try JSONDecoder().decode(AnemWidgetConfig.self, from: data)
        } catch {
            Log.error("Failed to load widget config: \(error)")
            return AnemWidgetConfig()
        }
    }

    // MARK: - Forecast Data

    func saveForecastForWidget(_ forecast: WidgetForecastData) {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot save forecast - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(forecast)
            defaults.set(data, forKey: forecastKey)
            defaults.synchronize()
            Log.success("AppGroup: Saved forecast for \(forecast.stationName)")
        } catch {
            Log.error("AppGroup: Failed to save forecast: \(error)")
        }
    }

    func loadForecastForWidget() -> WidgetForecastData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: forecastKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetForecastData.self, from: data)
        } catch {
            Log.error("AppGroup: Failed to load forecast: \(error)")
            return nil
        }
    }

    // MARK: - Tide Data

    func saveTideForWidget(_ tide: WidgetTideData) {
        guard let defaults = sharedDefaults else {
            Log.error("AppGroup: Cannot save tide - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(tide)
            defaults.set(data, forKey: tideKey)
            defaults.synchronize()
            Log.success("AppGroup: Saved tide for \(tide.locationName)")
        } catch {
            Log.error("AppGroup: Failed to save tide: \(error)")
        }
    }

    func loadTideForWidget() -> WidgetTideData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: tideKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetTideData.self, from: data)
        } catch {
            Log.error("AppGroup: Failed to load tide: \(error)")
            return nil
        }
    }
}
