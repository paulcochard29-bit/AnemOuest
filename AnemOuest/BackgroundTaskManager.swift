import Foundation
import BackgroundTasks
import UserNotifications
import WidgetKit
import CoreLocation
import UIKit

/// Manages background app refresh for wind alerts, widget updates, and data sync.
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    // Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let windCheckTaskId = AppConstants.backgroundTaskIdentifier
    static let dataProcessingTaskId = AppConstants.backgroundProcessingIdentifier

    // Track background task ID for immediate check
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Source Defaults

    /// Default source values matching @AppStorage defaults in ContentView.
    /// UserDefaults.bool(forKey:) returns false when key is unset,
    /// so we register these defaults to avoid all sources being disabled.
    static let sourceDefaults: [String: Any] = [
        "source_windcornouaille": true,
        "source_ffvl": false,
        "source_pioupiou": true,
        "source_holfuy": true,
        "source_windguru": true,
        "source_windsup": false,
        "source_meteofrance": true,
        "source_diabox": true,
        "source_netatmo": false,
        "source_ndbc": true,
        "refreshIntervalSeconds": 30.0
    ]

    /// Register UserDefaults so background reads match @AppStorage defaults.
    func registerDefaults() {
        UserDefaults.standard.register(defaults: Self.sourceDefaults)
    }

    // MARK: - Registration (call from App init)

    func registerBackgroundTasks() {
        // Ensure defaults are registered before any background task reads them
        registerDefaults()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.windCheckTaskId,
            using: nil
        ) { task in
            self.handleWindCheck(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dataProcessingTaskId,
            using: nil
        ) { task in
            self.handleDataProcessing(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Scheduling

    /// Schedule a lightweight app refresh (wind check + alerts + widget).
    func scheduleWindCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.windCheckTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.backgroundFetchMinInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("Background wind check scheduled")
        } catch {
            Log.error("Failed to schedule background wind check: \(error)")
        }
    }

    /// Schedule a heavier processing task (cache cleanup, forecast accuracy, multi-model fetch).
    /// Runs when device is charging and on WiFi.
    func scheduleDataProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.dataProcessingTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("Background data processing scheduled")
        } catch {
            Log.error("Failed to schedule background data processing: \(error)")
        }
    }

    func cancelScheduledTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }

    // MARK: - Immediate Background Check

    /// Perform an immediate wind check when the app enters background.
    /// Uses beginBackgroundTask to get ~30 seconds of execution time.
    func performImmediateBackgroundCheck() {
        let app = UIApplication.shared

        // End any previous background task
        if backgroundTaskId != .invalid {
            app.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }

        backgroundTaskId = app.beginBackgroundTask(withName: "ImmediateWindCheck") { [weak self] in
            guard let self else { return }
            if self.backgroundTaskId != .invalid {
                app.endBackgroundTask(self.backgroundTaskId)
                self.backgroundTaskId = .invalid
            }
        }

        guard backgroundTaskId != .invalid else {
            Log.error("Failed to begin immediate background task")
            return
        }

        Log.debug("Starting immediate background wind check")

        Task {
            await performWindCheck()
            await MainActor.run {
                if self.backgroundTaskId != .invalid {
                    app.endBackgroundTask(self.backgroundTaskId)
                    self.backgroundTaskId = .invalid
                }
                Log.debug("Immediate background wind check finished")
            }
        }
    }

    // MARK: - Wind Check Handler (BGAppRefreshTask)

    private func handleWindCheck(task: BGAppRefreshTask) {
        // Schedule next check immediately
        scheduleWindCheck()

        let fetchTask = Task {
            await performWindCheck()
        }

        task.expirationHandler = {
            fetchTask.cancel()
        }

        Task {
            _ = await fetchTask.result
            task.setTaskCompleted(success: !fetchTask.isCancelled)
        }
    }

    // MARK: - Data Processing Handler (BGProcessingTask)

    private func handleDataProcessing(task: BGProcessingTask) {
        // Schedule next processing
        scheduleDataProcessing()

        let processingTask = Task {
            await performDataProcessing()
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        Task {
            _ = await processingTask.result
            task.setTaskCompleted(success: !processingTask.isCancelled)
        }
    }

    // MARK: - Wind Check (lightweight, ~30s budget)

    /// Public method for silent push notifications to trigger refresh
    @MainActor
    func performWindCheck() async {
        let enabledSources = readEnabledSources()

        // Phase 1: Refresh wind stations (includes WindCornouaille)
        let stationManager = WindStationManager.shared
        await stationManager.refresh(sources: enabledSources)

        // Phase 2: Fetch wave buoys
        let waveBuoyService = WaveBuoyService.shared
        await waveBuoyService.fetchBuoys()

        let allStations = stationManager.stations

        // Phase 4: Check alerts
        let notificationManager = NotificationManager.shared
        let favoritesManager = FavoritesManager.shared

        await notificationManager.refreshAuthorizationStatus()

        notificationManager.checkAndNotify(
            stations: allStations,
            favorites: favoritesManager.favorites
        )

        // Phase 5: Check spot conditions (forecasts + tides for favorites)
        await checkSpotConditions(
            favoritesManager: favoritesManager,
            notificationManager: notificationManager
        )

        // Phase 6: Update widgets
        updateWidgetData(
            stations: allStations,
            favorites: favoritesManager.favorites,
            buoys: waveBuoyService.buoys
        )

        Log.debug("Background wind check completed: \(allStations.count) stations, \(waveBuoyService.buoys.count) buoys")
    }

    // MARK: - Data Processing (heavy, minutes budget)

    @MainActor
    private func performDataProcessing() async {
        let favoritesManager = FavoritesManager.shared
        let spotsWithAlerts = favoritesManager.spotsWithActiveAlerts

        // 1. Multi-model fetch for disagreement alerts
        let notificationManager = NotificationManager.shared
        await notificationManager.refreshAuthorizationStatus()

        var multiModelForecasts: [String: [WeatherModel: ForecastData]] = [:]

        for spot in spotsWithAlerts {
            guard let settings = spot.alertSettings,
                  settings.isEnabled,
                  settings.alertOnModelDisagreement else { continue }

            var modelData: [WeatherModel: ForecastData] = [:]
            let models: [WeatherModel] = [.arome, .ecmwf, .gfs, .icon]

            for model in models {
                guard !Task.isCancelled else { return }
                do {
                    let forecast = try await ForecastService.shared.fetchForecast(
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                        model: model
                    )
                    modelData[model] = forecast
                } catch {
                    Log.network("Background processing: Failed \(model.displayName) for \(spot.name)")
                }
            }

            if modelData.count >= 2 {
                multiModelForecasts[spot.id] = modelData
            }
        }

        // Check model disagreement
        if !multiModelForecasts.isEmpty {
            notificationManager.checkModelDisagreement(
                spots: spotsWithAlerts,
                multiModelForecasts: multiModelForecasts
            )
        }

        // 2. Cache cleanup
        CacheManager.shared.cleanupExpiredCache()

        Log.debug("Background data processing completed: \(multiModelForecasts.count) spots with multi-model data")
    }

    // MARK: - Helpers

    /// Read enabled sources from UserDefaults (with registered defaults).
    private func readEnabledSources() -> Set<WindSource> {
        let defaults = UserDefaults.standard
        var sources = Set<WindSource>()

        if defaults.bool(forKey: "source_windcornouaille") { sources.insert(.windCornouaille) }
        if defaults.bool(forKey: "source_ffvl")        { sources.insert(.ffvl) }
        if defaults.bool(forKey: "source_pioupiou")     { sources.insert(.pioupiou) }
        if defaults.bool(forKey: "source_holfuy")       { sources.insert(.holfuy) }
        if defaults.bool(forKey: "source_windguru")     { sources.insert(.windguru) }
        if defaults.bool(forKey: "source_windsup")      { sources.insert(.windsUp) }
        if defaults.bool(forKey: "source_meteofrance")  { sources.insert(.meteoFrance) }
        if defaults.bool(forKey: "source_diabox")       { sources.insert(.diabox) }
        if defaults.bool(forKey: "source_netatmo")     { sources.insert(.netatmo) }
        if defaults.bool(forKey: "source_ndbc")       { sources.insert(.ndbc) }

        return sources
    }


    // MARK: - Spot Conditions Check

    @MainActor
    private func checkSpotConditions(
        favoritesManager: FavoritesManager,
        notificationManager: NotificationManager
    ) async {
        let spotsWithAlerts = favoritesManager.spotsWithActiveAlerts
        guard !spotsWithAlerts.isEmpty else { return }

        var forecasts: [String: ForecastData] = [:]
        var surfForecasts: [String: SurfWaveForecast] = [:]

        for spot in spotsWithAlerts {
            do {
                let forecast = try await ForecastService.shared.fetchForecast(
                    latitude: spot.latitude,
                    longitude: spot.longitude
                )
                forecasts[spot.id] = forecast
            } catch {
                Log.network("Background: Forecast for \(spot.name) failed: \(error)")
            }

            if spot.type == .surf {
                do {
                    let surfForecast = try await SurfForecastService.shared.fetchForecastDirect(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )
                    if let current = surfForecast.first {
                        surfForecasts[spot.id] = current
                    }
                } catch {
                    Log.network("Background: Surf forecast for \(spot.name) failed: \(error)")
                }
            }
        }

        // Fetch tide data using first spot location
        var tideData: TideData?
        if let firstSpot = spotsWithAlerts.first {
            let coordinate = CLLocationCoordinate2D(
                latitude: firstSpot.latitude,
                longitude: firstSpot.longitude
            )
            tideData = await TideService.shared.fetchTideForLocation(coordinate)
        }

        let allStations = WindStationManager.shared.stations

        notificationManager.checkSpotConditions(
            spots: spotsWithAlerts,
            forecasts: forecasts,
            surfForecasts: surfForecasts,
            tideData: tideData,
            nearbyStations: allStations
        )

        Log.debug("Background: Checked conditions for \(spotsWithAlerts.count) spots")
    }

    // MARK: - Widget Update

    private func updateWidgetData(
        stations: [WindStation],
        favorites: [FavoriteStation],
        buoys: [WaveBuoy]
    ) {
        let favoriteIds = Set(favorites.map { $0.id })

        // Wind station data for widget
        let widgetStations: [WidgetStationData] = stations
            .filter { favoriteIds.contains($0.stableId) }
            .map { station in
                WidgetStationData(
                    id: station.stableId,
                    name: station.name,
                    source: station.source.rawValue,
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    isOnline: station.isOnline,
                    lastUpdate: station.lastUpdate
                )
            }

        // Save to App Group
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            // Stations
            if !widgetStations.isEmpty {
                do {
                    let data = try JSONEncoder().encode(widgetStations)
                    defaults.set(data, forKey: "widgetFavorites")
                } catch {
                    Log.error("Background: Failed to encode widget station data: \(error)")
                }
            }

            // Wave buoys
            if !buoys.isEmpty {
                FavoritesManager.shared.updateWaveBuoyWidgetData(buoys: buoys)
            }

            defaults.synchronize()
        }

        // Trigger widget refresh
        WidgetCenter.shared.reloadAllTimelines()
        Log.debug("Background: Widget updated — \(widgetStations.count) stations, \(buoys.count) buoys")
    }
}
