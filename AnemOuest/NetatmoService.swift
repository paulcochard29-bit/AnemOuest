//
//  NetatmoService.swift
//  AnemOuest
//
//  Service for Netatmo public weather stations (wind data + history)
//

import Foundation

// MARK: - Netatmo Service

actor NetatmoService {
    static let shared = NetatmoService()

    private let vercelAPI = "\(AppConstants.API.anemOuestAPI)/netatmo"

    private init() {}

    // MARK: - Fetch Stations from Vercel (with optional viewport bbox)

    func fetchStationsFromVercel(bbox: WindStationManager.MapBBox? = nil) async -> [WindStation] {
        var urlString = vercelAPI
        if let bbox = bbox {
            urlString += "?lat_sw=\(bbox.latSW)&lon_sw=\(bbox.lonSW)&lat_ne=\(bbox.latNE)&lon_ne=\(bbox.lonNE)"
        }
        guard let url = URL(string: urlString) else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = AppConstants.Timeout.extended
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(NetatmoStationsResponse.self, from: data)

            Log.network("Netatmo Vercel: Got \(response.stations.count) stations (cached: \(response.cached))")

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            return response.stations.compactMap { station -> WindStation? in
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
                    source: .netatmo,
                    lastUpdate: lastUpdate,
                    pressure: station.pressure,
                    temperature: station.temperature,
                    humidity: station.humidity
                )
            }
        } catch {
            Log.error("Netatmo Vercel error: \(error)")
            return []
        }
    }

    // MARK: - Fetch History from Vercel Blob

    func fetchHistory(stationId: String, hours: Int = 24) async throws -> [NetatmoObservation] {
        guard let encodedId = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(vercelAPI)?history=\(encodedId)&hours=\(hours)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            Log.network("Netatmo History: HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let historyResponse = try JSONDecoder().decode(NetatmoHistoryResponse.self, from: data)

        Log.network("Netatmo History: Got \(historyResponse.observations.count) observations for \(stationId)")

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return historyResponse.observations.compactMap { obs in
            guard let date = dateFormatter.date(from: obs.ts) ?? ISO8601DateFormatter().date(from: obs.ts) else {
                return nil
            }

            return NetatmoObservation(
                timestamp: date,
                windSpeed: obs.wind,
                gustSpeed: obs.gust,
                direction: obs.dir
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Observation Model

struct NetatmoObservation {
    let timestamp: Date
    let windSpeed: Double   // knots
    let gustSpeed: Double   // knots
    let direction: Double   // degrees
}

// MARK: - Vercel Response Models

private struct NetatmoStationsResponse: Codable {
    let stations: [NetatmoStationData]
    let cached: Bool
    let count: Int?
}

private struct NetatmoStationData: Codable {
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
    let humidity: Double?
    let pressure: Double?
    let altitude: Int?
}

private struct NetatmoHistoryResponse: Codable {
    let stationId: String
    let source: String?
    let observations: [NetatmoHistoryObservation]
    let count: Int?
    let hours: Int?
}

private struct NetatmoHistoryObservation: Codable {
    let ts: String
    let wind: Double
    let gust: Double
    let dir: Double
}
