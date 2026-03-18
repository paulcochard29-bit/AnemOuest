import Foundation

final class WindService {

    enum WindServiceError: Error {
        case badURL
        case badHTTP(Int)
        case empty
    }

    private static let vercelAPI = "\(AppConstants.API.anemOuestAPI)/windcornouaille"

    // MARK: - Stations cache

    private static var stationsCache: (stations: [VercelWCStation], fetchedAt: Date)?
    private static let stationsCacheDuration: TimeInterval = 120 // 2 minutes

    // MARK: - History cache (per sensor, always 48h)

    private static var historyCache: [String: (observations: [WCWindObservation], fetchedAt: Date)] = [:]
    private static let historyCacheDuration: TimeInterval = 120 // 2 minutes

    // MARK: - Public API

    struct WindChartResult {
        let latest: WCWindObservation
        let samples: [WCChartSample]
    }

    /// Pre-fetch all stations from Vercel (no-op if cache fresh)
    static func warmHistoryCache() async {
        if let cache = stationsCache,
           Date().timeIntervalSince(cache.fetchedAt) < stationsCacheDuration {
            return
        }
        _ = try? await fetchAllStations()
    }

    /// Fetch chart/history data for a sensor via Vercel.
    /// Always fetches 48h on first call and caches; subsequent time range changes filter locally.
    static func fetchChartWC(sensorId: String, timeFrame: Int) async throws -> WindChartResult {
        let requestedHours: Double
        switch timeFrame {
        case 36:  requestedHours = 6
        case 144: requestedHours = 24
        case 288: requestedHours = 48
        default:  requestedHours = 2
        }

        let rawId = sensorId.replacingOccurrences(of: "windcornouaille_", with: "")
        let allObservations = try await fetchHistory48h(sensorId: rawId)

        // Filter to requested time range
        let cutoff = Date().timeIntervalSince1970 - requestedHours * 3600
        let filtered = allObservations.filter { $0.ts >= cutoff }

        guard let latest = filtered.max(by: { $0.ts < $1.ts }) else {
            throw WindServiceError.empty
        }

        let samples = observationsToSamples(filtered)
        return WindChartResult(latest: latest, samples: samples)
    }

    /// Fetch all stations from Vercel (used by WindStationService)
    static func fetchAllStations() async throws -> [VercelWCStation] {
        if let cache = stationsCache,
           Date().timeIntervalSince(cache.fetchedAt) < stationsCacheDuration {
            return cache.stations
        }

        guard let url = URL(string: vercelAPI) else {
            throw WindServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConstants.Timeout.extended
        request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WindServiceError.badHTTP(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(VercelWCStationsResponse.self, from: data)
        stationsCache = (stations: decoded.stations, fetchedAt: Date())
        return decoded.stations
    }

    // MARK: - Internal

    /// Fetch 48h of history for a sensor. Returns cached data if fresh.
    private static func fetchHistory48h(sensorId: String) async throws -> [WCWindObservation] {
        if let cached = historyCache[sensorId],
           Date().timeIntervalSince(cached.fetchedAt) < historyCacheDuration {
            return cached.observations
        }

        guard let url = URL(string: "\(vercelAPI)?history=\(sensorId)&hours=48") else {
            throw WindServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConstants.Timeout.extended
        request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WindServiceError.badHTTP(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(VercelWCHistoryResponse.self, from: data)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        let observations: [WCWindObservation] = decoded.observations.compactMap { obs in
            guard let date = formatter.date(from: obs.ts) ?? fallbackFormatter.date(from: obs.ts) else {
                return nil
            }
            return WCWindObservation(
                ts: date.timeIntervalSince1970,
                ws: WCWindSpeed(moy: WCScalar(obs.wind), max: WCScalar(obs.gust)),
                wd: WCWindDir(moy: WCScalar(obs.dir))
            )
        }

        historyCache[sensorId] = (observations: observations, fetchedAt: Date())
        return observations
    }

    // MARK: - Helpers

    private static func observationsToSamples(_ observations: [WCWindObservation]) -> [WCChartSample] {
        observations
            .sorted(by: { $0.ts < $1.ts })
            .flatMap { obs -> [WCChartSample] in
                let date = Date(timeIntervalSince1970: obs.ts)
                let wind = obs.ws.moy.value ?? .nan
                let gust = obs.ws.max.value ?? .nan

                var out: [WCChartSample] = []
                if wind.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_wind", t: date, value: wind, kind: .wind))
                }
                if gust.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_gust", t: date, value: gust, kind: .gust))
                }
                if let dir = obs.wd.moy.value, dir.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_dir", t: date, value: dir, kind: .dir))
                }
                return out
            }
    }
}

// MARK: - Vercel Response Models

private struct VercelWCStationsResponse: Codable {
    let stations: [VercelWCStation]
    let cached: Bool
    let count: Int
}

struct VercelWCStation: Codable {
    let id: String
    let stableId: String
    let name: String
    let lat: Double
    let lon: Double
    let wind: Double
    let gust: Double
    let direction: Double
    let isOnline: Bool
    let source: String
    let ts: String

    func toObservation() -> WCWindObservation {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: ts) ?? ISO8601DateFormatter().date(from: ts) ?? Date()
        return WCWindObservation(
            ts: date.timeIntervalSince1970,
            ws: WCWindSpeed(moy: WCScalar(wind), max: WCScalar(gust)),
            wd: WCWindDir(moy: WCScalar(direction))
        )
    }
}

private struct VercelWCHistoryResponse: Codable {
    let stationId: String
    let name: String
    let source: String
    let observations: [VercelWCHistoryEntry]
    let count: Int
    let hours: Int
}

private struct VercelWCHistoryEntry: Codable {
    let ts: String
    let wind: Double?
    let gust: Double?
    let dir: Double?
}
