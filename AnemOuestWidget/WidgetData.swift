import Foundation
import WidgetKit

// MARK: - Widget Logger (DEBUG only)

private func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

// MARK: - Shared Widget Data

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
        return String(format: "%.0f", tp)
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

    /// Get next 6 hours of forecast
    var next6Hours: [WidgetForecastHour] {
        let now = Date()
        return hourly
            .filter { $0.time >= now }
            .prefix(6)
            .map { $0 }
    }
}

// MARK: - Widget Tide Data

struct WidgetTideEvent: Codable, Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let height: Double         // meters
    let type: TideType         // high or low

    enum TideType: String, Codable {
        case high = "high"
        case low = "low"

        var symbol: String {
            switch self {
            case .high: return "↑"
            case .low: return "↓"
            }
        }

        var label: String {
            switch self {
            case .high: return "PM"
            case .low: return "BM"
            }
        }
    }
}

struct WidgetTideData: Codable, Equatable {
    let locationName: String
    let events: [WidgetTideEvent]
    let coefficient: Int?      // Tide coefficient (French specific)
    let lastUpdate: Date

    /// Get next 2 tide events
    var nextEvents: [WidgetTideEvent] {
        let now = Date()
        return events
            .filter { $0.time >= now }
            .prefix(2)
            .map { $0 }
    }

    /// Current tide state description
    var currentState: String {
        guard let next = nextEvents.first else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(next.type.label) \(formatter.string(from: next.time))"
    }
}

// MARK: - Widget Configuration

struct AnemWidgetConfig: Codable {
    // Small widget - single station selection
    var smallWidgetStationId: String?

    // Medium widget - up to 3 stations in order
    var mediumWidgetStationIds: [String]

    // Large widget - up to 6 stations in order
    var largeWidgetStationIds: [String]

    // Display options
    var showGustSpeed: Bool
    var showDirection: Bool
    var showLastUpdate: Bool
    var showOnlineStatus: Bool

    // Color theme
    var colorTheme: WidgetColorTheme

    // Unit
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
        // Use the wind unit from App settings by default
        self.windUnit = WindUnit.current
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

    private static let appGroupId = "group.com.anemouest.shared"
    private static let windUnitKey = "windUnit"

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

    /// Get the current user-selected wind unit (from App Group shared defaults)
    static var current: WindUnit {
        let defaults = UserDefaults(suiteName: appGroupId)
        let raw = defaults?.string(forKey: windUnitKey) ?? WindUnit.knots.rawValue
        return WindUnit(rawValue: raw) ?? .knots
    }

    /// Convert a value from knots to current unit
    static func convertValue(_ knots: Double) -> Int {
        Int(round(current.convert(fromKnots: knots)))
    }
}

// MARK: - App Group Manager

final class AppGroupManager {
    static let shared = AppGroupManager()

    private let appGroupId = "group.com.anemouest.shared"
    private let favoritesKey = "widgetFavorites"
    private let waveBuoysKey = "widgetWaveBuoys"
    private let forecastKey = "widgetForecast"
    private let tideKey = "widgetTide"
    private let configKey = "widgetConfiguration"
    private let lastKnownGoodKey = "widgetLastKnownGood"  // Stable cache that never gets cleared

    private var sharedDefaults: UserDefaults? {
        let defaults = UserDefaults(suiteName: appGroupId)
        if defaults == nil {
            debugLog("⚠️ Widget AppGroup: Failed to access UserDefaults for \(appGroupId)")
        }
        return defaults
    }

    private init() {
        debugLog("🔧 Widget AppGroupManager initialized with group: \(appGroupId)")
    }

    // MARK: - Last Known Good Data (Stable Cache)

    /// Save station data to the stable "last known good" cache.
    /// This cache is ONLY updated when we have verified fresh data.
    func saveLastKnownGood(_ stations: [WidgetStationData]) {
        guard let defaults = sharedDefaults else { return }
        do {
            let data = try JSONEncoder().encode(stations)
            defaults.set(data, forKey: lastKnownGoodKey)
            defaults.synchronize()
            debugLog("✅ Widget: Saved \(stations.count) stations to last-known-good cache")
        } catch {
            debugLog("❌ Widget: Failed to save last-known-good: \(error)")
        }
    }

    /// Load from the stable "last known good" cache.
    func loadLastKnownGood() -> [WidgetStationData] {
        guard let defaults = sharedDefaults else { return [] }
        guard let data = defaults.data(forKey: lastKnownGoodKey) else { return [] }
        do {
            return try JSONDecoder().decode([WidgetStationData].self, from: data)
        } catch {
            return []
        }
    }

    /// Get the best available data: favorites first, then last-known-good as fallback
    func getBestAvailableStations() -> [WidgetStationData] {
        let favorites = loadFavoritesForWidget()
        if !favorites.isEmpty {
            return favorites
        }
        let lastKnown = loadLastKnownGood()
        if !lastKnown.isEmpty {
            debugLog("⚠️ Widget: Using last-known-good cache as fallback")
            return lastKnown
        }
        return []
    }

    // MARK: - Favorites Data

    func saveFavoritesForWidget(_ stations: [WidgetStationData]) {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot save - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(stations)
            defaults.set(data, forKey: favoritesKey)
            defaults.synchronize()
            debugLog("✅ Widget: Saved \(stations.count) stations")
        } catch {
            debugLog("❌ Widget: Failed to save widget data: \(error)")
        }
    }

    func loadFavoritesForWidget() -> [WidgetStationData] {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot load - sharedDefaults is nil")
            return []
        }
        guard let data = defaults.data(forKey: favoritesKey) else {
            debugLog("⚠️ Widget: No data found for key '\(favoritesKey)'")
            return []
        }
        do {
            let stations = try JSONDecoder().decode([WidgetStationData].self, from: data)
            debugLog("✅ Widget: Loaded \(stations.count) stations")
            for station in stations {
                debugLog("   - \(station.name) (\(station.source))")
            }
            return stations
        } catch {
            debugLog("❌ Widget: Failed to decode: \(error)")
            return []
        }
    }

    // MARK: - Wave Buoy Data

    func saveWaveBuoysForWidget(_ buoys: [WidgetWaveBuoyData]) {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot save wave buoys - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(buoys)
            defaults.set(data, forKey: waveBuoysKey)
            defaults.synchronize()
            debugLog("✅ Widget: Saved \(buoys.count) wave buoys")
        } catch {
            debugLog("❌ Widget: Failed to save wave buoy data: \(error)")
        }
    }

    func loadWaveBuoysForWidget() -> [WidgetWaveBuoyData] {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot load wave buoys - sharedDefaults is nil")
            return []
        }
        guard let data = defaults.data(forKey: waveBuoysKey) else {
            debugLog("⚠️ Widget: No wave buoy data found")
            return []
        }
        do {
            let buoys = try JSONDecoder().decode([WidgetWaveBuoyData].self, from: data)
            debugLog("✅ Widget: Loaded \(buoys.count) wave buoys")
            return buoys
        } catch {
            debugLog("❌ Widget: Failed to decode wave buoys: \(error)")
            return []
        }
    }

    func getWaveBuoysForSmallWidget() -> [WidgetWaveBuoyData] {
        return Array(loadWaveBuoysForWidget().prefix(1))
    }

    func getWaveBuoysForMediumWidget() -> [WidgetWaveBuoyData] {
        return Array(loadWaveBuoysForWidget().prefix(3))
    }

    // MARK: - Forecast Data

    func saveForecastForWidget(_ forecast: WidgetForecastData) {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot save forecast - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(forecast)
            defaults.set(data, forKey: forecastKey)
            defaults.synchronize()
            debugLog("✅ Widget: Saved forecast for \(forecast.stationName)")
        } catch {
            debugLog("❌ Widget: Failed to save forecast: \(error)")
        }
    }

    func loadForecastForWidget() -> WidgetForecastData? {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot load forecast - sharedDefaults is nil")
            return nil
        }
        guard let data = defaults.data(forKey: forecastKey) else {
            debugLog("⚠️ Widget: No forecast data found")
            return nil
        }
        do {
            let forecast = try JSONDecoder().decode(WidgetForecastData.self, from: data)
            debugLog("✅ Widget: Loaded forecast for \(forecast.stationName)")
            return forecast
        } catch {
            debugLog("❌ Widget: Failed to decode forecast: \(error)")
            return nil
        }
    }

    // MARK: - Tide Data

    func saveTideForWidget(_ tide: WidgetTideData) {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot save tide - sharedDefaults is nil")
            return
        }
        do {
            let data = try JSONEncoder().encode(tide)
            defaults.set(data, forKey: tideKey)
            defaults.synchronize()
            debugLog("✅ Widget: Saved tide for \(tide.locationName)")
        } catch {
            debugLog("❌ Widget: Failed to save tide: \(error)")
        }
    }

    func loadTideForWidget() -> WidgetTideData? {
        guard let defaults = sharedDefaults else {
            debugLog("❌ Widget: Cannot load tide - sharedDefaults is nil")
            return nil
        }
        guard let data = defaults.data(forKey: tideKey) else {
            debugLog("⚠️ Widget: No tide data found")
            return nil
        }
        do {
            let tide = try JSONDecoder().decode(WidgetTideData.self, from: data)
            debugLog("✅ Widget: Loaded tide for \(tide.locationName)")
            return tide
        } catch {
            debugLog("❌ Widget: Failed to decode tide: \(error)")
            return nil
        }
    }

    // MARK: - Widget Configuration

    func saveConfiguration(_ config: AnemWidgetConfig) {
        guard let defaults = sharedDefaults else { return }
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: configKey)
        } catch {
            debugLog("Failed to save widget config: \(error)")
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
            debugLog("Failed to load widget config: \(error)")
            return AnemWidgetConfig()
        }
    }

    // MARK: - Helper Methods

    func getStationsForSmallWidget() -> [WidgetStationData] {
        let config = loadConfiguration()
        let favorites = loadFavoritesForWidget()

        // If specific station selected, use it
        if let stationId = config.smallWidgetStationId,
           let station = favorites.first(where: { $0.id == stationId }) {
            return [station]
        }

        // Otherwise use first favorite
        return Array(favorites.prefix(1))
    }

    func getStationsForMediumWidget() -> [WidgetStationData] {
        let config = loadConfiguration()
        let favorites = loadFavoritesForWidget()

        // If specific stations selected, use them in order
        if !config.mediumWidgetStationIds.isEmpty {
            let selected = config.mediumWidgetStationIds.compactMap { id in
                favorites.first(where: { $0.id == id })
            }
            if !selected.isEmpty {
                return Array(selected.prefix(3))
            }
        }

        // Otherwise use first 3 favorites
        return Array(favorites.prefix(3))
    }

    func getStationsForLargeWidget() -> [WidgetStationData] {
        let config = loadConfiguration()
        let favorites = loadFavoritesForWidget()

        // If specific stations selected, use them in order
        if !config.largeWidgetStationIds.isEmpty {
            let selected = config.largeWidgetStationIds.compactMap { id in
                favorites.first(where: { $0.id == id })
            }
            if !selected.isEmpty {
                return Array(selected.prefix(6))
            }
        }

        // Otherwise use first 6 favorites
        return Array(favorites.prefix(6))
    }
}

// MARK: - Widget Data Fetcher

actor WidgetDataFetcher {
    static let shared = WidgetDataFetcher()

    private let vercelAPI = "https://api.levent.live/api"
    private let apiKey = "lv_R3POazDkm6rvLC5NKFNeTOwEu2oDnoN5"
    private let wcAPI = "https://backend.windmorbihan.com/observations/chart.json"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // Widgets get ~30s of execution time — use generous timeouts
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.waitsForConnectivity = true  // Wait briefly for network
        session = URLSession(configuration: config)
    }

    // MARK: - Full Refresh (stations + forecast + tide)

    /// Fetch all data the widget needs: stations, forecast, and tides.
    /// Has a hard timeout to avoid widget being killed by iOS.
    func refreshAllData() async {
        // Give all tasks max 25 seconds total (widgets get ~30s budget)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshStations() }
            group.addTask { await self.refreshForecast() }
            group.addTask { await self.refreshTide() }

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
            }

            // Wait for either all tasks to complete or timeout
            var completed = 0
            for await _ in group {
                completed += 1
                if completed >= 3 { // 3 data tasks done
                    group.cancelAll()
                    break
                }
            }
        }
        debugLog("Widget: refreshAllData completed")
    }

    /// Legacy method kept for compatibility with existing callers.
    @discardableResult
    func refreshData() async -> [WidgetStationData] {
        return await refreshStations()
    }

    // MARK: - Stations

    @discardableResult
    private func refreshStations() async -> [WidgetStationData] {
        let favorites = AppGroupManager.shared.loadFavoritesForWidget()

        guard !favorites.isEmpty else {
            debugLog("Widget: No favorites found")
            return []
        }

        debugLog("Widget: Refreshing \(favorites.count) favorites")

        // Build a dictionary of existing data for quick lookup
        let existingById = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        var updatedStations: [WidgetStationData] = []
        var hasNewData = false

        for favorite in favorites {
            let isWC = favorite.source.lowercased() == "windcornouaille"

            if isWC {
                // WindCornouaille sensor - fetch directly
                if let updated = await fetchWCSensor(id: favorite.id, name: favorite.name) {
                    updatedStations.append(updated)
                    hasNewData = true
                } else {
                    // Keep existing data exactly as-is to avoid flickering
                    // Only mark as offline if data is stale, but preserve all values
                    let existing = existingById[favorite.id] ?? favorite
                    if existing.lastUpdate != nil {
                        let staleStation = markStaleIfNeeded(existing)
                        updatedStations.append(staleStation)
                        debugLog("Widget: WC sensor \(favorite.id) failed, keeping cached (age: \(dataAge(existing)))")
                    } else {
                        updatedStations.append(existing)
                        debugLog("Widget: WC sensor \(favorite.id) failed, no cached data")
                    }
                }
            } else {
                // Other source - fetch from Vercel
                if let updated = await fetchVercelStation(favorite: favorite) {
                    updatedStations.append(updated)
                    hasNewData = true
                } else {
                    // Keep existing data exactly as-is to avoid flickering
                    let existing = existingById[favorite.id] ?? favorite
                    if existing.lastUpdate != nil {
                        let staleStation = markStaleIfNeeded(existing)
                        updatedStations.append(staleStation)
                        debugLog("Widget: Station \(favorite.id) (\(favorite.source)) failed, keeping cached (age: \(dataAge(existing)))")
                    } else {
                        updatedStations.append(existing)
                        debugLog("Widget: Station \(favorite.id) failed, no cached data")
                    }
                }
            }
        }

        // Only save if we have stations (never clear the cache)
        if !updatedStations.isEmpty {
            AppGroupManager.shared.saveFavoritesForWidget(updatedStations)

            // Also update the "last known good" cache if we got new data
            if hasNewData {
                AppGroupManager.shared.saveLastKnownGood(updatedStations)
            }

            debugLog("Widget: Saved \(updatedStations.count) stations (newData: \(hasNewData))")
        }

        return updatedStations
    }

    /// Mark station as offline if data is too old (more than 1 hour)
    private func markStaleIfNeeded(_ station: WidgetStationData) -> WidgetStationData {
        guard let lastUpdate = station.lastUpdate else {
            debugLog("Widget: \(station.name) has no lastUpdate, marking offline")
            return WidgetStationData(
                id: station.id, name: station.name, source: station.source,
                wind: station.wind, gust: station.gust, direction: station.direction,
                isOnline: false, lastUpdate: station.lastUpdate
            )
        }

        let ageSeconds = Date().timeIntervalSince(lastUpdate)
        let isStale = ageSeconds > 3600 // More than 1 hour old
        let isVeryStale = ageSeconds > 21600 // More than 6 hours old

        if isVeryStale {
            debugLog("Widget: ⚠️ \(station.name) data is VERY STALE (\(Int(ageSeconds / 3600))h old)")
        }

        if isStale && station.isOnline {
            return WidgetStationData(
                id: station.id, name: station.name, source: station.source,
                wind: station.wind, gust: station.gust, direction: station.direction,
                isOnline: false, lastUpdate: station.lastUpdate
            )
        }

        return station
    }

    /// Get human-readable age of station data
    private func dataAge(_ station: WidgetStationData) -> String {
        guard let lastUpdate = station.lastUpdate else { return "unknown" }
        let ageSeconds = Date().timeIntervalSince(lastUpdate)
        if ageSeconds < 60 { return "\(Int(ageSeconds))s" }
        if ageSeconds < 3600 { return "\(Int(ageSeconds / 60))m" }
        return "\(Int(ageSeconds / 3600))h"
    }

    /// Fetch a single station from Vercel APIs
    /// First tries the specific endpoint for the station's source, then falls back to all endpoints
    private func fetchVercelStation(favorite: WidgetStationData) async -> WidgetStationData? {
        // For Météo France, use /stations endpoint (same as the app) for better reliability
        // Other sources use their dedicated endpoints
        let sourceToEndpoint: [String: String] = [
            "pioupiou": "\(vercelAPI)/pioupiou",
            "gowind": "\(vercelAPI)/gowind",
            "meteofrance": "\(vercelAPI)/stations",  // Use /stations like the app does
            "diabox": "\(vercelAPI)/diabox"
        ]

        // First: try the specific endpoint for this station's source
        if let endpoint = sourceToEndpoint[favorite.source.lowercased()] {
            debugLog("Widget: Fetching \(favorite.name) (id=\(favorite.id)) from \(favorite.source) endpoint")
            let stations = await fetchVercelStations(endpoint: endpoint)

            debugLog("Widget: \(favorite.source) returned \(stations.count) stations")
            if stations.count > 0 && stations.count < 10 {
                // Log all station IDs for debugging
                debugLog("Widget: Available IDs: \(stations.map { $0.id }.joined(separator: ", "))")
            }

            if let found = stations.first(where: { $0.id == favorite.id }) {
                if let lastUpdate = found.lastUpdate {
                    let ageSeconds = Date().timeIntervalSince(lastUpdate)
                    debugLog("Widget: Found \(favorite.name) - data age: \(Int(ageSeconds / 60))min")
                }
                return found
            }

            // Check for partial ID match (debugging)
            let partialMatches = stations.filter { $0.id.contains(favorite.id.components(separatedBy: "_").last ?? "") }
            if !partialMatches.isEmpty {
                debugLog("Widget: Partial ID matches: \(partialMatches.map { "\($0.id)=\($0.name)" })")
            }

            debugLog("Widget: \(favorite.name) (id=\(favorite.id)) not found in \(favorite.source) endpoint")
        } else {
            debugLog("Widget: Unknown source '\(favorite.source)' for \(favorite.name)")
        }

        // Fallback: try all endpoints
        debugLog("Widget: Trying all endpoints for \(favorite.name)")
        let allStations = await fetchAllVercelStations()
        debugLog("Widget: All endpoints returned \(allStations.count) total stations")

        if let found = allStations.first(where: { $0.id == favorite.id }) {
            debugLog("Widget: Found \(favorite.name) in fallback search")
            return found
        }

        debugLog("Widget: ❌ \(favorite.name) (\(favorite.id)) NOT FOUND in any endpoint")
        return nil
    }

    // MARK: - Forecast

    private func refreshForecast() async {
        let favorites = AppGroupManager.shared.loadFavoritesForWidget()
        guard let first = favorites.first else { return }

        let coords = resolveCoordinates(for: first)
        guard let (lat, lon) = coords else { return }

        let urlString = "https://api.open-meteo.com/v1/meteofrance?" +
            "latitude=\(lat)&longitude=\(lon)" +
            "&hourly=wind_speed_10m,wind_gusts_10m,wind_direction_10m,weather_code" +
            "&wind_speed_unit=kn&timezone=Europe/Paris&forecast_days=1"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoWidgetResponse.self, from: data)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            dateFormatter.timeZone = TimeZone(identifier: "Europe/Paris")

            var hours: [WidgetForecastHour] = []
            let count = min(
                response.hourly.time.count,
                response.hourly.wind_speed_10m.count,
                response.hourly.wind_gusts_10m.count,
                response.hourly.wind_direction_10m.count
            )

            for i in 0..<count {
                let timeStr = response.hourly.time[i]
                guard let time = isoFormatter.date(from: timeStr) ?? dateFormatter.date(from: timeStr) else { continue }

                hours.append(WidgetForecastHour(
                    time: time,
                    windSpeed: response.hourly.wind_speed_10m[i] ?? 0,
                    gustSpeed: response.hourly.wind_gusts_10m[i] ?? 0,
                    windDirection: response.hourly.wind_direction_10m[i] ?? 0,
                    weatherCode: response.hourly.weather_code?[safe: i] ?? 0
                ))
            }

            let forecast = WidgetForecastData(
                stationId: first.id,
                stationName: first.name,
                hourly: hours,
                lastUpdate: Date()
            )
            AppGroupManager.shared.saveForecastForWidget(forecast)
            debugLog("Widget: Forecast fetched — \(hours.count) hours for \(first.name)")
        } catch {
            debugLog("Widget: Forecast fetch error: \(error)")
        }
    }

    // MARK: - Tides

    private func refreshTide() async {
        guard let url = URL(string: "\(vercelAPI)/tide?port=BREST&duration=2") else { return }

        do {
            var req = URLRequest(url: url)
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await session.data(for: req)
            let response = try JSONDecoder().decode(WidgetTideResponse.self, from: data)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            let events: [WidgetTideEvent] = response.tides.compactMap { event in
                guard let time = isoFormatter.date(from: event.datetime)
                        ?? fallbackFormatter.date(from: event.datetime) else { return nil }
                return WidgetTideEvent(
                    time: time,
                    height: event.height,
                    type: event.type == "high" ? .high : .low
                )
            }

            let tide = WidgetTideData(
                locationName: response.port.name,
                events: events,
                coefficient: response.todayCoefficient,
                lastUpdate: Date()
            )
            AppGroupManager.shared.saveTideForWidget(tide)
            debugLog("Widget: Tide fetched — \(events.count) events for \(response.port.name)")
        } catch {
            debugLog("Widget: Tide fetch error: \(error)")
        }
    }

    // MARK: - WC Sensor Fetch

    /// Fetch WC sensor with retry logic for better reliability.
    /// Tries up to 2 times with different time frames.
    private func fetchWCSensor(id: String, name: String) async -> WidgetStationData? {
        // Try with different time frames if first attempt fails
        let timeFrames = [60, 120, 360]  // 1h, 2h, 6h

        for timeFrame in timeFrames {
            guard let url = URL(string: "\(wcAPI)?sensor=\(id)&time_frame=\(timeFrame)") else {
                continue
            }

            do {
                let (data, response) = try await session.data(from: url)

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    debugLog("Widget: WC sensor \(id) HTTP \(httpResponse.statusCode)")
                    continue
                }

                let observations = try JSONDecoder().decode([WCWidgetObservation].self, from: data)

                // Skip if empty and try next time frame
                if observations.isEmpty {
                    debugLog("Widget: WC sensor \(id) empty with time_frame=\(timeFrame), trying wider")
                    continue
                }

                // Find most recent observation (by timestamp, not array position)
                guard let latest = observations.max(by: { $0.ts < $1.ts }) else {
                    continue
                }

                let timestamp = latest.ts
                // Consider online if data is less than 2 hours old (very lenient)
                let isOnline = Date().timeIntervalSince1970 - timestamp <= 7200

                let station = WidgetStationData(
                    id: id,
                    name: name,
                    source: "windcornouaille",
                    wind: latest.ws.moy.value ?? 0,
                    gust: latest.ws.max.value ?? 0,
                    direction: latest.wd.moy.value ?? 0,
                    isOnline: isOnline,
                    lastUpdate: Date(timeIntervalSince1970: timestamp)
                )

                debugLog("Widget: WC sensor \(id) (\(name)) OK - wind=\(station.wind), tf=\(timeFrame)")
                return station

            } catch {
                debugLog("Widget: WC sensor \(id) error (tf=\(timeFrame)): \(error.localizedDescription)")
                continue
            }
        }

        debugLog("Widget: WC sensor \(id) (\(name)) ALL ATTEMPTS FAILED")
        return nil
    }

    // MARK: - Vercel Multi-Source Fetch

    private func fetchAllVercelStations() async -> [WidgetStationData] {
        let endpoints = [
            "\(vercelAPI)/pioupiou",
            "\(vercelAPI)/gowind",
            "\(vercelAPI)/stations",  // Use /stations for Météo France (same as the app)
            "\(vercelAPI)/diabox"
        ]

        return await withTaskGroup(of: [WidgetStationData].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await self.fetchVercelStations(endpoint: endpoint)
                }
            }

            var all: [WidgetStationData] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    private func fetchVercelStations(endpoint: String, retryCount: Int = 2) async -> [WidgetStationData] {
        guard let url = URL(string: endpoint) else { return [] }

        for attempt in 0..<retryCount {
            do {
                var req = URLRequest(url: url)
                req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
                let (data, response) = try await session.data(for: req)

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        debugLog("Widget: \(endpoint) HTTP \(httpResponse.statusCode), attempt \(attempt + 1)/\(retryCount)")
                        if attempt < retryCount - 1 {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                            continue
                        }
                        return []
                    }
                }

                let decoded = try JSONDecoder().decode(VercelStationsResponse.self, from: data)

                if decoded.stale {
                    debugLog("Widget: ⚠️ \(endpoint) returned STALE cached data (upstream error)")
                }

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fallbackFormatter = ISO8601DateFormatter()
                fallbackFormatter.formatOptions = [.withInternetDateTime]

                let stations = decoded.stations.compactMap { station -> WidgetStationData? in
                    var lastUpdate: Date?
                    if let ts = station.ts {
                        lastUpdate = isoFormatter.date(from: ts) ?? fallbackFormatter.date(from: ts)

                        // Validate timestamp - reject if in the future or too old (>7 days)
                        if let date = lastUpdate {
                            let ageSeconds = Date().timeIntervalSince(date)
                            if ageSeconds < -300 { // More than 5 min in the future
                                debugLog("Widget: Rejecting \(station.name) - timestamp in future: \(ts)")
                                lastUpdate = nil
                            } else if ageSeconds > 604800 { // More than 7 days old
                                debugLog("Widget: ⚠️ \(station.name) has very old timestamp: \(Int(ageSeconds / 86400)) days old")
                            }
                        }
                    }

                    return WidgetStationData(
                        id: station.computedStableId,  // Use computed for compatibility with /api/stations
                        name: station.name,
                        source: station.computedSource,
                        wind: station.wind,
                        gust: station.gust,
                        direction: station.computedDirection,
                        isOnline: station.computedIsOnline(lastUpdate: lastUpdate),
                        lastUpdate: lastUpdate
                    )
                }

                debugLog("Widget: \(endpoint) fetched \(stations.count) stations")
                return stations

            } catch {
                debugLog("Widget: \(endpoint) error (attempt \(attempt + 1)/\(retryCount)): \(error.localizedDescription)")
                if attempt < retryCount - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s before retry
                }
            }
        }

        debugLog("Widget: \(endpoint) FAILED after \(retryCount) attempts")
        return []
    }

    // MARK: - Coordinate Resolution

    private static let wcCoordinates: [String: (lat: Double, lon: Double)] = [
        "6": (47.71791, -4.0088), "7": (47.79325, -3.85535),
        "8": (47.258259, -2.35234), "2": (47.1337, -2.24585),
        "10": (47.5478, -2.9183), "5": (47.457333, -3.0458),
        "73091286": (47.699518, -3.46097), "73091264": (47.321217, -2.834867),
        "73091265": (47.550833, -3.134722), "73091277": (47.646112, -3.214433),
        "73091300": (47.647736, -3.509733), "73091304": (47.2978046, -2.63425627),
        "73091305": (47.222515, -2.315754), "73091306": (47.268821, -2.200842),
        "10438252": (47.5095, -3.1194), "4": (47.411505, -2.620043),
        "9": (47.595, -2.81044), "1": (47.567, -3.004), "3": (47.02458, -2.3067)
    ]

    private func resolveCoordinates(for station: WidgetStationData) -> (Double, Double)? {
        if station.source.lowercased() == "windcornouaille" {
            return Self.wcCoordinates[station.id].map { ($0.lat, $0.lon) }
        }
        // Default: Bretagne center
        return (47.65, -3.0)
    }
}

// MARK: - WindCornouaille API Models for Widget

private struct WCWidgetObservation: Codable {
    let ts: Double
    let ws: WCWidgetWindSpeed
    let wd: WCWidgetWindDir
}

private struct WCWidgetWindSpeed: Codable {
    let moy: WCWidgetScalar
    let max: WCWidgetScalar
}

private struct WCWidgetWindDir: Codable {
    let moy: WCWidgetScalar
}

private struct WCWidgetScalar: Codable {
    let value: Double?
}

// MARK: - Vercel API Models for Widget

private struct VercelStationsResponse: Codable {
    let stations: [VercelStation]
    let cached: Bool
    let stale: Bool  // True if API is serving old cached data due to upstream error

    enum CodingKeys: String, CodingKey {
        case stations, cached, stale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stations = try container.decode([VercelStation].self, forKey: .stations)
        cached = (try? container.decode(Bool.self, forKey: .cached)) ?? false
        stale = (try? container.decode(Bool.self, forKey: .stale)) ?? false
    }
}

private struct VercelStation: Codable {
    let id: String
    let stableId: String?  // Optional - /api/stations doesn't return this
    let name: String
    let lat: Double
    let lon: Double
    let wind: Double
    let gust: Double
    let direction: Double?  // Optional - might be 0 or missing
    let isOnline: Bool?  // Optional - /api/stations doesn't return this
    let source: String?  // Optional - /api/stations doesn't return this
    let ts: String?
    let dir: Double?  // /api/stations uses 'dir' instead of 'direction'

    // Computed stable ID - use stableId if present, otherwise generate from source + id
    var computedStableId: String {
        if let stableId = stableId {
            return stableId
        }
        // For /api/stations endpoint (Météo France), generate stableId
        return "meteofrance_\(id)"
    }

    // Computed direction - /api/stations uses 'dir', /api/meteofrance uses 'direction'
    var computedDirection: Double {
        if let direction = direction, direction != 0 {
            return direction
        }
        return dir ?? 0
    }

    // Computed source - default to meteofrance for /api/stations
    var computedSource: String {
        source ?? "meteofrance"
    }

    // Computed online status - use isOnline if present, otherwise compute from timestamp
    func computedIsOnline(lastUpdate: Date?) -> Bool {
        if let isOnline = isOnline {
            return isOnline
        }
        // If no isOnline field, consider online if data is < 20 min old
        guard let lastUpdate = lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 20 * 60
    }
}

// MARK: - Open-Meteo Response for Widget

private struct OpenMeteoWidgetResponse: Codable {
    let hourly: OpenMeteoWidgetHourly
}

private struct OpenMeteoWidgetHourly: Codable {
    let time: [String]
    let wind_speed_10m: [Double?]
    let wind_gusts_10m: [Double?]
    let wind_direction_10m: [Double?]
    let weather_code: [Int]?
}

// MARK: - Tide Response for Widget

private struct WidgetTideResponse: Codable {
    let port: WidgetTidePort
    let tides: [WidgetTideRawEvent]
    let todayCoefficient: Int?
}

private struct WidgetTidePort: Codable {
    let name: String
    let cst: String
}

private struct WidgetTideRawEvent: Codable {
    let type: String
    let datetime: String
    let height: Double
    let coefficient: Int?
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
