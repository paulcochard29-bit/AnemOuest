//
//  GoWindVercelService.swift
//  AnemOuest
//
//  Service for GoWind API via Vercel (Holfuy & Windguru with history)
//

import Foundation

// MARK: - GoWind Vercel Service

actor GoWindVercelService {
    static let shared = GoWindVercelService()

    private let vercelAPI = "https://api.levent.live/api/gowind"

    private init() {}

    // MARK: - Fetch History from Vercel

    /// Fetch historical observations for a GoWind station (Holfuy or Windguru)
    /// - Parameters:
    ///   - stationId: The stable ID in format "source_id" (e.g., "holfuy_123" or "windguru_456")
    ///   - hours: Number of hours of history to fetch (default 24)
    /// - Returns: Array of observations sorted by time
    func fetchHistory(stationId: String, hours: Int = 24) async throws -> [GoWindObservation] {
        // URL encode the station ID
        guard let encodedId = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(vercelAPI)?history=\(encodedId)&hours=\(hours)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            Log.network("GoWind Vercel: HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let historyResponse = try JSONDecoder().decode(GoWindHistoryResponse.self, from: data)

        Log.network("GoWind Vercel: Got \(historyResponse.observations.count) observations for \(stationId)")

        // Convert to observations
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return historyResponse.observations.compactMap { obs in
            guard let date = dateFormatter.date(from: obs.ts) ?? ISO8601DateFormatter().date(from: obs.ts) else {
                return nil
            }

            return GoWindObservation(
                timestamp: date,
                windSpeed: obs.wind,
                gustSpeed: obs.gust,
                direction: obs.dir
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Fetch All Stations from Vercel (optional, can use direct API too)

    func fetchStationsFromVercel() async -> [WindStation] {
        guard let url = URL(string: vercelAPI) else { return [] }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GoWindStationsResponse.self, from: data)

            Log.network("GoWind Vercel: Got \(response.stations.count) stations (cached: \(response.cached))")

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let excludedNames: Set<String> = ["keranguyader"]
            return response.stations.compactMap { station -> WindStation? in
                if excludedNames.contains(station.name.lowercased()) { return nil }
                let source: WindSource = station.source == "holfuy" ? .holfuy : .windguru

                let lastUpdate: Date?
                if let ts = station.ts {
                    lastUpdate = dateFormatter.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
                } else {
                    lastUpdate = nil
                }

                return WindStation(
                    id: station.id,
                    name: station.name,
                    latitude: station.lat,
                    longitude: station.lon,
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    isOnline: station.isOnline,
                    source: source,
                    lastUpdate: lastUpdate
                )
            }
        } catch {
            Log.error("GoWind Vercel error: \(error)")
            return []
        }
    }
}

// MARK: - Models

struct GoWindObservation {
    let timestamp: Date
    let windSpeed: Double   // knots
    let gustSpeed: Double   // knots
    let direction: Double   // degrees
}

// MARK: - Vercel Response Models

private struct GoWindStationsResponse: Codable {
    let stations: [GoWindStationData]
    let cached: Bool
    let count: Int?
    let historyStations: Int?
}

private struct GoWindStationData: Codable {
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
    let ts: String?
}

private struct GoWindHistoryResponse: Codable {
    let stationId: String
    let name: String?
    let source: String?
    let observations: [GoWindHistoryObservation]
    let count: Int?
    let hours: Int?
    let error: String?
}

private struct GoWindHistoryObservation: Codable {
    let ts: String
    let wind: Double
    let gust: Double
    let dir: Double
}
