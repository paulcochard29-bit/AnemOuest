import Foundation

// MARK: - Offline Cache
/// Persistent disk cache for forecast, tide, and marine data.
/// Allows the app to show stale data when offline.

final class OfflineCache {
    static let shared = OfflineCache()

    private let cacheDir: URL
    private let queue = DispatchQueue(label: "com.anemouest.offlinecache", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("OfflineData", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Generic Codable Cache

    private struct CacheEntry<T: Codable>: Codable {
        let data: T
        let cachedAt: Date
    }

    private func filePath(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(120)
        return cacheDir.appendingPathComponent("\(safeKey).json")
    }

    func save<T: Codable>(_ value: T, forKey key: String) {
        queue.async {
            let entry = CacheEntry(data: value, cachedAt: Date())
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: self.filePath(for: key))
        }
    }

    func load<T: Codable>(_ type: T.Type, forKey key: String, maxAge: TimeInterval? = nil) -> (data: T, cachedAt: Date)? {
        let url = filePath(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else {
            return nil
        }

        if let maxAge = maxAge, Date().timeIntervalSince(entry.cachedAt) > maxAge {
            return nil // Expired
        }

        return (entry.data, entry.cachedAt)
    }

    func remove(forKey key: String) {
        let url = filePath(for: key)
        try? FileManager.default.removeItem(at: url)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Convenience Keys

    static func forecastKey(lat: Double, lon: Double, model: String) -> String {
        "forecast_\(model)_\(String(format: "%.2f", lat))_\(String(format: "%.2f", lon))"
    }

    static func tideKey(portId: String) -> String {
        "tide_\(portId)"
    }

    static func marineKey(lat: Double, lon: Double) -> String {
        "marine_\(String(format: "%.2f", lat))_\(String(format: "%.2f", lon))"
    }

    static func waveBuoyKey() -> String {
        "wavebuoys"
    }

    // MARK: - Cache Inventory

    /// Returns all cache entries with their keys and ages
    func allEntries() -> [(key: String, age: TimeInterval)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files.compactMap { url -> (String, TimeInterval)? in
            guard url.pathExtension == "json" else { return nil }
            let key = url.deletingPathExtension().lastPathComponent
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { return nil }
            return (key, Date().timeIntervalSince(modDate))
        }
        .sorted { $0.1 < $1.1 }
    }

    /// Total disk size of all offline cache files
    func totalSize() -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { sum, file in
            sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Cache Age Display

    func cacheAge(forKey key: String) -> String? {
        let url = filePath(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<EmptyPlaceholder>.self, from: data) else {
            return nil
        }

        let age = Date().timeIntervalSince(entry.cachedAt)
        if age < 60 { return "< 1 min" }
        if age < 3600 { return "\(Int(age / 60)) min" }
        if age < 86400 { return "\(Int(age / 3600))h" }
        return "\(Int(age / 86400))j"
    }

    private struct EmptyPlaceholder: Codable {
        // Only decode the cachedAt field via CacheEntry wrapper
    }
}

// MARK: - Codable Wrappers for Non-Codable Types

/// Codable wrapper for ForecastData (HourlyForecast + DailyForecast are not Codable by default)
struct CodableForecastData: Codable {
    let hourly: [CodableHourlyForecast]
    let daily: [CodableDailyForecast]
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
    let model: String

    init(from forecast: ForecastData) {
        hourly = forecast.hourly.map(CodableHourlyForecast.init)
        daily = forecast.daily.map(CodableDailyForecast.init)
        fetchedAt = forecast.fetchedAt
        latitude = forecast.latitude
        longitude = forecast.longitude
        model = forecast.model.rawValue
    }

    func toForecastData() -> ForecastData? {
        guard let weatherModel = WeatherModel(rawValue: model) else { return nil }
        return ForecastData(
            hourly: hourly.map { $0.toHourlyForecast() },
            daily: daily.map { $0.toDailyForecast() },
            fetchedAt: fetchedAt,
            latitude: latitude,
            longitude: longitude,
            model: weatherModel
        )
    }
}

struct CodableHourlyForecast: Codable {
    let time: Date
    let windSpeed: Double
    let windGusts: Double
    let windDirection: Double
    let temperature: Double
    let precipitation: Double
    let weatherCode: Int
    let cloudCover: Int
    let cloudCoverLow: Int
    let cloudCoverMid: Int
    let cloudCoverHigh: Int
    let humidity: Int
    let visibility: Double
    let pressureMSL: Double?

    init(from h: HourlyForecast) {
        time = h.time; windSpeed = h.windSpeed; windGusts = h.windGusts
        windDirection = h.windDirection; temperature = h.temperature
        precipitation = h.precipitation; weatherCode = h.weatherCode
        cloudCover = h.cloudCover; cloudCoverLow = h.cloudCoverLow
        cloudCoverMid = h.cloudCoverMid; cloudCoverHigh = h.cloudCoverHigh
        humidity = h.humidity; visibility = h.visibility; pressureMSL = h.pressureMSL
    }

    func toHourlyForecast() -> HourlyForecast {
        HourlyForecast(
            time: time, windSpeed: windSpeed, windGusts: windGusts,
            windDirection: windDirection, temperature: temperature,
            precipitation: precipitation, weatherCode: weatherCode,
            cloudCover: cloudCover, cloudCoverLow: cloudCoverLow,
            cloudCoverMid: cloudCoverMid, cloudCoverHigh: cloudCoverHigh,
            humidity: humidity, visibility: visibility, pressureMSL: pressureMSL
        )
    }
}

struct CodableDailyForecast: Codable {
    let date: Date
    let windSpeedMax: Double
    let windGustsMax: Double
    let temperatureMin: Double
    let temperatureMax: Double
    let precipitationSum: Double
    let weatherCode: Int

    init(from d: DailyForecast) {
        date = d.date; windSpeedMax = d.windSpeedMax; windGustsMax = d.windGustsMax
        temperatureMin = d.temperatureMin; temperatureMax = d.temperatureMax
        precipitationSum = d.precipitationSum; weatherCode = d.weatherCode
    }

    func toDailyForecast() -> DailyForecast {
        DailyForecast(
            date: date, windSpeedMax: windSpeedMax, windGustsMax: windGustsMax,
            temperatureMin: temperatureMin, temperatureMax: temperatureMax,
            precipitationSum: precipitationSum, weatherCode: weatherCode
        )
    }
}
