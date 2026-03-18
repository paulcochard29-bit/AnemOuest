import Foundation
import Combine

// MARK: - Models

struct StoredForecast: Codable, Identifiable {
    var id: String { "\(stationId)_\(forecastTime.timeIntervalSince1970)" }

    let stationId: String
    let stationName: String
    let latitude: Double
    let longitude: Double
    let forecastTime: Date      // Heure prévue
    let fetchedAt: Date         // Quand la prévision a été faite
    let predictedWind: Double   // knots
    let predictedGust: Double   // knots
    let predictedDirection: Double
}

struct AccuracyRecord: Codable, Identifiable {
    var id: String { "\(stationId)_\(forecastTime.timeIntervalSince1970)" }

    let stationId: String
    let forecastTime: Date
    let predictedWind: Double
    let actualWind: Double
    let predictedGust: Double
    let actualGust: Double
    let windError: Double       // |predicted - actual|
    let gustError: Double
    let directionError: Double  // Erreur angulaire
    let hoursAhead: Int         // Combien d'heures à l'avance
    let recordedAt: Date
}

struct StationAccuracyStats: Codable, Identifiable {
    var id: String { stationId }

    let stationId: String
    let stationName: String
    var totalComparisons: Int
    var meanWindError: Double   // MAE vent moyen
    var meanGustError: Double   // MAE rafales
    var percentWithin3Knots: Double  // % prévisions ±3 nds
    var percentWithin5Knots: Double  // % prévisions ±5 nds
    var lastUpdated: Date
    var latitude: Double?
    var longitude: Double?
}

// MARK: - Vercel API Response

private struct VercelAccuracyResponse: Codable {
    let stations: [String: VercelStationStats]?
    let count: Int?
    let lastUpdated: String?
}

private struct VercelStationStats: Codable {
    let stationId: String
    let stationName: String
    let totalComparisons: Int
    let meanWindError: Double
    let meanGustError: Double?
    let percentWithin3Knots: Int
    let percentWithin5Knots: Int
    let lastUpdated: String?
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Service

class ForecastAccuracyService: ObservableObject {
    static let shared = ForecastAccuracyService()

    private let vercelAPIBase = "https://api.levent.live/api"
    private let storedForecastsKey = "storedForecasts_v1"
    private let accuracyRecordsKey = "accuracyRecords_v1"
    private let stationStatsKey = "stationAccuracyStats_v1"
    private let vercelStatsCacheKey = "vercelAccuracyStats_v1"

    private let maxHistoryDays = 30
    private let minComparisonsForStats = 5
    private let timeToleranceMinutes = 30.0

    @Published private(set) var stationStats: [String: StationAccuracyStats] = [:]
    @Published private(set) var isLoading: Bool = false

    private var storedForecasts: [StoredForecast] = []
    private var accuracyRecords: [AccuracyRecord] = []

    private init() {
        loadData()
        cleanupOldData()
        // Fetch stats from Vercel API
        Task {
            await fetchStatsFromVercel()
        }
    }

    // MARK: - Vercel API

    /// Fetch pre-calculated accuracy stats from Vercel
    @MainActor
    func fetchStatsFromVercel() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let url = URL(string: "\(vercelAPIBase)/forecast-accuracy?action=stats") else { return }

            let request = AppConstants.apiRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[ForecastAccuracy] Vercel API returned non-200 status")
                return
            }

            let decoded = try JSONDecoder().decode(VercelAccuracyResponse.self, from: data)

            if let stations = decoded.stations {
                for (stationId, vercelStats) in stations {
                    // Convert to local format
                    let stats = StationAccuracyStats(
                        stationId: vercelStats.stationId,
                        stationName: vercelStats.stationName,
                        totalComparisons: vercelStats.totalComparisons,
                        meanWindError: vercelStats.meanWindError,
                        meanGustError: vercelStats.meanGustError ?? 0,
                        percentWithin3Knots: Double(vercelStats.percentWithin3Knots),
                        percentWithin5Knots: Double(vercelStats.percentWithin5Knots),
                        lastUpdated: ISO8601DateFormatter().date(from: vercelStats.lastUpdated ?? "") ?? Date(),
                        latitude: vercelStats.latitude,
                        longitude: vercelStats.longitude
                    )

                    // Only use Vercel stats if we don't have local stats or Vercel has more data
                    if let localStats = stationStats[stationId] {
                        if vercelStats.totalComparisons > localStats.totalComparisons {
                            stationStats[stationId] = stats
                        }
                    } else {
                        stationStats[stationId] = stats
                    }
                }

                // Cache the Vercel stats
                if let cacheData = try? JSONEncoder().encode(Array(stationStats.values)) {
                    UserDefaults.standard.set(cacheData, forKey: vercelStatsCacheKey)
                }

                print("[ForecastAccuracy] Loaded \(stations.count) stats from Vercel API")
            }
        } catch {
            print("[ForecastAccuracy] Vercel API error: \(error.localizedDescription)")
            // Load cached Vercel stats if available
            loadCachedVercelStats()
        }
    }

    private func loadCachedVercelStats() {
        if let data = UserDefaults.standard.data(forKey: vercelStatsCacheKey),
           let stats = try? JSONDecoder().decode([StationAccuracyStats].self, from: data) {
            for stat in stats {
                if stationStats[stat.stationId] == nil {
                    stationStats[stat.stationId] = stat
                }
            }
            print("[ForecastAccuracy] Loaded \(stats.count) cached Vercel stats")
        }
    }

    // MARK: - Public Methods

    /// Store forecasts for a station when they are loaded
    func storeForecast(stationId: String, stationName: String, latitude: Double, longitude: Double, forecasts: [HourlyForecast]) {
        let now = Date()

        // Store forecasts for the next 12 hours
        let futureForecasts = forecasts.filter { forecast in
            let hoursAhead = forecast.time.timeIntervalSince(now) / 3600
            return hoursAhead > 0 && hoursAhead <= 12
        }

        // Remove existing forecasts for this station that haven't been compared yet
        storedForecasts.removeAll { $0.stationId == stationId && $0.forecastTime > now }

        // Add new forecasts
        for forecast in futureForecasts {
            let stored = StoredForecast(
                stationId: stationId,
                stationName: stationName,
                latitude: latitude,
                longitude: longitude,
                forecastTime: forecast.time,
                fetchedAt: now,
                predictedWind: forecast.windSpeedKnots,
                predictedGust: forecast.gustsKnots,
                predictedDirection: forecast.windDirection
            )
            storedForecasts.append(stored)
        }

        saveForecasts()
        print("[ForecastAccuracy] Stored \(futureForecasts.count) forecasts for \(stationName)")
    }

    /// Compare actual wind data with stored forecasts
    func compareWithActual(stationId: String, latitude: Double, longitude: Double, actualWind: Double, actualGust: Double, actualDirection: Double) {
        let now = Date()
        let tolerance = timeToleranceMinutes * 60 // Convert to seconds

        // Find matching forecast (within time tolerance)
        guard let matchingForecast = storedForecasts.first(where: { forecast in
            guard forecast.stationId == stationId else { return false }
            let timeDiff = abs(forecast.forecastTime.timeIntervalSince(now))
            return timeDiff <= tolerance
        }) else {
            // Try to find by coordinates if stationId doesn't match
            guard let matchingForecast = storedForecasts.first(where: { forecast in
                let latDiff = abs(forecast.latitude - latitude)
                let lonDiff = abs(forecast.longitude - longitude)
                let timeDiff = abs(forecast.forecastTime.timeIntervalSince(now))
                return latDiff < 0.02 && lonDiff < 0.02 && timeDiff <= tolerance
            }) else {
                return
            }

            recordComparison(forecast: matchingForecast, actualWind: actualWind, actualGust: actualGust, actualDirection: actualDirection, now: now)
            return
        }

        recordComparison(forecast: matchingForecast, actualWind: actualWind, actualGust: actualGust, actualDirection: actualDirection, now: now)
    }

    /// Get accuracy stats for a station
    func getAccuracy(for stationId: String) -> StationAccuracyStats? {
        return stationStats[stationId]
    }

    /// Get accuracy percentage for display (within 5 knots tolerance)
    func getAccuracyPercent(for stationId: String) -> Int? {
        guard let stats = stationStats[stationId],
              stats.totalComparisons >= minComparisonsForStats else {
            return nil
        }
        return Int(stats.percentWithin5Knots)
    }

    /// Get accuracy percentage by location (finds nearest station within 50km)
    func getAccuracyPercent(latitude: Double, longitude: Double) -> Int? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return Int(stats.percentWithin5Knots)
    }

    /// Get mean wind error by location (finds nearest station within 50km)
    func getMeanError(latitude: Double, longitude: Double) -> Double? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return stats.meanWindError
    }

    /// Get accuracy info (percent + mean error) by location
    func getAccuracyInfo(latitude: Double, longitude: Double) -> (percent: Int, meanError: Double)? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return (Int(stats.percentWithin5Knots), stats.meanWindError)
    }

    private func getNearestStats(latitude: Double, longitude: Double) -> StationAccuracyStats? {
        let maxDistance = 0.5 // ~50km in degrees

        var nearestStats: StationAccuracyStats?
        var minDistance = Double.infinity

        for stats in stationStats.values {
            guard let lat = stats.latitude, let lon = stats.longitude else { continue }
            let distance = sqrt(pow(lat - latitude, 2) + pow(lon - longitude, 2))
            if distance < minDistance && distance < maxDistance {
                minDistance = distance
                nearestStats = stats
            }
        }

        guard let stats = nearestStats,
              stats.totalComparisons >= minComparisonsForStats else {
            return nil
        }

        return stats
    }

    /// Check if we have enough data to show accuracy
    func hasEnoughData(for stationId: String) -> Bool {
        guard let stats = stationStats[stationId] else { return false }
        return stats.totalComparisons >= minComparisonsForStats
    }

    // MARK: - Private Methods

    private func recordComparison(forecast: StoredForecast, actualWind: Double, actualGust: Double, actualDirection: Double, now: Date) {
        let windError = abs(forecast.predictedWind - actualWind)
        let gustError = abs(forecast.predictedGust - actualGust)
        let directionError = calculateDirectionError(predicted: forecast.predictedDirection, actual: actualDirection)
        let hoursAhead = Int(forecast.forecastTime.timeIntervalSince(forecast.fetchedAt) / 3600)

        let record = AccuracyRecord(
            stationId: forecast.stationId,
            forecastTime: forecast.forecastTime,
            predictedWind: forecast.predictedWind,
            actualWind: actualWind,
            predictedGust: forecast.predictedGust,
            actualGust: actualGust,
            windError: windError,
            gustError: gustError,
            directionError: directionError,
            hoursAhead: hoursAhead,
            recordedAt: now
        )

        // Check if we already have a record for this forecast
        if !accuracyRecords.contains(where: { $0.id == record.id }) {
            accuracyRecords.append(record)
            saveRecords()

            // Update station stats
            updateStationStats(for: forecast.stationId, stationName: forecast.stationName)

            print("[ForecastAccuracy] Recorded comparison for \(forecast.stationName): wind error=\(String(format: "%.1f", windError))kts, gust error=\(String(format: "%.1f", gustError))kts")
        }

        // Remove the used forecast
        storedForecasts.removeAll { $0.id == forecast.id }
        saveForecasts()
    }

    private func calculateDirectionError(predicted: Double, actual: Double) -> Double {
        let diff = abs(predicted - actual)
        return min(diff, 360 - diff)
    }

    private func updateStationStats(for stationId: String, stationName: String) {
        let stationRecords = accuracyRecords.filter { $0.stationId == stationId }

        guard !stationRecords.isEmpty else { return }

        let totalComparisons = stationRecords.count
        let meanWindError = stationRecords.map { $0.windError }.reduce(0, +) / Double(totalComparisons)
        let meanGustError = stationRecords.map { $0.gustError }.reduce(0, +) / Double(totalComparisons)

        let within3Knots = stationRecords.filter { $0.windError <= 3 }.count
        let within5Knots = stationRecords.filter { $0.windError <= 5 }.count

        let percentWithin3Knots = Double(within3Knots) / Double(totalComparisons) * 100
        let percentWithin5Knots = Double(within5Knots) / Double(totalComparisons) * 100

        let stats = StationAccuracyStats(
            stationId: stationId,
            stationName: stationName,
            totalComparisons: totalComparisons,
            meanWindError: meanWindError,
            meanGustError: meanGustError,
            percentWithin3Knots: percentWithin3Knots,
            percentWithin5Knots: percentWithin5Knots,
            lastUpdated: Date()
        )

        stationStats[stationId] = stats
        saveStats()
    }

    // MARK: - Persistence

    private func loadData() {
        // Load stored forecasts
        if let data = UserDefaults.standard.data(forKey: storedForecastsKey),
           let forecasts = try? JSONDecoder().decode([StoredForecast].self, from: data) {
            storedForecasts = forecasts
        }

        // Load accuracy records
        if let data = UserDefaults.standard.data(forKey: accuracyRecordsKey),
           let records = try? JSONDecoder().decode([AccuracyRecord].self, from: data) {
            accuracyRecords = records
        }

        // Load station stats
        if let data = UserDefaults.standard.data(forKey: stationStatsKey),
           let stats = try? JSONDecoder().decode([StationAccuracyStats].self, from: data) {
            stationStats = Dictionary(uniqueKeysWithValues: stats.map { ($0.stationId, $0) })
        }

        print("[ForecastAccuracy] Loaded \(storedForecasts.count) forecasts, \(accuracyRecords.count) records, \(stationStats.count) station stats")
    }

    private func saveForecasts() {
        if let data = try? JSONEncoder().encode(storedForecasts) {
            UserDefaults.standard.set(data, forKey: storedForecastsKey)
        }
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(accuracyRecords) {
            UserDefaults.standard.set(data, forKey: accuracyRecordsKey)
        }
    }

    private func saveStats() {
        let statsArray = Array(stationStats.values)
        if let data = try? JSONEncoder().encode(statsArray) {
            UserDefaults.standard.set(data, forKey: stationStatsKey)
        }
    }

    private func cleanupOldData() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxHistoryDays, to: Date()) ?? Date()

        // Remove old forecasts that were never used
        let oldCount = storedForecasts.count
        storedForecasts.removeAll { $0.forecastTime < Date() }

        // Remove old accuracy records
        let oldRecordsCount = accuracyRecords.count
        accuracyRecords.removeAll { $0.recordedAt < cutoffDate }

        if storedForecasts.count != oldCount {
            saveForecasts()
        }

        if accuracyRecords.count != oldRecordsCount {
            saveRecords()
            // Recalculate stats after cleanup
            for (stationId, stats) in stationStats {
                updateStationStats(for: stationId, stationName: stats.stationName)
            }
        }

        print("[ForecastAccuracy] Cleanup: removed \(oldCount - storedForecasts.count) old forecasts, \(oldRecordsCount - accuracyRecords.count) old records")
    }
}
