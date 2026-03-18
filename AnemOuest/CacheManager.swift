import Foundation

// MARK: - Cache Manager

final class CacheManager {
    static let shared = CacheManager()

    private let stationsKey = "cachedStations"
private let cacheTimestampKey = "cacheTimestamp"

    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    // MARK: - Cache Timestamp

    var cacheDate: Date? {
        UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date
    }

    var cacheAge: String? {
        guard let date = cacheDate else { return nil }
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "il y a \(seconds)s"
        } else if seconds < 3600 {
            return "il y a \(seconds / 60)min"
        } else if seconds < 86400 {
            return "il y a \(seconds / 3600)h"
        } else {
            return "il y a \(seconds / 86400)j"
        }
    }

    private func updateCacheTimestamp() {
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }

    // MARK: - WindStations Cache

    func saveStations(_ stations: [WindStation]) {
        let cacheable = stations.map { CacheableStation(from: $0) }

        do {
            let data = try JSONEncoder().encode(cacheable)
            let url = cacheDirectory.appendingPathComponent("stations.json")
            try data.write(to: url)
            updateCacheTimestamp()
            Log.data("Cache: Saved \(stations.count) stations")
        } catch {
            Log.data("Cache: Failed to save stations - \(error)")
        }
    }

    func loadStations() -> [WindStation] {
        let url = cacheDirectory.appendingPathComponent("stations.json")

        guard fileManager.fileExists(atPath: url.path) else {
            Log.data("Cache: No cached stations found")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let cacheable = try JSONDecoder().decode([CacheableStation].self, from: data)
            let stations = cacheable.map { $0.toWindStation() }
            Log.data("Cache: Loaded \(stations.count) stations")
            return stations
        } catch {
            Log.data("Cache: Failed to load stations - \(error)")
            return []
        }
    }

    // MARK: - Cleanup Expired Cache

    /// Remove cache files older than 24 hours. Called from background processing task.
    func cleanupExpiredCache() {
        let maxAge: TimeInterval = 24 * 3600 // 24 hours
        let now = Date()
        var removedCount = 0

        // Check known cache files
        let cacheFiles = ["stations.json", "forecasts.json", "tides.json", "wave_buoys.json"]

        for filename in cacheFiles {
            let url = cacheDirectory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            do {
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                if let modDate = attrs[.modificationDate] as? Date,
                   now.timeIntervalSince(modDate) > maxAge {
                    try fileManager.removeItem(at: url)
                    removedCount += 1
                }
            } catch {
                Log.data("Cache cleanup: Failed for \(filename) - \(error)")
            }
        }

        // Clean up webcam cache directory if it exists
        let webcamDir = cacheDirectory.appendingPathComponent("webcams")
        if fileManager.fileExists(atPath: webcamDir.path) {
            do {
                let files = try fileManager.contentsOfDirectory(at: webcamDir, includingPropertiesForKeys: [.contentModificationDateKey])
                for file in files {
                    let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modDate = values.contentModificationDate,
                       now.timeIntervalSince(modDate) > maxAge {
                        try fileManager.removeItem(at: file)
                        removedCount += 1
                    }
                }
            } catch {
                Log.data("Cache cleanup: Webcam dir error - \(error)")
            }
        }

        if removedCount > 0 {
            Log.data("Cache cleanup: Removed \(removedCount) expired files")
        }
    }

    // MARK: - Clear Cache

    func clearCache() {
        let stationsURL = cacheDirectory.appendingPathComponent("stations.json")
        let observationsURL = cacheDirectory.appendingPathComponent("observations.json")

        try? fileManager.removeItem(at: stationsURL)
        try? fileManager.removeItem(at: observationsURL)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)

        Log.data("Cache: Cleared all cached data")
    }
}

// MARK: - Cacheable Station (Codable wrapper)

private struct CacheableStation: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let wind: Double
    let gust: Double
    let direction: Double
    let isOnline: Bool
    let source: String
    let lastUpdate: Date?
    // Additional metadata
    let altitude: Int?
    let stationDescription: String?
    let picture: String?
    let pressure: Double?
    let temperature: Double?
    let humidity: Double?

    init(from station: WindStation) {
        self.id = station.id
        self.name = station.name
        self.latitude = station.latitude
        self.longitude = station.longitude
        self.wind = station.wind
        self.gust = station.gust
        self.direction = station.direction
        self.isOnline = station.isOnline
        self.source = station.source.rawValue
        self.lastUpdate = station.lastUpdate
        self.altitude = station.altitude
        self.stationDescription = station.stationDescription
        self.picture = station.picture
        self.pressure = station.pressure
        self.temperature = station.temperature
        self.humidity = station.humidity
    }

    func toWindStation() -> WindStation {
        WindStation(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            wind: wind,
            gust: gust,
            direction: direction,
            isOnline: isOnline,
            source: WindSource(rawValue: source) ?? .pioupiou,
            lastUpdate: lastUpdate,
            altitude: altitude,
            stationDescription: stationDescription,
            picture: picture,
            pressure: pressure,
            temperature: temperature,
            humidity: humidity
        )
    }
}
