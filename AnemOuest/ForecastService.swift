import Foundation
import CoreLocation

// MARK: - Weather Models Enum

enum WeatherModel: String, CaseIterable, Identifiable {
    case arome = "arome"
    case ecmwf = "ecmwf"
    case gfs = "gfs"
    case icon = "icon"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arome: return "AROME"
        case .ecmwf: return "ECMWF"
        case .gfs: return "GFS"
        case .icon: return "ICON"
        }
    }

    var description: String {
        switch self {
        case .arome: return "Météo France - Haute résolution"
        case .ecmwf: return "Européen - 10 jours"
        case .gfs: return "Américain - 16 jours"
        case .icon: return "Allemand - 7 jours"
        }
    }

    var apiEndpoint: String {
        switch self {
        case .arome: return "https://api.open-meteo.com/v1/meteofrance"
        case .ecmwf: return "https://api.open-meteo.com/v1/ecmwf"
        case .gfs: return "https://api.open-meteo.com/v1/gfs"
        case .icon: return "https://api.open-meteo.com/v1/dwd-icon"
        }
    }

    var forecastDays: Int {
        switch self {
        case .arome: return 4
        case .ecmwf: return 10
        case .gfs: return 16
        case .icon: return 7
        }
    }

    var color: String {
        switch self {
        case .arome: return "blue"
        case .ecmwf: return "purple"
        case .gfs: return "green"
        case .icon: return "orange"
        }
    }
}

// MARK: - Forecast Models

struct HourlyForecast: Identifiable {
    let id = UUID()
    let time: Date
    let windSpeed: Double      // km/h -> convert to knots
    let windGusts: Double      // km/h -> convert to knots
    let windDirection: Double  // degrees
    let temperature: Double    // °C
    let precipitation: Double  // mm
    let weatherCode: Int
    let cloudCover: Int        // % total
    let cloudCoverLow: Int     // % low clouds
    let cloudCoverMid: Int     // % mid clouds
    let cloudCoverHigh: Int    // % high clouds
    let humidity: Int          // %
    let visibility: Double     // meters
    let pressureMSL: Double?   // hPa

    var windSpeedKnots: Double { windSpeed * 0.539957 }
    var gustsKnots: Double { windGusts * 0.539957 }

    var visibilityKm: Double { visibility / 1000 }

    var weatherDescription: String {
        switch weatherCode {
        case 0: return "Ciel dégagé"
        case 1, 2, 3: return "Peu nuageux"
        case 45, 48: return "Brouillard"
        case 51, 53, 55: return "Bruine"
        case 61, 63, 65: return "Pluie"
        case 66, 67: return "Pluie verglaçante"
        case 71, 73, 75: return "Neige"
        case 77: return "Grains de neige"
        case 80, 81, 82: return "Averses"
        case 85, 86: return "Averses de neige"
        case 95: return "Orage"
        case 96, 99: return "Orage avec grêle"
        default: return "—"
        }
    }

    var weatherIcon: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 61, 63, 65: return "cloud.drizzle.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

struct DailyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let windSpeedMax: Double
    let windGustsMax: Double
    let temperatureMin: Double
    let temperatureMax: Double
    let precipitationSum: Double
    let weatherCode: Int

    var windSpeedMaxKnots: Double { windSpeedMax * 0.539957 }
    var gustsMaxKnots: Double { windGustsMax * 0.539957 }
}

struct ForecastData {
    let hourly: [HourlyForecast]
    let daily: [DailyForecast]
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
    let model: WeatherModel
}

// MARK: - Wave Models

struct HourlyWave: Identifiable {
    let id = UUID()
    let time: Date
    let waveHeight: Double          // meters
    let wavePeriod: Double          // seconds
    let waveDirection: Double       // degrees
    let swellHeight: Double?        // meters (primary swell)
    let swellPeriod: Double?        // seconds
    let swellDirection: Double?     // degrees
    let windWaveHeight: Double?     // meters (wind waves)
    let windWavePeriod: Double?     // seconds
    let windWaveDirection: Double?  // degrees

    var waveHeightDescription: String {
        switch waveHeight {
        case ..<0.5: return "Calme"
        case ..<1.0: return "Peu agitée"
        case ..<1.5: return "Agitée"
        case ..<2.5: return "Forte"
        case ..<4.0: return "Très forte"
        default: return "Grosse"
        }
    }

    var waveIcon: String {
        switch waveHeight {
        case ..<0.5: return "water.waves"
        case ..<1.5: return "water.waves"
        case ..<2.5: return "water.waves"
        default: return "water.waves"
        }
    }
}

struct WaveData {
    let hourly: [HourlyWave]
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
}

// MARK: - API Response Models

private struct OpenMeteoResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let hourly: HourlyData?
    let daily: DailyData?

    struct HourlyData: Decodable {
        let time: [String]
        let wind_speed_10m: [Double?]?
        let wind_gusts_10m: [Double?]?
        let wind_direction_10m: [Double?]?
        let temperature_2m: [Double?]?
        let precipitation: [Double?]?
        let weather_code: [Int?]?
        let cloud_cover: [Int?]?
        let cloud_cover_low: [Int?]?
        let cloud_cover_mid: [Int?]?
        let cloud_cover_high: [Int?]?
        let relative_humidity_2m: [Int?]?
        let visibility: [Double?]?
        let pressure_msl: [Double?]?
    }

    struct DailyData: Decodable {
        let time: [String]
        let wind_speed_10m_max: [Double?]?
        let wind_gusts_10m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let temperature_2m_max: [Double?]?
        let precipitation_sum: [Double?]?
        let weather_code: [Int?]?
    }
}

private struct MarineResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let hourly: MarineHourlyData?

    struct MarineHourlyData: Decodable {
        let time: [String]
        let wave_height: [Double?]?
        let wave_period: [Double?]?
        let wave_direction: [Double?]?
        let swell_wave_height: [Double?]?
        let swell_wave_period: [Double?]?
        let swell_wave_direction: [Double?]?
        let wind_wave_height: [Double?]?
        let wind_wave_period: [Double?]?
        let wind_wave_direction: [Double?]?
    }
}

// MARK: - Forecast Service

final class ForecastService {

    static let shared = ForecastService()

    private init() {}

    enum ForecastError: Error {
        case badURL
        case networkError(Error)
        case decodingError(Error)
        case noData
    }

    // MARK: - Fetch Weather Forecast

    /// Fetch forecast using specified weather model
    func fetchForecast(
        latitude: Double,
        longitude: Double,
        model: WeatherModel = .arome,
        pastDays: Int = 0
    ) async throws -> ForecastData {
        let pastDaysParam = pastDays > 0 ? "&past_days=\(pastDays)" : ""

        // Build URL - all models use the same parameters
        let urlString = """
        \(model.apiEndpoint)?\
        latitude=\(latitude)&\
        longitude=\(longitude)&\
        hourly=temperature_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,relative_humidity_2m,visibility,pressure_msl&\
        daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max,wind_gusts_10m_max&\
        wind_speed_unit=kmh&\
        timezone=Europe/Paris&\
        forecast_days=\(model.forecastDays)\(pastDaysParam)
        """.replacingOccurrences(of: "\n", with: "")

        guard let url = URL(string: urlString) else {
            throw ForecastError.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConstants.Timeout.standard
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        let offlineKey = OfflineCache.forecastKey(lat: latitude, lon: longitude, model: model.rawValue)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Offline fallback: return cached data if available
            if let cached = OfflineCache.shared.load(CodableForecastData.self, forKey: offlineKey),
               let forecast = cached.data.toForecastData() {
                Log.network("Forecast offline fallback for \(model.rawValue)")
                return forecast
            }
            throw ForecastError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ForecastError.networkError(NSError(domain: "HTTP", code: http.statusCode))
        }

        let decoded: OpenMeteoResponse
        do {
            decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw ForecastError.decodingError(error)
        }

        // Parse hourly data
        var hourlyForecasts: [HourlyForecast] = []
        if let hourly = decoded.hourly {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

            let altFormatter = DateFormatter()
            altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            altFormatter.timeZone = TimeZone(identifier: "Europe/Paris")

            for i in 0..<hourly.time.count {
                guard let date = dateFormatter.date(from: hourly.time[i]) ?? altFormatter.date(from: hourly.time[i]) else { continue }

                let windSpeed = hourly.wind_speed_10m?[safe: i] ?? 0
                let windGusts = hourly.wind_gusts_10m?[safe: i] ?? 0
                let windDir = hourly.wind_direction_10m?[safe: i] ?? 0
                let temp = hourly.temperature_2m?[safe: i] ?? 0
                let precip = hourly.precipitation?[safe: i] ?? 0
                let weather = hourly.weather_code?[safe: i] ?? 0
                let cloud = hourly.cloud_cover?[safe: i] ?? 0
                let cloudLow = hourly.cloud_cover_low?[safe: i] ?? 0
                let cloudMid = hourly.cloud_cover_mid?[safe: i] ?? 0
                let cloudHigh = hourly.cloud_cover_high?[safe: i] ?? 0
                let humidity = hourly.relative_humidity_2m?[safe: i] ?? 0
                let vis = hourly.visibility?[safe: i] ?? 10000
                let pressure = hourly.pressure_msl?[safe: i] as Double?

                hourlyForecasts.append(HourlyForecast(
                    time: date,
                    windSpeed: windSpeed,
                    windGusts: windGusts,
                    windDirection: windDir,
                    temperature: temp,
                    precipitation: precip,
                    weatherCode: weather,
                    cloudCover: cloud,
                    cloudCoverLow: cloudLow,
                    cloudCoverMid: cloudMid,
                    cloudCoverHigh: cloudHigh,
                    humidity: humidity,
                    visibility: vis,
                    pressureMSL: pressure
                ))
            }
        }

        // Parse daily data
        var dailyForecasts: [DailyForecast] = []
        if let daily = decoded.daily {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "Europe/Paris")

            for i in 0..<daily.time.count {
                guard let date = dateFormatter.date(from: daily.time[i]) else { continue }

                dailyForecasts.append(DailyForecast(
                    date: date,
                    windSpeedMax: daily.wind_speed_10m_max?[safe: i] ?? 0,
                    windGustsMax: daily.wind_gusts_10m_max?[safe: i] ?? 0,
                    temperatureMin: daily.temperature_2m_min?[safe: i] ?? 0,
                    temperatureMax: daily.temperature_2m_max?[safe: i] ?? 0,
                    precipitationSum: daily.precipitation_sum?[safe: i] ?? 0,
                    weatherCode: daily.weather_code?[safe: i] ?? 0
                ))
            }
        }

        if hourlyForecasts.isEmpty {
            throw ForecastError.noData
        }

        let forecastData = ForecastData(
            hourly: hourlyForecasts,
            daily: dailyForecasts,
            fetchedAt: Date(),
            latitude: decoded.latitude,
            longitude: decoded.longitude,
            model: model
        )

        // Save to offline cache
        OfflineCache.shared.save(CodableForecastData(from: forecastData), forKey: offlineKey)

        return forecastData
    }

    // MARK: - Fetch Wave Data

    /// Fetch wave/marine forecast from Open-Meteo Marine API
    func fetchWaves(latitude: Double, longitude: Double, pastDays: Int = 0) async throws -> WaveData {
        let pastDaysParam = pastDays > 0 ? "&past_days=\(pastDays)" : ""

        let urlString = """
        https://marine-api.open-meteo.com/v1/marine?\
        latitude=\(latitude)&\
        longitude=\(longitude)&\
        hourly=wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,wind_wave_height,wind_wave_period,wind_wave_direction&\
        timezone=Europe/Paris&\
        forecast_days=7\(pastDaysParam)
        """.replacingOccurrences(of: "\n", with: "")

        guard let url = URL(string: urlString) else {
            throw ForecastError.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("AnemOuest/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ForecastError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ForecastError.networkError(NSError(domain: "HTTP", code: http.statusCode))
        }

        let decoded: MarineResponse
        do {
            decoded = try JSONDecoder().decode(MarineResponse.self, from: data)
        } catch {
            throw ForecastError.decodingError(error)
        }

        // Parse hourly wave data
        var hourlyWaves: [HourlyWave] = []
        if let hourly = decoded.hourly {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

            let altFormatter = DateFormatter()
            altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            altFormatter.timeZone = TimeZone(identifier: "Europe/Paris")

            for i in 0..<hourly.time.count {
                guard let date = dateFormatter.date(from: hourly.time[i]) ?? altFormatter.date(from: hourly.time[i]) else { continue }

                let waveHeight = hourly.wave_height?[safe: i] ?? 0
                let wavePeriod = hourly.wave_period?[safe: i] ?? 0
                let waveDir = hourly.wave_direction?[safe: i] ?? 0

                hourlyWaves.append(HourlyWave(
                    time: date,
                    waveHeight: waveHeight,
                    wavePeriod: wavePeriod,
                    waveDirection: waveDir,
                    swellHeight: hourly.swell_wave_height?[safe: i],
                    swellPeriod: hourly.swell_wave_period?[safe: i],
                    swellDirection: hourly.swell_wave_direction?[safe: i],
                    windWaveHeight: hourly.wind_wave_height?[safe: i],
                    windWavePeriod: hourly.wind_wave_period?[safe: i],
                    windWaveDirection: hourly.wind_wave_direction?[safe: i]
                ))
            }
        }

        if hourlyWaves.isEmpty {
            throw ForecastError.noData
        }

        return WaveData(
            hourly: hourlyWaves,
            fetchedAt: Date(),
            latitude: decoded.latitude,
            longitude: decoded.longitude
        )
    }

    // MARK: - Fetch All Models (for comparison)

    /// Fetch forecasts from multiple models for comparison
    func fetchAllModels(latitude: Double, longitude: Double) async -> [WeatherModel: ForecastData] {
        var results: [WeatherModel: ForecastData] = [:]

        await withTaskGroup(of: (WeatherModel, ForecastData?).self) { group in
            for model in WeatherModel.allCases {
                group.addTask {
                    do {
                        let data = try await self.fetchForecast(latitude: latitude, longitude: longitude, model: model)
                        return (model, data)
                    } catch {
                        Log.error("Failed to fetch \(model.displayName): \(error)")
                        return (model, nil)
                    }
                }
            }

            for await (model, data) in group {
                if let data = data {
                    results[model] = data
                }
            }
        }

        return results
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

private extension Array where Element == Double? {
    subscript(safe index: Int) -> Double {
        guard index >= 0 && index < count else { return 0 }
        return self[index] ?? 0
    }
}

private extension Array where Element == Int? {
    subscript(safe index: Int) -> Int {
        guard index >= 0 && index < count else { return 0 }
        return self[index] ?? 0
    }
}
