import Foundation
import SwiftUI

// MARK: - Diabox Service

actor DiaboxService {
    static let shared = DiaboxService()

    private let vercelAPI = "https://api.levent.live/api/diabox"

    private init() {}

    // MARK: - Fetch All Stations

    func fetchStationsFromVercel() async -> [WindStation] {
        guard let url = URL(string: vercelAPI) else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Log.network("Diabox Vercel: HTTP \(httpResponse.statusCode)")
                return []
            }

            let decoded = try JSONDecoder().decode(DiaboxStationsResponse.self, from: data)

            Log.network("Diabox Vercel: Got \(decoded.stations.count) stations (cached: \(decoded.cached))")

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            return decoded.stations.compactMap { station -> WindStation? in
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
                    source: .diabox,
                    lastUpdate: lastUpdate,
                    pressure: station.pressure,
                    temperature: station.temperature,
                    humidity: station.humidity
                )
            }
        } catch {
            Log.error("Diabox Vercel error: \(error)")
            return []
        }
    }

    // MARK: - Fetch History

    func fetchHistory(stationId: String, hours: Int = 6) async throws -> [DiaboxObservation] {
        let rawId = stationId.replacingOccurrences(of: "diabox_", with: "")
        let hoursParam = min(hours, 72)

        guard let url = URL(string: "\(vercelAPI)?history=\(rawId)&hours=\(hoursParam)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(DiaboxHistoryResponse.self, from: data)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let observations = decoded.observations.compactMap { obs -> DiaboxObservation? in
            guard let date = dateFormatter.date(from: obs.ts) ?? ISO8601DateFormatter().date(from: obs.ts) else {
                return nil
            }
            return DiaboxObservation(
                timestamp: date,
                windSpeed: obs.wind,
                gustSpeed: obs.gust,
                direction: obs.dir
            )
        }

        Log.network("Diabox History: Got \(observations.count) observations for \(rawId) (last \(hoursParam)h)")
        return observations.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Models

struct DiaboxObservation {
    let timestamp: Date
    let windSpeed: Double   // knots
    let gustSpeed: Double   // knots
    let direction: Double   // degrees
}

// MARK: - Codable Response Models

private struct DiaboxStationsResponse: Codable {
    let stations: [DiaboxStationData]
    let cached: Bool
    let count: Int?
}

private struct DiaboxStationData: Codable {
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
    let temperature: Double?
    let pressure: Double?
    let humidity: Double?
}

private struct DiaboxHistoryResponse: Codable {
    let stationId: String
    let observations: [DiaboxHistoryEntry]
    let count: Int?
    let hours: Int?
    let error: String?
}

private struct DiaboxHistoryEntry: Codable {
    let ts: String
    let wind: Double
    let gust: Double
    let dir: Double
}
