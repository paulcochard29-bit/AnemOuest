//
//  SurfForecastService.swift
//  AnemOuest
//
//  Service de prévisions de houle pour les spots de surf
//  Utilise l'API Open-Meteo Marine (gratuit, sans clé API)
//

import Foundation
import CoreLocation
import Combine

// MARK: - Models

struct SurfWaveForecast: Identifiable {
    let id = UUID()
    let timestamp: Date
    let waveHeight: Double?        // Hauteur significative (m)
    let wavePeriod: Double?        // Période des vagues (s)
    let waveDirection: Double?     // Direction des vagues (°)
    let swellHeight: Double?       // Hauteur de houle (m)
    let swellPeriod: Double?       // Période de houle (s)
    let swellDirection: Double?    // Direction de houle (°)

    /// Hauteur principale (houle si disponible, sinon vagues combinées)
    var primaryHeight: Double? {
        swellHeight ?? waveHeight
    }

    /// Période principale
    var primaryPeriod: Double? {
        swellPeriod ?? wavePeriod
    }

    /// Direction principale
    var primaryDirection: Double? {
        swellDirection ?? waveDirection
    }
}

struct SpotWaveForecast {
    let spotId: String
    let spotName: String
    let latitude: Double
    let longitude: Double
    let forecasts: [SurfWaveForecast]
    let fetchedAt: Date

    /// Prévision actuelle (heure la plus proche)
    var current: SurfWaveForecast? {
        let now = Date()
        return forecasts.min(by: { abs($0.timestamp.timeIntervalSince(now)) < abs($1.timestamp.timeIntervalSince(now)) })
    }

    /// Prévisions pour les prochaines 24h
    var next24Hours: [SurfWaveForecast] {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
        return forecasts.filter { $0.timestamp >= now && $0.timestamp <= tomorrow }
    }
}

// MARK: - API Response Models

private struct MarineAPIResponse: Codable {
    let latitude: Double
    let longitude: Double
    let hourly: MarineHourlyData
    let hourly_units: MarineUnits?
}

private struct MarineHourlyData: Codable {
    let time: [String]
    let wave_height: [Double?]?
    let wave_period: [Double?]?
    let wave_direction: [Double?]?
    let swell_wave_height: [Double?]?
    let swell_wave_period: [Double?]?
    let swell_wave_direction: [Double?]?
}

private struct MarineUnits: Codable {
    let wave_height: String?
    let wave_period: String?
    let wave_direction: String?
}

// MARK: - Service

@MainActor
class SurfForecastService: ObservableObject {
    static let shared = SurfForecastService()

    @Published var spotForecasts: [String: SpotWaveForecast] = [:]
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let baseURL = "https://marine-api.open-meteo.com/v1/marine"
    private let cache = NSCache<NSString, CachedForecast>()
    private let cacheExpiration: TimeInterval = 30 * 60 // 30 minutes

    private init() {
        cache.countLimit = 100
    }

    /// Récupère les prévisions de houle pour un spot
    func fetchForecast(for spot: SurfSpot) async {
        let cacheKey = NSString(string: spot.id)

        // Vérifier le cache
        if let cached = cache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.fetchedAt) < cacheExpiration {
            spotForecasts[spot.id] = cached.forecast
            return
        }

        isLoading = true
        lastError = nil

        do {
            let forecast = try await fetchFromAPI(spot: spot)
            spotForecasts[spot.id] = forecast
            cache.setObject(CachedForecast(forecast: forecast, fetchedAt: Date()), forKey: cacheKey)
        } catch {
            lastError = error.localizedDescription
            print("SurfForecast: Error fetching forecast for \(spot.name): \(error)")
        }

        isLoading = false
    }

    /// Récupère les prévisions pour plusieurs spots
    func fetchForecasts(for spots: [SurfSpot]) async {
        await withTaskGroup(of: Void.self) { group in
            for spot in spots {
                group.addTask {
                    await self.fetchForecast(for: spot)
                }
            }
        }
    }

    /// Prévision actuelle pour un spot
    func currentForecast(for spotId: String) -> SurfWaveForecast? {
        spotForecasts[spotId]?.current
    }

    /// Prévisions 24h pour un spot
    func forecasts24h(for spotId: String) -> [SurfWaveForecast] {
        spotForecasts[spotId]?.next24Hours ?? []
    }

    /// Fetch forecast directly by coordinates (for background tasks)
    func fetchForecastDirect(latitude: Double, longitude: Double) async throws -> [SurfWaveForecast] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]

        guard let url = components.url else {
            throw SurfForecastError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SurfForecastError.apiError
        }

        let apiResponse = try JSONDecoder().decode(MarineAPIResponse.self, from: data)
        return parseForecasts(from: apiResponse.hourly)
    }

    // MARK: - Private

    private func fetchFromAPI(spot: SurfSpot) async throws -> SpotWaveForecast {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", spot.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", spot.longitude)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]

        guard let url = components.url else {
            throw SurfForecastError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SurfForecastError.apiError
        }

        let apiResponse = try JSONDecoder().decode(MarineAPIResponse.self, from: data)

        let forecasts = parseForecasts(from: apiResponse.hourly)

        return SpotWaveForecast(
            spotId: spot.id,
            spotName: spot.name,
            latitude: spot.latitude,
            longitude: spot.longitude,
            forecasts: forecasts,
            fetchedAt: Date()
        )
    }

    private func parseForecasts(from hourly: MarineHourlyData) -> [SurfWaveForecast] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        var forecasts: [SurfWaveForecast] = []

        for (index, timeString) in hourly.time.enumerated() {
            // Parse ISO8601 date
            guard let timestamp = dateFormatter.date(from: timeString) ?? parseSimpleDate(timeString) else {
                continue
            }

            let forecast = SurfWaveForecast(
                timestamp: timestamp,
                waveHeight: hourly.wave_height?[safe: index] ?? nil,
                wavePeriod: hourly.wave_period?[safe: index] ?? nil,
                waveDirection: hourly.wave_direction?[safe: index] ?? nil,
                swellHeight: hourly.swell_wave_height?[safe: index] ?? nil,
                swellPeriod: hourly.swell_wave_period?[safe: index] ?? nil,
                swellDirection: hourly.swell_wave_direction?[safe: index] ?? nil
            )

            forecasts.append(forecast)
        }

        return forecasts
    }

    private func parseSimpleDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
}

// MARK: - Cache Helper

private class CachedForecast {
    let forecast: SpotWaveForecast
    let fetchedAt: Date

    init(forecast: SpotWaveForecast, fetchedAt: Date) {
        self.forecast = forecast
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Errors

enum SurfForecastError: Error, LocalizedError {
    case invalidURL
    case apiError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL invalide"
        case .apiError: return "Erreur API"
        case .decodingError: return "Erreur de décodage"
        }
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
