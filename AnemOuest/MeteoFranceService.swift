//
//  MeteoFranceService.swift
//  AnemOuest
//
//  Service for Météo France data via two Vercel APIs
//  API-1: Atlantic coast stations (Bretagne → Pays Basque)
//  API-2: North coast + Mediterranean + Corsica stations
//

import Foundation
import CoreLocation

// MARK: - Météo France Service (via Vercel APIs)

actor MeteoFranceService {
    static let shared = MeteoFranceService()

    // Single API base for both station sets
    private let apiBase = "https://api.levent.live/api"

    private init() {}

    // MARK: - Fetch all stations from both APIs

    func fetchAllStationsFromVercel() async -> [WindStation] {
        // Call both APIs in parallel
        async let stations1 = fetchStations(endpoint: "stations", label: "Atlantic")
        async let stations2 = fetchStations(endpoint: "mf2-stations", label: "Nord+Med")

        let all = await stations1 + stations2
        Log.network("MF Vercel: Total \(all.count) stations from both APIs")
        return all
    }

    private func fetchStations(endpoint: String, label: String) async -> [WindStation] {
        guard let url = URL(string: "\(apiBase)/\(endpoint)") else { return [] }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(VercelStationsResponse.self, from: data)

            Log.network("MF \(label): Got \(response.stations.count) stations (cached: \(response.cached))")

            return response.stations.map { station in
                let timestamp = ISO8601DateFormatter().date(from: station.ts) ?? Date()
                let isOnline = Date().timeIntervalSince(timestamp) <= 20 * 60

                return WindStation(
                    id: station.id,
                    name: station.name,
                    latitude: station.lat,
                    longitude: station.lon,
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.dir,
                    isOnline: isOnline,
                    source: .meteoFrance,
                    lastUpdate: timestamp,
                    pressure: station.pressure,
                    temperature: station.temperature,
                    humidity: station.humidity
                )
            }
        } catch {
            Log.error("MF \(label) error: \(error)")
            return []
        }
    }

    // MARK: - Fetch history (try both APIs)

    func fetchHistoryFromVercel(stationId: String, hours: Int = 24) async throws -> [MFObservation] {
        // Try API-1 first, then API-2 (mf2- prefix)
        if let result = try? await fetchHistory(endpoint: "history", stationId: stationId, hours: hours), !result.isEmpty {
            return result
        }
        return try await fetchHistory(endpoint: "mf2-history", stationId: stationId, hours: hours)
    }

    private func fetchHistory(endpoint: String, stationId: String, hours: Int) async throws -> [MFObservation] {
        guard let url = URL(string: "\(apiBase)/\(endpoint)?stationId=\(stationId)&hours=\(hours)") else {
            return []
        }

        let request = AppConstants.apiRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(VercelHistoryResponse.self, from: data)

        return response.observations.map { obs in
            MFObservation(
                stationId: stationId,
                latitude: 0,
                longitude: 0,
                timestamp: ISO8601DateFormatter().date(from: obs.ts) ?? Date(),
                windSpeed: obs.wind,
                windGust: obs.gust,
                windDirection: obs.dir,
                gustDirection: obs.dir
            )
        }
    }
}

// MARK: - Models

struct MFStation {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let altitude: Int
    let pack: String
}

struct MFObservation {
    let stationId: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let windSpeed: Double      // knots
    let windGust: Double       // knots
    let windDirection: Double  // degrees
    let gustDirection: Double  // degrees
}

// MARK: - Vercel API Response Models

private struct VercelStationsResponse: Codable {
    let stations: [VercelStation]
    let cached: Bool
    let count: Int?
}

private struct VercelStation: Codable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let wind: Double
    let gust: Double
    let dir: Double
    let ts: String
    let temperature: Double?
    let pressure: Double?
    let humidity: Double?
}

private struct VercelHistoryResponse: Codable {
    let observations: [VercelObservation]
    let cached: Bool
}

private struct VercelObservation: Codable {
    let ts: String
    let wind: Double
    let gust: Double
    let dir: Double
}
