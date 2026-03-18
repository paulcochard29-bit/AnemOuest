import Foundation
import Combine

// MARK: - Models

struct StoredWaveForecast: Codable, Identifiable {
    var id: String { "\(buoyId)_\(forecastTime.timeIntervalSince1970)" }

    let buoyId: String
    let buoyName: String
    let latitude: Double
    let longitude: Double
    let forecastTime: Date
    let fetchedAt: Date
    let predictedHeight: Double    // meters
    let predictedPeriod: Double    // seconds
    let predictedDirection: Double // degrees
}

struct WaveAccuracyRecord: Codable, Identifiable {
    var id: String { "\(buoyId)_\(forecastTime.timeIntervalSince1970)" }

    let buoyId: String
    let forecastTime: Date
    let predictedHeight: Double
    let actualHeight: Double
    let predictedPeriod: Double
    let actualPeriod: Double
    let heightError: Double        // |predicted - actual| in meters
    let periodError: Double        // |predicted - actual| in seconds
    let directionError: Double     // circular error in degrees
    let hoursAhead: Int
    let recordedAt: Date
}

struct BuoyAccuracyStats: Codable, Identifiable {
    var id: String { buoyId }

    let buoyId: String
    let buoyName: String
    var totalComparisons: Int
    var meanHeightError: Double    // MAE wave height in meters
    var meanPeriodError: Double    // MAE period in seconds
    var percentWithin03m: Double   // % forecasts within +/-0.3m
    var percentWithin05m: Double   // % forecasts within +/-0.5m
    var lastUpdated: Date
    var latitude: Double?
    var longitude: Double?
}

// MARK: - Service

class WaveForecastAccuracyService: ObservableObject {
    static let shared = WaveForecastAccuracyService()

    private let storedForecastsKey = "storedWaveForecasts_v1"
    private let accuracyRecordsKey = "waveAccuracyRecords_v1"
    private let buoyStatsKey = "buoyAccuracyStats_v1"

    private let maxHistoryDays = 30
    private let minComparisonsForStats = 5
    private let timeToleranceMinutes = 30.0

    @Published private(set) var buoyStats: [String: BuoyAccuracyStats] = [:]
    @Published private(set) var isLoading: Bool = false

    private var storedForecasts: [StoredWaveForecast] = []
    private var accuracyRecords: [WaveAccuracyRecord] = []

    private init() {
        loadData()
        cleanupOldData()
    }

    // MARK: - Public Methods

    /// Store wave forecasts for a buoy when they are loaded
    func storeForecast(buoyId: String, buoyName: String, latitude: Double, longitude: Double, forecasts: [HourlyWave]) {
        let now = Date()

        // Store forecasts for the next 12 hours
        let futureForecasts = forecasts.filter { forecast in
            let hoursAhead = forecast.time.timeIntervalSince(now) / 3600
            return hoursAhead > 0 && hoursAhead <= 12
        }

        // Remove existing forecasts for this buoy that haven't been compared yet
        storedForecasts.removeAll { $0.buoyId == buoyId && $0.forecastTime > now }

        // Add new forecasts
        for forecast in futureForecasts {
            let stored = StoredWaveForecast(
                buoyId: buoyId,
                buoyName: buoyName,
                latitude: latitude,
                longitude: longitude,
                forecastTime: forecast.time,
                fetchedAt: now,
                predictedHeight: forecast.waveHeight,
                predictedPeriod: forecast.wavePeriod,
                predictedDirection: forecast.waveDirection
            )
            storedForecasts.append(stored)
        }

        saveForecasts()
        Log.data("[WaveAccuracy] Stored \(futureForecasts.count) forecasts for \(buoyName)")
    }

    /// Compare actual buoy data with stored forecasts
    func compareWithActual(buoyId: String, latitude: Double, longitude: Double, actualHeight: Double, actualPeriod: Double, actualDirection: Double) {
        let now = Date()
        let tolerance = timeToleranceMinutes * 60

        // Find matching forecast by buoyId within time tolerance
        if let matchingForecast = storedForecasts.first(where: { forecast in
            guard forecast.buoyId == buoyId else { return false }
            let timeDiff = abs(forecast.forecastTime.timeIntervalSince(now))
            return timeDiff <= tolerance
        }) {
            recordComparison(forecast: matchingForecast, actualHeight: actualHeight, actualPeriod: actualPeriod, actualDirection: actualDirection, now: now)
            return
        }

        // Fallback: try to find by coordinates
        if let matchingForecast = storedForecasts.first(where: { forecast in
            let latDiff = abs(forecast.latitude - latitude)
            let lonDiff = abs(forecast.longitude - longitude)
            let timeDiff = abs(forecast.forecastTime.timeIntervalSince(now))
            return latDiff < 0.02 && lonDiff < 0.02 && timeDiff <= tolerance
        }) {
            recordComparison(forecast: matchingForecast, actualHeight: actualHeight, actualPeriod: actualPeriod, actualDirection: actualDirection, now: now)
        }
    }

    /// Get accuracy stats for a buoy
    func getAccuracy(for buoyId: String) -> BuoyAccuracyStats? {
        return buoyStats[buoyId]
    }

    /// Get accuracy percentage for display (within 0.5m tolerance)
    func getAccuracyPercent(for buoyId: String) -> Int? {
        guard let stats = buoyStats[buoyId],
              stats.totalComparisons >= minComparisonsForStats else {
            return nil
        }
        return Int(stats.percentWithin05m)
    }

    /// Get accuracy percentage by location (finds nearest buoy within ~50km)
    func getAccuracyPercent(latitude: Double, longitude: Double) -> Int? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return Int(stats.percentWithin05m)
    }

    /// Get mean height error by location
    func getMeanError(latitude: Double, longitude: Double) -> Double? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return stats.meanHeightError
    }

    /// Get accuracy info (percent + mean error) by location
    func getAccuracyInfo(latitude: Double, longitude: Double) -> (percent: Int, meanError: Double)? {
        guard let stats = getNearestStats(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return (Int(stats.percentWithin05m), stats.meanHeightError)
    }

    private func getNearestStats(latitude: Double, longitude: Double) -> BuoyAccuracyStats? {
        let maxDistance = 0.5 // ~50km in degrees

        var nearestStats: BuoyAccuracyStats?
        var minDistance = Double.infinity

        for stats in buoyStats.values {
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
    func hasEnoughData(for buoyId: String) -> Bool {
        guard let stats = buoyStats[buoyId] else { return false }
        return stats.totalComparisons >= minComparisonsForStats
    }

    // MARK: - Private Methods

    private func recordComparison(forecast: StoredWaveForecast, actualHeight: Double, actualPeriod: Double, actualDirection: Double, now: Date) {
        let heightError = abs(forecast.predictedHeight - actualHeight)
        let periodError = abs(forecast.predictedPeriod - actualPeriod)
        let directionError = calculateDirectionError(predicted: forecast.predictedDirection, actual: actualDirection)
        let hoursAhead = Int(forecast.forecastTime.timeIntervalSince(forecast.fetchedAt) / 3600)

        let record = WaveAccuracyRecord(
            buoyId: forecast.buoyId,
            forecastTime: forecast.forecastTime,
            predictedHeight: forecast.predictedHeight,
            actualHeight: actualHeight,
            predictedPeriod: forecast.predictedPeriod,
            actualPeriod: actualPeriod,
            heightError: heightError,
            periodError: periodError,
            directionError: directionError,
            hoursAhead: hoursAhead,
            recordedAt: now
        )

        // Check if we already have a record for this forecast
        if !accuracyRecords.contains(where: { $0.id == record.id }) {
            accuracyRecords.append(record)
            saveRecords()

            // Update buoy stats
            updateBuoyStats(for: forecast.buoyId, buoyName: forecast.buoyName)

            Log.data("[WaveAccuracy] Recorded comparison for \(forecast.buoyName): height error=\(String(format: "%.2f", heightError))m, period error=\(String(format: "%.1f", periodError))s")
        }

        // Remove the used forecast
        storedForecasts.removeAll { $0.id == forecast.id }
        saveForecasts()
    }

    private func calculateDirectionError(predicted: Double, actual: Double) -> Double {
        let diff = abs(predicted - actual)
        return min(diff, 360 - diff)
    }

    private func updateBuoyStats(for buoyId: String, buoyName: String) {
        let buoyRecords = accuracyRecords.filter { $0.buoyId == buoyId }

        guard !buoyRecords.isEmpty else { return }

        let totalComparisons = buoyRecords.count
        let meanHeightError = buoyRecords.map { $0.heightError }.reduce(0, +) / Double(totalComparisons)
        let meanPeriodError = buoyRecords.map { $0.periodError }.reduce(0, +) / Double(totalComparisons)

        let within03m = buoyRecords.filter { $0.heightError <= 0.3 }.count
        let within05m = buoyRecords.filter { $0.heightError <= 0.5 }.count

        let percentWithin03m = Double(within03m) / Double(totalComparisons) * 100
        let percentWithin05m = Double(within05m) / Double(totalComparisons) * 100

        let stats = BuoyAccuracyStats(
            buoyId: buoyId,
            buoyName: buoyName,
            totalComparisons: totalComparisons,
            meanHeightError: meanHeightError,
            meanPeriodError: meanPeriodError,
            percentWithin03m: percentWithin03m,
            percentWithin05m: percentWithin05m,
            lastUpdated: Date()
        )

        buoyStats[buoyId] = stats
        saveStats()
    }

    // MARK: - Persistence

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: storedForecastsKey),
           let forecasts = try? JSONDecoder().decode([StoredWaveForecast].self, from: data) {
            storedForecasts = forecasts
        }

        if let data = UserDefaults.standard.data(forKey: accuracyRecordsKey),
           let records = try? JSONDecoder().decode([WaveAccuracyRecord].self, from: data) {
            accuracyRecords = records
        }

        if let data = UserDefaults.standard.data(forKey: buoyStatsKey),
           let stats = try? JSONDecoder().decode([BuoyAccuracyStats].self, from: data) {
            buoyStats = Dictionary(uniqueKeysWithValues: stats.map { ($0.buoyId, $0) })
        }

        Log.data("[WaveAccuracy] Loaded \(storedForecasts.count) forecasts, \(accuracyRecords.count) records, \(buoyStats.count) buoy stats")
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
        let statsArray = Array(buoyStats.values)
        if let data = try? JSONEncoder().encode(statsArray) {
            UserDefaults.standard.set(data, forKey: buoyStatsKey)
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
            for (buoyId, stats) in buoyStats {
                updateBuoyStats(for: buoyId, buoyName: stats.buoyName)
            }
        }

        Log.data("[WaveAccuracy] Cleanup: removed \(oldCount - storedForecasts.count) old forecasts, \(oldRecordsCount - accuracyRecords.count) old records")
    }
}
