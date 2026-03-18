import Foundation
import SwiftUI
import Combine
import CoreLocation
import WidgetKit

// MARK: - Favorite Station Model

struct FavoriteStation: Codable, Identifiable, Equatable {
    let id: String           // stableId for WindStation, or sensor id for WC sensors
    let name: String
    let source: String       // "windcornouaille", "pioupiou", "ffvl", etc.
    let latitude: Double
    let longitude: Double
    let addedAt: Date

    // Wind alert threshold (optional)
    var windAlertThreshold: Double?

    var isWindCornouaille: Bool {
        source == "windcornouaille"
    }
}

// MARK: - Favorite Wave Buoy Model

struct FavoriteWaveBuoy: Codable, Identifiable, Equatable {
    let id: String           // Buoy ID from CANDHIS
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    let depth: Int
    let addedAt: Date

    // Wave alert threshold (optional, in meters)
    var waveAlertThreshold: Double?
}

// MARK: - Favorite Spot Model (Kite/Surf)

enum SpotFavoriteType: String, Codable, CaseIterable {
    case kite = "kite"
    case surf = "surf"

    var icon: String {
        switch self {
        case .kite: return "wind"
        case .surf: return "figure.surfing"
        }
    }

    var displayName: String {
        switch self {
        case .kite: return "Kite"
        case .surf: return "Surf"
        }
    }
}

enum TideAlertPreference: String, Codable, CaseIterable {
    case all = "all"
    case low = "low"
    case mid = "mid"
    case high = "high"
    case risingOnly = "rising"
    case fallingOnly = "falling"

    var displayName: String {
        switch self {
        case .all: return "Toutes"
        case .low: return "Basse"
        case .mid: return "Mi-maree"
        case .high: return "Haute"
        case .risingOnly: return "Montante"
        case .fallingOnly: return "Descendante"
        }
    }

    var icon: String {
        switch self {
        case .all: return "water.waves"
        case .low: return "arrow.down.to.line"
        case .mid: return "equal"
        case .high: return "arrow.up.to.line"
        case .risingOnly: return "arrow.up"
        case .fallingOnly: return "arrow.down"
        }
    }
}

struct SpotAlertSettings: Codable, Equatable {
    var isEnabled: Bool = true

    // Wind conditions
    var minWindSpeed: Double = 12       // knots minimum
    var maxWindSpeed: Double = 30       // knots maximum
    var useSpotOrientation: Bool = true // Use spot's default orientation
    var customWindDirections: [String]? // Custom directions if not using spot orientation

    // Wave conditions (surf only)
    var minWaveHeight: Double?          // meters
    var maxWaveHeight: Double?
    var minWavePeriod: Double?          // seconds

    // Minimum condition score (0-100)
    var minConditionScore: Int = 60     // Default "good conditions"

    // Alert time window
    var alertStartHour: Int = 6         // 6 AM
    var alertEndHour: Int = 21          // 9 PM
    var alertDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7] // 1=Monday...7=Sunday

    // Tide preference (surf)
    var tidePreference: TideAlertPreference = .all

    // Advanced settings
    var cooldownHours: Int = 4          // Hours between alerts
    var forecastHoursAhead: Int = 24    // Alert X hours before

    // Weather alerts
    var alertOnRain: Bool = false
    var alertOnStorm: Bool = true
    var maxGustThreshold: Double = 45   // knots

    // Best spot comparison
    var includeInBestSpotComparison: Bool = true

    // Extended alerts
    var alertOnWindTrend: Bool = false          // Alert when wind is picking up or dropping
    var windTrendThreshold: Double = 5          // Minimum change in knots over 3 hours
    var alertOnModelDisagreement: Bool = false   // Alert when models disagree significantly
    var modelDisagreementThreshold: Double = 8   // Minimum disagreement in knots
    var alertBeforeTide: Bool = false            // Alert before high/low tide
    var tideAlertMinutesBefore: Int = 60         // Minutes before tide event

    static var defaultKite: SpotAlertSettings {
        var settings = SpotAlertSettings()
        settings.minWindSpeed = 12
        settings.maxWindSpeed = 30
        return settings
    }

    static var defaultSurf: SpotAlertSettings {
        var settings = SpotAlertSettings()
        settings.minWindSpeed = 0
        settings.maxWindSpeed = 20
        settings.minWaveHeight = 0.5
        settings.maxWaveHeight = 2.5
        settings.minWavePeriod = 8
        return settings
    }
}

struct FavoriteSpot: Codable, Identifiable, Equatable {
    let id: String                      // Spot ID
    let name: String
    let type: SpotFavoriteType          // .kite or .surf
    let latitude: Double
    let longitude: Double
    let orientation: String             // Spot orientations (e.g., "W,NW")
    let addedAt: Date
    var alertSettings: SpotAlertSettings?

    // Préférence de marée du spot (pour kite)
    var kiteTidePreference: String?     // Stocké comme String pour Codable

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasActiveAlerts: Bool {
        alertSettings?.isEnabled ?? false
    }
}

// MARK: - Favorites Manager

@MainActor
final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var favorites: [FavoriteStation] = []
    @Published private(set) var favoriteWaveBuoys: [FavoriteWaveBuoy] = []
    @Published private(set) var favoriteSpots: [FavoriteSpot] = []

    private let userDefaultsKey = "savedFavorites"
    private let waveBuoysKey = "savedFavoriteWaveBuoys"
    private let spotsKey = "savedFavoriteSpots"

    private init() {
        loadFavorites()
        loadWaveBuoyFavorites()
        loadSpotFavorites()
    }

    /// Reload widget timelines (simple, no debounce)
    private func scheduleWidgetReload() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Public API

    func isFavorite(stationId: String) -> Bool {
        favorites.contains { $0.id == stationId }
    }

    func addFavorite(station: WindStation) {
        guard !isFavorite(stationId: station.stableId) else { return }

        let favorite = FavoriteStation(
            id: station.stableId,
            name: station.name,
            source: station.source.rawValue,
            latitude: station.latitude,
            longitude: station.longitude,
            addedAt: Date(),
            windAlertThreshold: nil
        )
        favorites.append(favorite)
        saveFavorites()
        Analytics.favoriteAdded(type: "station", id: station.stableId)
    }

    func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
        Analytics.favoriteRemoved(type: "station", id: id)
    }

    func toggleFavorite(station: WindStation) {
        if isFavorite(stationId: station.stableId) {
            removeFavorite(id: station.stableId)
        } else {
            addFavorite(station: station)
        }
    }

    func setWindAlert(for id: String, threshold: Double?) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites[index].windAlertThreshold = threshold
            saveFavorites()
            Analytics.alertConfigured(type: "wind", id: id)
        }
    }

    // MARK: - Wave Buoy Favorites API

    func isFavorite(buoyId: String) -> Bool {
        favoriteWaveBuoys.contains { $0.id == buoyId }
    }

    func addFavorite(buoy: WaveBuoy) {
        guard !isFavorite(buoyId: buoy.id) else { return }

        let favorite = FavoriteWaveBuoy(
            id: buoy.id,
            name: buoy.name,
            region: buoy.region,
            latitude: buoy.latitude,
            longitude: buoy.longitude,
            depth: buoy.depth,
            addedAt: Date(),
            waveAlertThreshold: nil
        )
        favoriteWaveBuoys.append(favorite)
        saveWaveBuoyFavorites()
        Analytics.favoriteAdded(type: "buoy", id: buoy.id)
    }

    func removeFavoriteBuoy(id: String) {
        favoriteWaveBuoys.removeAll { $0.id == id }
        saveWaveBuoyFavorites()
        Analytics.favoriteRemoved(type: "buoy", id: id)
    }

    func toggleFavorite(buoy: WaveBuoy) {
        if isFavorite(buoyId: buoy.id) {
            removeFavoriteBuoy(id: buoy.id)
        } else {
            addFavorite(buoy: buoy)
        }
    }

    func setWaveAlert(for buoyId: String, threshold: Double?) {
        if let index = favoriteWaveBuoys.firstIndex(where: { $0.id == buoyId }) {
            favoriteWaveBuoys[index].waveAlertThreshold = threshold
            saveWaveBuoyFavorites()
            Analytics.alertConfigured(type: "wave", id: buoyId)
        }
    }

    // MARK: - Spot Favorites

    func isSpotFavorite(spotId: String) -> Bool {
        favoriteSpots.contains { $0.id == spotId }
    }

    func addFavorite(kiteSpot: KiteSpot) {
        guard !isSpotFavorite(spotId: kiteSpot.id) else { return }

        let favorite = FavoriteSpot(
            id: kiteSpot.id,
            name: kiteSpot.name,
            type: .kite,
            latitude: kiteSpot.latitude,
            longitude: kiteSpot.longitude,
            orientation: kiteSpot.orientation,
            addedAt: Date(),
            alertSettings: .defaultKite,
            kiteTidePreference: kiteSpot.tidePreference.rawValue
        )
        favoriteSpots.append(favorite)
        saveSpotFavorites()
        Analytics.favoriteAdded(type: "kiteSpot", id: kiteSpot.id)
    }

    func addFavorite(surfSpot: SurfSpot) {
        guard !isSpotFavorite(spotId: surfSpot.id) else { return }

        let favorite = FavoriteSpot(
            id: surfSpot.id,
            name: surfSpot.name,
            type: .surf,
            latitude: surfSpot.latitude,
            longitude: surfSpot.longitude,
            orientation: surfSpot.orientation,
            addedAt: Date(),
            alertSettings: .defaultSurf,
            kiteTidePreference: nil
        )
        favoriteSpots.append(favorite)
        saveSpotFavorites()
        Analytics.favoriteAdded(type: "surfSpot", id: surfSpot.id)
    }

    func removeSpotFavorite(id: String) {
        favoriteSpots.removeAll { $0.id == id }
        saveSpotFavorites()
        Analytics.favoriteRemoved(type: "spot", id: id)
    }

    func toggleFavorite(kiteSpot: KiteSpot) {
        if isSpotFavorite(spotId: kiteSpot.id) {
            removeSpotFavorite(id: kiteSpot.id)
        } else {
            addFavorite(kiteSpot: kiteSpot)
        }
    }

    func toggleFavorite(surfSpot: SurfSpot) {
        if isSpotFavorite(spotId: surfSpot.id) {
            removeSpotFavorite(id: surfSpot.id)
        } else {
            addFavorite(surfSpot: surfSpot)
        }
    }

    func setSpotAlertSettings(for spotId: String, settings: SpotAlertSettings?) {
        if let index = favoriteSpots.firstIndex(where: { $0.id == spotId }) {
            favoriteSpots[index].alertSettings = settings
            saveSpotFavorites()
            Analytics.alertConfigured(type: "spot", id: spotId)
        }
    }

    func getSpotFavorite(id: String) -> FavoriteSpot? {
        favoriteSpots.first { $0.id == id }
    }

    /// Get all spots with active alerts
    var spotsWithActiveAlerts: [FavoriteSpot] {
        favoriteSpots.filter { $0.hasActiveAlerts }
    }

    // MARK: - Widget Update

    func updateWidgetData(stations: [WindStation]) {
        // Load existing widget data to use as fallback for missing stations
        let existingData = AppGroupManager.shared.loadFavoritesForWidget()
        let existingById = Dictionary(uniqueKeysWithValues: existingData.map { ($0.id, $0) })

        var widgetData: [WidgetStationData] = []

        for favorite in favorites {
            if let station = stations.first(where: { $0.stableId == favorite.id }) {
                widgetData.append(WidgetStationData(
                    id: station.stableId,
                    name: station.name,
                    source: station.source.rawValue,
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    isOnline: station.isOnline,
                    lastUpdate: station.lastUpdate
                ))
            } else if let existing = existingById[favorite.id], existing.lastUpdate != nil {
                // Fallback: use previous cached data to avoid flickering
                widgetData.append(existing)
                Log.widget("Widget: Using cached data for \(favorite.name)")
            } else {
                // Last resort: placeholder
                widgetData.append(WidgetStationData(
                    id: favorite.id,
                    name: favorite.name,
                    source: favorite.source,
                    wind: 0,
                    gust: 0,
                    direction: 0,
                    isOnline: false,
                    lastUpdate: nil
                ))
            }
        }

        // Save to App Group
        AppGroupManager.shared.saveFavoritesForWidget(widgetData)

        Log.widget("Widget data updated: \(widgetData.count) stations saved")

        // Reload widget
        scheduleWidgetReload()
    }

    /// Update forecast widget data (for first favorite station)
    func updateForecastWidgetData(forecast: ForecastData?, stationId: String, stationName: String) {
        guard let forecast = forecast else { return }

        let hours = forecast.hourly.prefix(12).map { hour in
            WidgetForecastHour(
                time: hour.time,
                windSpeed: hour.windSpeedKnots,
                gustSpeed: hour.gustsKnots,
                windDirection: hour.windDirection,
                weatherCode: hour.weatherCode
            )
        }

        let widgetForecast = WidgetForecastData(
            stationId: stationId,
            stationName: stationName,
            hourly: hours,
            lastUpdate: Date()
        )

        AppGroupManager.shared.saveForecastForWidget(widgetForecast)
        Log.widget("Forecast widget data updated for \(stationName)")
        scheduleWidgetReload()
    }

    /// Update tide widget data
    func updateTideWidgetData(tides: [TideEvent], locationName: String) {
        let events = tides.prefix(4).compactMap { event -> WidgetTideEvent? in
            guard let time = event.parsedDateTime else { return nil }
            return WidgetTideEvent(
                time: time,
                height: event.height,
                type: event.isHighTide ? .high : .low
            )
        }

        // Get coefficient from first high tide
        let coefficient = tides.first(where: { $0.isHighTide })?.coefficient

        let widgetTide = WidgetTideData(
            locationName: locationName,
            events: events,
            coefficient: coefficient,
            lastUpdate: Date()
        )

        AppGroupManager.shared.saveTideForWidget(widgetTide)
        Log.widget("Tide widget data updated for \(locationName)")
        scheduleWidgetReload()
    }

    /// Update wave buoy widget data
    func updateWaveBuoyWidgetData(buoys: [WaveBuoy]) {
        var widgetData: [WidgetWaveBuoyData] = []

        for favorite in favoriteWaveBuoys {
            if let buoy = buoys.first(where: { $0.id == favorite.id }) {
                widgetData.append(WidgetWaveBuoyData(
                    id: buoy.id,
                    name: buoy.name,
                    region: buoy.region,
                    hm0: buoy.hm0,
                    tp: buoy.tp,
                    direction: buoy.direction,
                    seaTemp: buoy.seaTemp,
                    isOnline: buoy.status.isOnline,
                    lastUpdate: buoy.lastUpdate
                ))
            } else {
                // Fallback: add favorite even without current data
                widgetData.append(WidgetWaveBuoyData(
                    id: favorite.id,
                    name: favorite.name,
                    region: favorite.region,
                    hm0: nil,
                    tp: nil,
                    direction: nil,
                    seaTemp: nil,
                    isOnline: false,
                    lastUpdate: nil
                ))
            }
        }

        // Save to App Group
        AppGroupManager.shared.saveWaveBuoysForWidget(widgetData)

        Log.widget("Wave buoy widget data updated: \(widgetData.count) buoys saved")

        // Reload widget
        scheduleWidgetReload()
    }

    // MARK: - Persistence

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save favorites: \(error)")
        }
    }

    // Canonical names from Constants.swift
    private static let wcSensorNames = WCSensors.names

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            var loaded = try JSONDecoder().decode([FavoriteStation].self, from: data)

            // Migrate WindCornouaille favorites: raw sensor ID → stableId format
            var needsSave = false
            for i in loaded.indices where loaded[i].isWindCornouaille {
                let old = loaded[i]
                var changed = false
                var newId = old.id
                var newName = old.name

                // Migrate ID from raw "6" to "windcornouaille_6"
                if !old.id.hasPrefix("windcornouaille_") {
                    newId = "windcornouaille_\(old.id)"
                    changed = true
                }

                // Migrate name to canonical value
                let rawId = old.id.replacingOccurrences(of: "windcornouaille_", with: "")
                if let canonical = Self.wcSensorNames[rawId], old.name != canonical {
                    newName = canonical
                    changed = true
                }

                if changed {
                    loaded[i] = FavoriteStation(
                        id: newId,
                        name: newName,
                        source: old.source,
                        latitude: old.latitude,
                        longitude: old.longitude,
                        addedAt: old.addedAt,
                        windAlertThreshold: old.windAlertThreshold
                    )
                    needsSave = true
                }
            }

            favorites = loaded
            if needsSave { saveFavorites() }
        } catch {
            Log.error("Failed to load favorites: \(error)")
        }
    }

    private func saveWaveBuoyFavorites() {
        do {
            let data = try JSONEncoder().encode(favoriteWaveBuoys)
            UserDefaults.standard.set(data, forKey: waveBuoysKey)
        } catch {
            Log.error("Failed to save wave buoy favorites: \(error)")
        }
    }

    private func loadWaveBuoyFavorites() {
        guard let data = UserDefaults.standard.data(forKey: waveBuoysKey) else { return }
        do {
            favoriteWaveBuoys = try JSONDecoder().decode([FavoriteWaveBuoy].self, from: data)
        } catch {
            Log.error("Failed to load wave buoy favorites: \(error)")
        }
    }

    private func saveSpotFavorites() {
        do {
            let data = try JSONEncoder().encode(favoriteSpots)
            UserDefaults.standard.set(data, forKey: spotsKey)
        } catch {
            Log.error("Failed to save spot favorites: \(error)")
        }
    }

    private func loadSpotFavorites() {
        guard let data = UserDefaults.standard.data(forKey: spotsKey) else { return }
        do {
            favoriteSpots = try JSONDecoder().decode([FavoriteSpot].self, from: data)
        } catch {
            Log.error("Failed to load spot favorites: \(error)")
        }
    }
}

// Note: WidgetStationData and AppGroupManager are defined in WidgetTypes.swift
