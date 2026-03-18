import Foundation
import UserNotifications
import SwiftUI
import Combine

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false
    @Published var pendingAlerts: [String: Double] = [:]  // stationId -> threshold

    // Quiet hours settings (no notifications during these hours)
    @Published var quietHoursEnabled: Bool = false {
        didSet { saveQuietHoursSettings() }
    }
    @Published var quietHoursStart: Int = 22 {  // 22:00
        didSet { saveQuietHoursSettings() }
    }
    @Published var quietHoursEnd: Int = 7 {     // 07:00
        didSet { saveQuietHoursSettings() }
    }

    private let userDefaultsKey = "windAlertThresholds"
    private let lastNotificationKey = "lastWindNotificationTime"
    private let quietHoursKey = "quietHoursSettings"
    private let spotNotificationKey = "lastSpotNotificationTime"

    // Cooldown: minimum 30 minutes between notifications for the same station
    private let notificationCooldown: TimeInterval = 30 * 60
    private var lastNotificationTimes: [String: Date] = [:]
    private var lastSpotNotificationTimes: [String: Date] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadAlerts()
        loadLastNotificationTimes()
        loadSpotNotificationTimes()
        loadQuietHoursSettings()
        checkAuthorizationStatus()

        // Reload quiet hours when changed by remote config
        NotificationCenter.default.publisher(for: .init("quietHoursSettingsChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadQuietHoursSettings()
            }
            .store(in: &cancellables)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            Log.error("Notification authorization error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Synchronously refresh authorization status (awaitable)
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Alert Management

    func setWindAlert(for stationId: String, threshold: Double) {
        pendingAlerts[stationId] = threshold
        saveAlerts()
    }

    func removeWindAlert(for stationId: String) {
        pendingAlerts.removeValue(forKey: stationId)
        saveAlerts()
        // Remove any pending notifications for this station
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stationId])
    }

    func getThreshold(for stationId: String) -> Double? {
        pendingAlerts[stationId]
    }

    func hasAlert(for stationId: String) -> Bool {
        pendingAlerts[stationId] != nil
    }

    // MARK: - Quiet Hours

    private var isInQuietHours: Bool {
        guard quietHoursEnabled else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        // Handle overnight quiet hours (e.g., 22:00 - 07:00)
        if quietHoursStart > quietHoursEnd {
            return hour >= quietHoursStart || hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
    }

    // MARK: - Check and Notify

    func checkAndNotify(stations: [WindStation], favorites: [FavoriteStation]) {
        guard isAuthorized else { return }
        guard !isInQuietHours else { return }

        for favorite in favorites {
            guard let threshold = pendingAlerts[favorite.id] else { continue }

            // Check cooldown - don't spam notifications
            if let lastTime = lastNotificationTimes[favorite.id],
               Date().timeIntervalSince(lastTime) < notificationCooldown {
                continue
            }

            // Find matching station
            // For WindCornouaille: favorite.id is just the sensor id (e.g. "6")
            // For others: favorite.id is the stableId (e.g. "ffvl_123")
            let station: WindStation?
            if favorite.source == "windcornouaille" {
                station = stations.first(where: { $0.source == .windCornouaille && $0.id == favorite.id })
            } else {
                station = stations.first(where: { $0.stableId == favorite.id })
            }

            if let station = station, station.wind >= threshold {
                sendWindAlert(station: station, threshold: threshold, favoriteId: favorite.id)
            }
        }
    }

    private func sendWindAlert(station: WindStation, threshold: Double, favoriteId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Vent fort: \(station.name)"
        content.body = "Le vent atteint \(Int(round(station.wind))) nds (seuil: \(Int(threshold)) nds)"
        content.sound = .default

        // Use station ID to avoid duplicate notifications (only one per station)
        let request = UNNotificationRequest(
            identifier: "wind_\(station.stableId)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.error("Failed to schedule notification: \(error)")
            }
        }

        // Record notification time for cooldown
        lastNotificationTimes[favoriteId] = Date()
        saveLastNotificationTimes()
        Analytics.alertTriggered(type: "wind")
    }

    // MARK: - Spot Conditions Check

    /// Check conditions for all favorite spots and send notifications
    /// - Parameters:
    ///   - nearbyStations: Optional list of nearby wind stations to validate kite spot conditions
    func checkSpotConditions(
        spots: [FavoriteSpot],
        forecasts: [String: ForecastData],
        surfForecasts: [String: SurfWaveForecast],
        tideData: TideData?,
        nearbyStations: [WindStation] = []
    ) {
        guard isAuthorized else { return }

        var bestSpot: (spot: FavoriteSpot, score: Int)?

        for spot in spots {
            guard let settings = spot.alertSettings, settings.isEnabled else { continue }

            // Check if in alert time window
            guard isInAlertWindow(settings: settings) else { continue }

            // Check cooldown
            let cooldownInterval = TimeInterval(settings.cooldownHours * 3600)
            if let lastTime = lastSpotNotificationTimes[spot.id],
               Date().timeIntervalSince(lastTime) < cooldownInterval {
                continue
            }

            // For kite spots: verify nearby stations are online
            if spot.type == .kite && !nearbyStations.isEmpty {
                let stationsNearSpot = findNearbyStations(
                    spot: spot,
                    allStations: nearbyStations,
                    maxDistance: 30 // km
                )

                // Skip if no nearby stations are online
                let onlineStations = stationsNearSpot.filter { $0.isOnline }
                if onlineStations.isEmpty && !stationsNearSpot.isEmpty {
                    Log.debug("Spot \(spot.name): Skipping - no nearby stations online")
                    continue
                }

                // Verify at least one online station confirms favorable wind
                if !onlineStations.isEmpty {
                    let hasConfirmingStation = onlineStations.contains { station in
                        station.wind >= settings.minWindSpeed &&
                        station.wind <= settings.maxWindSpeed
                    }

                    if !hasConfirmingStation {
                        Log.debug("Spot \(spot.name): Skipping - nearby stations don't confirm wind conditions")
                        continue
                    }
                }
            }

            // Check conditions based on spot type
            let (conditionsMet, score, message) = evaluateSpotConditions(
                spot: spot,
                settings: settings,
                forecast: forecasts[spot.id],
                surfForecast: surfForecasts[spot.id],
                tideData: tideData
            )

            if conditionsMet && score >= settings.minConditionScore {
                sendSpotAlert(spot: spot, score: score, message: message)

                // Track best spot for comparison
                if settings.includeInBestSpotComparison {
                    if bestSpot == nil || score > bestSpot!.score {
                        bestSpot = (spot, score)
                    }
                }
            }

            // Check weather alerts
            if let forecast = forecasts[spot.id] {
                checkWeatherAlerts(spot: spot, settings: settings, forecast: forecast)
            }
        }

        // Send "best spot" notification if multiple spots are favorable
        if let best = bestSpot {
            let favorableSpotsCount = spots.filter { spot in
                guard let settings = spot.alertSettings, settings.isEnabled else { return false }
                let (met, score, _) = evaluateSpotConditions(
                    spot: spot, settings: settings,
                    forecast: forecasts[spot.id],
                    surfForecast: surfForecasts[spot.id],
                    tideData: tideData
                )
                return met && score >= settings.minConditionScore
            }.count

            if favorableSpotsCount > 1 {
                sendBestSpotNotification(spot: best.spot, score: best.score, totalFavorable: favorableSpotsCount)
            }
        }

        // Extended alerts
        checkWindTrends(spots: spots, forecasts: forecasts)
        checkTideSchedule(spots: spots, tideData: tideData)
    }

    private func isInAlertWindow(settings: SpotAlertSettings) -> Bool {
        // Check quiet hours first
        if isInQuietHours { return false }

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        // Convert to 1=Monday format (Calendar uses 1=Sunday)
        let adjustedWeekday = weekday == 1 ? 7 : weekday - 1

        // Check day
        guard settings.alertDays.contains(adjustedWeekday) else { return false }

        // Check hour window
        if settings.alertStartHour <= settings.alertEndHour {
            return hour >= settings.alertStartHour && hour < settings.alertEndHour
        } else {
            // Overnight window
            return hour >= settings.alertStartHour || hour < settings.alertEndHour
        }
    }

    private func evaluateSpotConditions(
        spot: FavoriteSpot,
        settings: SpotAlertSettings,
        forecast: ForecastData?,
        surfForecast: SurfWaveForecast?,
        tideData: TideData?
    ) -> (conditionsMet: Bool, score: Int, message: String) {

        guard let forecast = forecast,
              let currentHour = forecast.hourly.first else {
            return (false, 0, "Pas de données")
        }

        var score = 0
        var reasons: [String] = []
        var issues: [String] = []

        // Wind speed check (0-35 points based on how well it fits the range)
        let windSpeed = currentHour.windSpeedKnots
        let windInRange = windSpeed >= settings.minWindSpeed && windSpeed <= settings.maxWindSpeed

        if windInRange {
            // Calculate how centered the wind is in the preferred range
            let rangeCenter = (settings.minWindSpeed + settings.maxWindSpeed) / 2
            let rangeSize = settings.maxWindSpeed - settings.minWindSpeed
            let distanceFromCenter = abs(windSpeed - rangeCenter)
            let centerScore = max(0, 1 - (distanceFromCenter / (rangeSize / 2)))
            score += Int(20 + centerScore * 15) // 20-35 points
            reasons.append("\(WindUnit.convertValue(windSpeed)) \(WindUnit.current.symbol)")
        } else {
            // Partial score if close to range
            let distanceFromRange: Double
            if windSpeed < settings.minWindSpeed {
                distanceFromRange = settings.minWindSpeed - windSpeed
            } else {
                distanceFromRange = windSpeed - settings.maxWindSpeed
            }
            // Give some points if within 5 knots of the range
            if distanceFromRange <= 5 {
                score += Int(10 * (1 - distanceFromRange / 5))
            }
            issues.append("Vent \(WindUnit.convertValue(windSpeed)) \(WindUnit.current.symbol)")
        }

        // Wind direction check (0-25 points)
        let windDir = directionAbbrev(currentHour.windDirection)
        var directionOk = false

        if settings.useSpotOrientation {
            let spotOrientations = spot.orientation.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            directionOk = spotOrientations.contains { orientation in
                windDir == orientation ||
                (windDir.count == 2 && (String(windDir.prefix(1)) == orientation || String(windDir.suffix(1)) == orientation))
            }
        } else if let customDirs = settings.customWindDirections, !customDirs.isEmpty {
            directionOk = customDirs.contains(windDir)
        } else {
            directionOk = true // No direction preference
        }

        if directionOk {
            score += 25
            reasons.append(windDir)
        } else {
            // Check if direction is close (adjacent cardinal)
            let adjacentScore = isAdjacentDirection(windDir: windDir, spotOrientation: spot.orientation)
            score += adjacentScore // 0-10 points for adjacent directions
            if adjacentScore > 0 {
                reasons.append("\(windDir)~")
            } else {
                issues.append("Dir \(windDir)")
            }
        }

        // Surf-specific conditions (0-30 points)
        if spot.type == .surf {
            if let surfForecast = surfForecast {
                // Wave height (0-15 points)
                if let minHeight = settings.minWaveHeight,
                   let maxHeight = settings.maxWaveHeight,
                   let waveHeight = surfForecast.primaryHeight {
                    if waveHeight >= minHeight && waveHeight <= maxHeight {
                        score += 15
                        reasons.append(String(format: "%.1fm", waveHeight))
                    } else if waveHeight >= minHeight * 0.7 && waveHeight <= maxHeight * 1.3 {
                        score += 8 // Close to range
                        reasons.append(String(format: "%.1fm~", waveHeight))
                    }
                } else {
                    score += 10 // Neutral if no preference
                }

                // Wave period (0-10 points)
                if let minPeriod = settings.minWavePeriod,
                   let period = surfForecast.primaryPeriod {
                    if period >= minPeriod {
                        score += 10
                        reasons.append("\(Int(period))s")
                    } else if period >= minPeriod * 0.8 {
                        score += 5
                    }
                } else {
                    score += 5 // Neutral
                }
            } else {
                score += 15 // Neutral if no surf data
            }

            // Tide preference (0-10 points)
            if settings.tidePreference != .all, let tide = tideData {
                if isTidePreferenceMet(preference: settings.tidePreference, tide: tide) {
                    score += 10
                    reasons.append(settings.tidePreference.rawValue)
                }
            } else {
                score += 5 // Neutral
            }
        } else {
            // Kite - tide preference (0-40 points)
            if let kiteTidePrefRaw = spot.kiteTidePreference,
               let kiteTidePref = KiteTidePreference(rawValue: kiteTidePrefRaw),
               kiteTidePref != .all {
                if kiteTidePref.isCompatible(with: tideData) {
                    score += 40
                    reasons.append(kiteTidePref.shortName)
                } else {
                    score += 10 // Partial score
                    issues.append("Marée")
                }
            } else {
                score += 30 // No tide preference = neutral bonus
            }
        }

        // Normalize score to 0-100
        score = min(100, max(0, score))

        // Build message
        var message = reasons.joined(separator: " • ")
        if !issues.isEmpty {
            message += " | " + issues.joined(separator: ", ")
        }

        // Conditions are met if score is above threshold AND critical conditions (wind) are OK
        let conditionsMet = score >= settings.minConditionScore && windInRange

        return (conditionsMet, score, message)
    }

    /// Check if wind direction is adjacent to spot orientation (gives partial credit)
    private func isAdjacentDirection(windDir: String, spotOrientation: String) -> Int {
        let allDirections = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let spotOrientations = spotOrientation.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard let windIndex = allDirections.firstIndex(of: windDir) else { return 0 }

        for orientation in spotOrientations {
            if let spotIndex = allDirections.firstIndex(of: orientation) {
                let diff = abs(windIndex - spotIndex)
                let wrappedDiff = min(diff, 8 - diff) // Handle wrap-around (N-NW)
                if wrappedDiff == 1 {
                    return 10 // Adjacent direction
                } else if wrappedDiff == 2 {
                    return 5 // Two steps away
                }
            }
        }
        return 0
    }

    private func directionAbbrev(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(round(degrees / 45.0)) % 8
        return directions[index]
    }

    /// Find stations within a given distance from a spot
    private func findNearbyStations(spot: FavoriteSpot, allStations: [WindStation], maxDistance: Double) -> [WindStation] {
        return allStations.filter { station in
            let distance = haversineDistance(
                lat1: spot.latitude, lon1: spot.longitude,
                lat2: station.latitude, lon2: station.longitude
            )
            return distance <= maxDistance
        }
    }

    /// Calculate distance between two coordinates in kilometers (Haversine formula)
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0 // Earth radius in km
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    private func isTidePreferenceMet(preference: TideAlertPreference, tide: TideData) -> Bool {
        guard let nextEvent = tide.tides.first else { return true }

        switch preference {
        case .all: return true
        case .low: return !nextEvent.isHighTide
        case .high: return nextEvent.isHighTide
        case .mid:
            // Mid-tide: within 2 hours of a tide event
            if let eventTime = nextEvent.parsedDateTime {
                let hoursUntil = eventTime.timeIntervalSince(Date()) / 3600
                return abs(hoursUntil) < 2
            }
            return false
        case .risingOnly:
            return !nextEvent.isHighTide // Next event is high = currently rising
        case .fallingOnly:
            return nextEvent.isHighTide // Next event is low = currently falling
        }
    }

    private func sendSpotAlert(spot: FavoriteSpot, score: Int, message: String) {
        Analytics.alertTriggered(type: "spot")
        let content = UNMutableNotificationContent()

        let emoji = spot.type == .kite ? "🪁" : "🏄"
        content.title = "\(emoji) \(spot.name) praticable !"
        content.body = "Score \(score)/100 • \(message)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "spot_\(spot.id)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.error("Failed to schedule spot notification: \(error)")
            }
        }

        lastSpotNotificationTimes[spot.id] = Date()
        saveSpotNotificationTimes()
    }

    private func sendBestSpotNotification(spot: FavoriteSpot, score: Int, totalFavorable: Int) {
        // Only send if we haven't sent a best-spot notification recently (6 hours)
        let bestSpotKey = "bestSpot"
        if let lastTime = lastSpotNotificationTimes[bestSpotKey],
           Date().timeIntervalSince(lastTime) < 6 * 3600 {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "🏆 Meilleur spot: \(spot.name)"
        content.body = "Score \(score)/100 • \(totalFavorable) spots praticables"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "bestSpot_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.error("Failed to schedule best spot notification: \(error)")
            }
        }

        lastSpotNotificationTimes[bestSpotKey] = Date()
        saveSpotNotificationTimes()
    }

    // MARK: - Weather Alerts

    private func checkWeatherAlerts(spot: FavoriteSpot, settings: SpotAlertSettings, forecast: ForecastData) {
        guard settings.alertOnRain || settings.alertOnStorm else { return }

        // Check next few hours
        for hour in forecast.hourly.prefix(settings.forecastHoursAhead) {
            // Storm alert (weather codes 95-99)
            if settings.alertOnStorm && (95...99).contains(hour.weatherCode) {
                sendWeatherAlert(spot: spot, type: .storm, time: hour.time)
                return
            }

            // Rain alert
            if settings.alertOnRain && hour.precipitation > 0.5 {
                sendWeatherAlert(spot: spot, type: .rain, time: hour.time)
                return
            }

            // Strong gusts alert
            if hour.gustsKnots > settings.maxGustThreshold {
                sendWeatherAlert(spot: spot, type: .strongGusts(Int(hour.gustsKnots)), time: hour.time)
                return
            }
        }
    }

    private enum WeatherAlertType {
        case storm
        case rain
        case strongGusts(Int)

        var emoji: String {
            switch self {
            case .storm: return "⛈️"
            case .rain: return "🌧️"
            case .strongGusts: return "💨"
            }
        }

        var title: String {
            switch self {
            case .storm: return "Orage prévu"
            case .rain: return "Pluie prévue"
            case .strongGusts(let knots): return "Rafales fortes (\(knots) nds)"
            }
        }
    }

    private func sendWeatherAlert(spot: FavoriteSpot, type: WeatherAlertType, time: Date) {
        // Cooldown for weather alerts (2 hours per spot per type)
        let alertKey = "weather_\(spot.id)_\(type.title)"
        if let lastTime = lastSpotNotificationTimes[alertKey],
           Date().timeIntervalSince(lastTime) < 2 * 3600 {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(type.emoji) \(type.title)"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'"
        let timeStr = formatter.string(from: time)

        content.body = "\(spot.name) vers \(timeStr)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weather_\(spot.id)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.error("Failed to schedule weather alert: \(error)")
            }
        }

        lastSpotNotificationTimes[alertKey] = Date()
        saveSpotNotificationTimes()
    }

    // MARK: - Wind Trend Alerts

    /// Detect significant wind changes in the next 3 hours and alert.
    func checkWindTrends(
        spots: [FavoriteSpot],
        forecasts: [String: ForecastData]
    ) {
        guard isAuthorized, !isInQuietHours else { return }

        for spot in spots {
            guard let settings = spot.alertSettings,
                  settings.isEnabled,
                  settings.alertOnWindTrend,
                  let forecast = forecasts[spot.id] else { continue }

            // Need at least current + 3 hours of data
            let upcoming = Array(forecast.hourly.prefix(4))
            guard upcoming.count >= 4 else { continue }

            let currentWind = upcoming[0].windSpeedKnots
            let futureWind = upcoming[3].windSpeedKnots
            let delta = futureWind - currentWind

            // Cooldown: 3 hours per spot for trend alerts
            let trendKey = "trend_\(spot.id)"
            if let lastTime = lastSpotNotificationTimes[trendKey],
               Date().timeIntervalSince(lastTime) < 3 * 3600 {
                continue
            }

            if abs(delta) >= settings.windTrendThreshold {
                let content = UNMutableNotificationContent()

                if delta > 0 {
                    content.title = "📈 Vent en hausse: \(spot.name)"
                    content.body = "De \(Int(currentWind)) à \(Int(futureWind)) nds dans les 3h"
                } else {
                    content.title = "📉 Vent en baisse: \(spot.name)"
                    content.body = "De \(Int(currentWind)) à \(Int(futureWind)) nds dans les 3h"
                }
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "trend_\(spot.id)_\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request)

                lastSpotNotificationTimes[trendKey] = Date()
                saveSpotNotificationTimes()
            }
        }
    }

    // MARK: - Model Disagreement Alerts

    /// Alert when forecast models disagree on wind for a spot.
    func checkModelDisagreement(
        spots: [FavoriteSpot],
        multiModelForecasts: [String: [WeatherModel: ForecastData]]
    ) {
        guard isAuthorized, !isInQuietHours else { return }

        for spot in spots {
            guard let settings = spot.alertSettings,
                  settings.isEnabled,
                  settings.alertOnModelDisagreement,
                  let modelForecasts = multiModelForecasts[spot.id],
                  modelForecasts.count >= 2 else { continue }

            // Cooldown: 6 hours per spot for disagreement alerts
            let disagreeKey = "disagree_\(spot.id)"
            if let lastTime = lastSpotNotificationTimes[disagreeKey],
               Date().timeIntervalSince(lastTime) < 6 * 3600 {
                continue
            }

            // Compare current hour wind speed across models
            var modelWinds: [(model: WeatherModel, wind: Double)] = []
            for (model, forecast) in modelForecasts {
                if let currentHour = forecast.hourly.first {
                    modelWinds.append((model, currentHour.windSpeedKnots))
                }
            }

            guard modelWinds.count >= 2 else { continue }

            let maxWind = modelWinds.max(by: { $0.wind < $1.wind })!
            let minWind = modelWinds.min(by: { $0.wind < $1.wind })!
            let disagreement = maxWind.wind - minWind.wind

            if disagreement >= settings.modelDisagreementThreshold {
                let content = UNMutableNotificationContent()
                content.title = "⚠️ Modèles divergents: \(spot.name)"
                content.body = "\(maxWind.model.displayName): \(WindUnit.convertValue(maxWind.wind)) \(WindUnit.current.symbol) vs \(minWind.model.displayName): \(WindUnit.convertValue(minWind.wind)) \(WindUnit.current.symbol)"
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "disagree_\(spot.id)_\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request)

                lastSpotNotificationTimes[disagreeKey] = Date()
                saveSpotNotificationTimes()
            }
        }
    }

    // MARK: - Tide Schedule Alerts

    /// Schedule alerts before upcoming tide events for favorite spots.
    func checkTideSchedule(
        spots: [FavoriteSpot],
        tideData: TideData?
    ) {
        guard isAuthorized, !isInQuietHours, let tideData = tideData else { return }

        for spot in spots {
            guard let settings = spot.alertSettings,
                  settings.isEnabled,
                  settings.alertBeforeTide else { continue }

            let tideKey = "tide_\(spot.id)"
            if let lastTime = lastSpotNotificationTimes[tideKey],
               Date().timeIntervalSince(lastTime) < 3 * 3600 {
                continue
            }

            // Check upcoming tide events
            let now = Date()
            let alertWindow = TimeInterval(settings.tideAlertMinutesBefore * 60)

            for event in tideData.tides {
                guard let eventTime = event.parsedDateTime else { continue }
                let timeUntil = eventTime.timeIntervalSince(now)

                // Alert if the event is within the alert window and in the future
                if timeUntil > 0 && timeUntil <= alertWindow {
                    let typeStr = event.isHighTide ? "Pleine mer" : "Basse mer"
                    let coeffStr = event.coefficient.map { " (coef \($0))" } ?? ""

                    let content = UNMutableNotificationContent()
                    content.title = "🌊 \(typeStr) dans \(settings.tideAlertMinutesBefore) min"
                    content.body = "\(spot.name) • \(event.timeDisplay) • \(event.heightDisplay)\(coeffStr)"
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "tide_\(spot.id)_\(event.id)",
                        content: content,
                        trigger: nil
                    )
                    UNUserNotificationCenter.current().add(request)

                    lastSpotNotificationTimes[tideKey] = Date()
                    saveSpotNotificationTimes()
                    break // Only one tide alert per check cycle
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveAlerts() {
        UserDefaults.standard.set(pendingAlerts, forKey: userDefaultsKey)
    }

    private func loadAlerts() {
        if let saved = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] {
            pendingAlerts = saved
        }
    }

    private func saveLastNotificationTimes() {
        let timestamps = lastNotificationTimes.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: lastNotificationKey)
    }

    private func loadLastNotificationTimes() {
        if let saved = UserDefaults.standard.dictionary(forKey: lastNotificationKey) as? [String: Double] {
            lastNotificationTimes = saved.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func saveSpotNotificationTimes() {
        let timestamps = lastSpotNotificationTimes.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: spotNotificationKey)
    }

    private func loadSpotNotificationTimes() {
        if let saved = UserDefaults.standard.dictionary(forKey: spotNotificationKey) as? [String: Double] {
            lastSpotNotificationTimes = saved.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func saveQuietHoursSettings() {
        let settings: [String: Any] = [
            "enabled": quietHoursEnabled,
            "start": quietHoursStart,
            "end": quietHoursEnd
        ]
        UserDefaults.standard.set(settings, forKey: quietHoursKey)
    }

    private func loadQuietHoursSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: quietHoursKey) else { return }
        if let enabled = settings["enabled"] as? Bool {
            quietHoursEnabled = enabled
        }
        if let start = settings["start"] as? Int {
            quietHoursStart = start
        }
        if let end = settings["end"] as? Int {
            quietHoursEnd = end
        }
    }

    // MARK: - Debug / Test

    /// Test spot notification for a specific spot (bypasses cooldown)
    /// Returns a debug message describing the result
    func testSpotNotification(
        spot: FavoriteSpot,
        forecast: ForecastData?,
        surfForecast: SurfWaveForecast?,
        tideData: TideData?,
        nearbyStations: [WindStation]
    ) -> String {
        var results: [String] = []
        results.append("=== Test notification: \(spot.name) ===")
        results.append("Type: \(spot.type == .kite ? "Kite" : "Surf")")

        // Check authorization
        if !isAuthorized {
            results.append("❌ Notifications non autorisées")
            return results.joined(separator: "\n")
        }
        results.append("✅ Notifications autorisées")

        // Check alert settings
        guard let settings = spot.alertSettings else {
            results.append("❌ Pas de paramètres d'alerte configurés")
            return results.joined(separator: "\n")
        }

        if !settings.isEnabled {
            results.append("❌ Alerte désactivée")
            return results.joined(separator: "\n")
        }
        results.append("✅ Alerte activée")

        // Check time window
        if !isInAlertWindow(settings: settings) {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            results.append("❌ Hors fenêtre horaire (actuel: \(hour)h, config: \(settings.alertStartHour)h-\(settings.alertEndHour)h)")
            return results.joined(separator: "\n")
        }
        results.append("✅ Dans la fenêtre horaire")

        // Check nearby stations for kite spots
        if spot.type == .kite && !nearbyStations.isEmpty {
            let stationsNearSpot = findNearbyStations(spot: spot, allStations: nearbyStations, maxDistance: 30)
            results.append("Stations proches (30km): \(stationsNearSpot.count)")

            let onlineStations = stationsNearSpot.filter { $0.isOnline }
            results.append("Stations en ligne: \(onlineStations.count)")

            for station in stationsNearSpot.prefix(5) {
                let status = station.isOnline ? "✅" : "❌"
                results.append("  \(status) \(station.name): \(WindUnit.convertValue(station.wind)) \(WindUnit.current.symbol)")
            }

            if onlineStations.isEmpty && !stationsNearSpot.isEmpty {
                results.append("❌ Aucune station proche en ligne")
                return results.joined(separator: "\n")
            }

            let hasConfirmingStation = onlineStations.contains { station in
                station.wind >= settings.minWindSpeed && station.wind <= settings.maxWindSpeed
            }

            if !hasConfirmingStation && !onlineStations.isEmpty {
                results.append("❌ Stations ne confirment pas le vent (\(WindUnit.convertValue(settings.minWindSpeed))-\(WindUnit.convertValue(settings.maxWindSpeed)) \(WindUnit.current.symbol))")
                return results.joined(separator: "\n")
            }
            results.append("✅ Stations confirment les conditions")
        }

        // Check forecast conditions
        guard let forecast = forecast, let currentHour = forecast.hourly.first else {
            results.append("❌ Pas de données prévision")
            return results.joined(separator: "\n")
        }

        results.append("Prévision actuelle:")
        results.append("  Vent: \(Int(currentHour.windSpeedKnots)) nds (config: \(Int(settings.minWindSpeed))-\(Int(settings.maxWindSpeed)))")
        results.append("  Direction: \(directionAbbrev(currentHour.windDirection)) (\(Int(currentHour.windDirection))°)")
        results.append("  Orientation spot: \(spot.orientation)")

        // Evaluate conditions
        let (conditionsMet, score, message) = evaluateSpotConditions(
            spot: spot,
            settings: settings,
            forecast: forecast,
            surfForecast: surfForecast,
            tideData: tideData
        )

        results.append("Score: \(score)/100 (minimum: \(settings.minConditionScore))")
        results.append("Message: \(message)")

        if conditionsMet && score >= settings.minConditionScore {
            results.append("✅ CONDITIONS REMPLIES - Notification envoyée!")
            // Actually send the notification for the test
            sendSpotAlert(spot: spot, score: score, message: message)
        } else {
            results.append("❌ Conditions non remplies")
        }

        return results.joined(separator: "\n")
    }

    /// Reset cooldown for a spot (for testing)
    func resetCooldown(for spotId: String) {
        lastSpotNotificationTimes.removeValue(forKey: spotId)
        saveSpotNotificationTimes()
        Log.debug("Cooldown reset for spot: \(spotId)")
    }
}

// MARK: - Alert Configuration View

struct WindAlertConfigView: View {
    let stationId: String
    let stationName: String
    @ObservedObject var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var threshold: Double = 15
    @State private var isEnabled: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Alerte vent")
                        .font(.title2.bold())

                    Text(stationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                if !notificationManager.isAuthorized {
                    VStack(spacing: 12) {
                        Text("Les notifications sont desactivees")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Button("Activer les notifications") {
                            Task {
                                await notificationManager.requestAuthorization()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
                } else {
                    VStack(spacing: 20) {
                        Toggle("Activer l'alerte", isOn: $isEnabled)
                            .tint(.blue)

                        if isEnabled {
                            VStack(spacing: 8) {
                                Text("Seuil: \(WindUnit.convertValue(threshold)) \(WindUnit.current.symbol)")
                                    .font(.headline)

                                Slider(value: $threshold, in: 5...50, step: 1)
                                    .tint(windColor(threshold))

                                HStack {
                                    Text("\(WindUnit.convertValue(5)) \(WindUnit.current.symbol)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(WindUnit.convertValue(50)) \(WindUnit.current.symbol)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))

                            Text("Vous recevrez une notification quand le vent depasse \(WindUnit.convertValue(threshold)) \(WindUnit.current.symbol)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                Spacer()

                Button(action: save) {
                    Text("Enregistrer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let existing = notificationManager.getThreshold(for: stationId) {
                    threshold = existing
                    isEnabled = true
                }
            }
        }
    }

    private func save() {
        if isEnabled {
            notificationManager.setWindAlert(for: stationId, threshold: threshold)
        } else {
            notificationManager.removeWindAlert(for: stationId)
        }
        dismiss()
    }

    private func windColor(_ knots: Double) -> Color {
        windScale(knots)
    }
}
