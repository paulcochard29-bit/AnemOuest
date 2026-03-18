//
//  PioupiouVercelService.swift
//  AnemOuest
//
//  Service for Pioupiou API (direct archive + Vercel fallback)
//

import Foundation

// MARK: - Pioupiou Service

actor PioupiouVercelService {
    static let shared = PioupiouVercelService()

    private let vercelAPI = "https://api.levent.live/api/pioupiou"
    private let archiveAPI = "https://api.pioupiou.fr/v1/archive"

    private init() {}

    // MARK: - Fetch History from Official Pioupiou Archive API

    /// Fetch historical observations directly from Pioupiou Archive API
    /// - Parameters:
    ///   - stationId: The station ID (e.g., "pioupiou_123" or just "123")
    ///   - hours: Number of hours of history to fetch
    /// - Returns: Array of observations sorted by time
    func fetchHistoryDirect(stationId: String, hours: Int = 24) async throws -> [PioupiouObservation] {
        // Extract numeric ID from stableId (e.g., "pioupiou_123" -> "123")
        let numericId = stationId.replacingOccurrences(of: "pioupiou_", with: "")

        // Use convenient start parameters
        // Always use at least last-day to ensure we have data (last-hour often empty)
        let startParam: String
        switch hours {
        case ...24: startParam = "last-day"
        case ...168: startParam = "last-week"
        default: startParam = "last-month"
        }

        guard let url = URL(string: "\(archiveAPI)/\(numericId)?start=\(startParam)&stop=now") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            Log.network("Pioupiou Archive: HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let archiveResponse = try JSONDecoder().decode(PioupiouArchiveResponse.self, from: data)

        // Filter by actual time range
        let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)

        // ISO8601 date formatter for parsing timestamps
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let observations = archiveResponse.data.compactMap { row -> PioupiouObservation? in
            guard row.count >= 7 else { return nil }

            // row format: [time (ISO string), lat, lon, wind_min, wind_avg, wind_max, heading, pressure?]
            guard let timeString = row[0].value as? String else { return nil }

            // Parse ISO 8601 date string
            guard let date = dateFormatter.date(from: timeString) ?? ISO8601DateFormatter().date(from: timeString) else {
                return nil
            }

            guard date >= cutoffDate else { return nil }

            // wind speeds are in km/h, convert to knots (1 km/h = 0.539957 knots)
            let windAvgKmh = row[4].value as? Double ?? 0
            let windMaxKmh = row[5].value as? Double ?? 0
            let direction = row[6].value as? Double ?? 0

            return PioupiouObservation(
                timestamp: date,
                windSpeed: windAvgKmh * 0.539957,
                gustSpeed: windMaxKmh * 0.539957,
                direction: direction
            )
        }

        Log.network("Pioupiou Archive: Got \(observations.count) observations for \(numericId) (last \(hours)h)")

        return observations.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Fetch History from Vercel

    /// Fetch historical observations for a Pioupiou station
    /// - Parameters:
    ///   - stationId: The station ID (e.g., "pioupiou_123" or just "123")
    ///   - hours: Number of hours of history to fetch (default 24)
    /// - Returns: Array of observations sorted by time
    func fetchHistory(stationId: String, hours: Int = 24) async throws -> [PioupiouObservation] {
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
            Log.network("Pioupiou Vercel: HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let historyResponse = try JSONDecoder().decode(PioupiouHistoryResponse.self, from: data)

        Log.network("Pioupiou Vercel: Got \(historyResponse.observations.count) observations for \(stationId)")

        // Convert to observations
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return historyResponse.observations.compactMap { obs in
            guard let date = dateFormatter.date(from: obs.ts) ?? ISO8601DateFormatter().date(from: obs.ts) else {
                return nil
            }

            return PioupiouObservation(
                timestamp: date,
                windSpeed: obs.wind,
                gustSpeed: obs.gust,
                direction: obs.dir
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Fetch All Stations from Vercel

    func fetchStationsFromVercel() async -> [WindStation] {
        guard let url = URL(string: vercelAPI) else { return [] }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PioupiouStationsResponse.self, from: data)

            Log.network("Pioupiou Vercel: Got \(response.stations.count) stations (cached: \(response.cached))")

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
                    source: .pioupiou,
                    lastUpdate: lastUpdate,
                    stationDescription: station.description,
                    picture: station.picture,
                    pressure: station.pressure
                )
            }
        } catch {
            Log.error("Pioupiou Vercel error: \(error)")
            return []
        }
    }
}

// MARK: - Models

struct PioupiouObservation {
    let timestamp: Date
    let windSpeed: Double   // knots
    let gustSpeed: Double   // knots
    let direction: Double   // degrees
}

// MARK: - Vercel Response Models

private struct PioupiouStationsResponse: Codable {
    let stations: [PioupiouStationData]
    let cached: Bool
    let count: Int?
    let historyStations: Int?
}

private struct PioupiouStationData: Codable {
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
    // Additional metadata
    let description: String?
    let picture: String?
    let pressure: Double?
    let state: String?
}

private struct PioupiouHistoryResponse: Codable {
    let stationId: String
    let name: String?
    let source: String?
    let observations: [PioupiouHistoryObservation]
    let count: Int?
    let hours: Int?
    let error: String?
}

private struct PioupiouHistoryObservation: Codable {
    let ts: String
    let wind: Double
    let gust: Double
    let dir: Double
}

// MARK: - Pioupiou Archive API Response

private struct PioupiouArchiveResponse: Codable {
    let doc: String?
    let license: String?
    let attribution: String?
    let legend: [String]?
    let units: [String]?
    let data: [[AnyCodable]]
}

// Helper to decode mixed-type arrays
// Marked @unchecked Sendable since only Sendable types (Double, String) are stored
private struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if container.decodeNil() {
            value = 0.0
        } else {
            value = 0.0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? Double {
            try container.encode(v)
        } else if let v = value as? String {
            try container.encode(v)
        }
    }
}

extension AnyCodable {
    var doubleValue: Double? {
        value as? Double
    }
}

extension Array where Element == AnyCodable {
    subscript(safe index: Int) -> Any? {
        guard index >= 0 && index < count else { return nil }
        return self[index].value
    }
}
